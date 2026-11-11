import Darwin
import Foundation
import Synchronization

/// Un nœud de la carte du disque : dossier, fichier ou regroupement des petits éléments.
public struct DiskNode: Sendable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case directory
        case file
        /// Petits éléments d'un dossier, regroupés en un seul bloc.
        case others(count: Int)
    }

    /// Chemin sur le disque (pour un regroupement : chemin du dossier suivi de `/…`).
    public let path: String
    public let name: String
    public let kind: Kind
    /// Espace réellement alloué (blocs × 512), contenu compris.
    public let allocatedBytes: Int64
    /// Nombre de fichiers contenus.
    public let fileCount: Int
    public let modified: Date?
    /// Contenu trié du plus gros au plus petit ; le regroupement éventuel est en dernier.
    public let children: [DiskNode]

    public var id: String { path }
    public var isDirectory: Bool { kind == .directory }

    /// Le nœud situé à ce chemin, s'il est dans la carte.
    public func descendant(at target: String) -> DiskNode? {
        if target == path { return self }
        let prefix = path == "/" ? "/" : path + "/"
        guard target.hasPrefix(prefix) else { return nil }
        for child in children where child.isDirectory {
            if let found = child.descendant(at: target) { return found }
        }
        return nil
    }
}

/// Un gros fichier repéré pendant la cartographie.
public struct LargeFile: Sendable, Identifiable, Equatable {
    public let path: String
    public let allocatedBytes: Int64
    public let modified: Date
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
}

/// Carte complète d'un dossier ou d'un volume.
public struct DiskMap: Sendable {
    public let root: DiskNode
    /// Les plus gros fichiers, du plus gros au plus petit.
    public let largestFiles: [LargeFile]
    /// Éléments illisibles (droits insuffisants…).
    public let unreadableCount: Int
    public let duration: Duration
}

/// Avancement de la cartographie (le total n'est pas connu d'avance).
public struct DiskMapProgress: Sendable, Equatable {
    public var filesVisited: Int
    public var bytesFound: Int64
    public var currentPath: String
}

public enum DiskMapError: Error, LocalizedError, Equatable {
    case unreadableRoot(String)

    public var errorDescription: String? {
        switch self {
        case let .unreadableRoot(path): "Impossible de lire le dossier « \(path) »."
        }
    }
}

/// Cartographie d'un dossier : lecture seule, asynchrone, annulable, avec progression.
/// Les liens symboliques ne sont jamais suivis, les liens physiques ne comptent qu'une fois
/// et l'analyse ne sort pas du volume de départ (disques externes, volumes montés).
/// Les premiers niveaux de dossiers sont lus en parallèle (le disque répond mieux à plusieurs lectures).
public struct DiskMapper: Sendable {
    /// Nombre maximal d'éléments gardés par dossier (le reste est regroupé).
    public var maxChildren = 40
    /// Les plus gros éléments d'un dossier toujours gardés, quelle que soit leur taille.
    public var alwaysKept = 8
    /// Au-delà, seuls les éléments au moins aussi gros sont gardés.
    public var minKeptBytes: Int64 = 1 << 20
    /// Nombre de gros fichiers retenus.
    public var largeFileCount = 60
    /// Taille minimale d'un « gros fichier ».
    public var largeFileMinimum: Int64 = 50 << 20
    /// Fréquence des vérifications d'annulation et des rapports de progression.
    public var reportEvery = 2_000
    /// Profondeur jusqu'à laquelle les sous-dossiers sont lus en parallèle.
    public var parallelDepth = 2
    /// Lectures simultanées au plus, par dossier parallélisé.
    public var maxConcurrent = 8

    public init() {}

    /// Cartographie `root`. Lève `CancellationError` en cas d'annulation.
    /// - Parameter name: nom affiché pour la racine (par défaut, le dernier composant du chemin).
    @concurrent
    public func map(
        _ root: String,
        name: String? = nil,
        progress: (@Sendable (DiskMapProgress) -> Void)? = nil
    ) async throws -> DiskMap {
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let start = clock.now
        var st = stat()
        guard lstat(root, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            throw DiskMapError.unreadableRoot(root)
        }
        let shared = WalkShared(config: self, device: st.st_dev, progress: progress)
        let last = (root as NSString).lastPathComponent
        let node = try await directory(path: root, name: name ?? (last.isEmpty ? root : last),
                                       stat: st, depth: 0, shared: shared)
        let totals = shared.totals
        progress?(DiskMapProgress(filesVisited: totals.visited, bytesFound: totals.bytes, currentPath: root))
        return DiskMap(root: node, largestFiles: totals.largest,
                       unreadableCount: totals.unreadable, duration: clock.now - start)
    }

    private func directory(path: String, name: String, stat st: stat, depth: Int, shared: WalkShared) async throws -> DiskNode {
        let walk = Walk(shared: shared)
        defer { walk.flush() }
        guard depth < parallelDepth else {
            return try walk.directory(path: path, name: name, stat: st)
        }
        guard let listing = try walk.read(path: path, stat: st) else {
            return walk.unreadableDirectory(path: path, name: name, stat: st)
        }
        walk.flush()
        var items = listing.files
        let prefix = Walk.prefix(path)
        try await withThrowingTaskGroup(of: DiskNode.self) { group in
            var pending = listing.subdirectories[...]
            func launch() {
                guard let sub = pending.popFirst() else { return }
                group.addTask {
                    try await directory(path: prefix + sub.name, name: sub.name, stat: sub.stat,
                                        depth: depth + 1, shared: shared)
                }
            }
            for _ in 0..<maxConcurrent { launch() }
            while let node = try await group.next() {
                items.append(node)
                launch()
            }
        }
        return walk.assemble(path: path, name: name, stat: st, items: items)
    }
}

/// Compteurs et listes partagés entre les lectures parallèles.
private final class WalkShared: Sendable {
    struct InodeKey: Hashable {
        let device: Int32
        let inode: UInt64
    }

    struct Totals {
        var visited = 0
        var bytes: Int64 = 0
        var unreadable = 0
        var largest: [LargeFile] = []
        var seen = Set<InodeKey>()
    }

    let config: DiskMapper
    let device: dev_t
    let progress: (@Sendable (DiskMapProgress) -> Void)?
    private let state = Mutex(Totals())

    init(config: DiskMapper, device: dev_t, progress: (@Sendable (DiskMapProgress) -> Void)?) {
        self.config = config
        self.device = device
        self.progress = progress
    }

    var totals: Totals { state.withLock { $0 } }

    /// Ajoute les compteurs d'une lecture ; renvoie les totaux à jour.
    func add(visited: Int, bytes: Int64, unreadable: Int) -> (visited: Int, bytes: Int64) {
        state.withLock {
            $0.visited += visited
            $0.bytes += bytes
            $0.unreadable += unreadable
            return ($0.visited, $0.bytes)
        }
    }

    /// Vrai la première fois qu'un fichier à liens physiques est vu.
    func firstSighting(device: Int32, inode: UInt64) -> Bool {
        state.withLock { $0.seen.insert(InodeKey(device: device, inode: inode)).inserted }
    }

    func record(_ file: LargeFile) {
        let cap = config.largeFileCount
        state.withLock { totals in
            if totals.largest.count >= cap, let last = totals.largest.last, last.allocatedBytes >= file.allocatedBytes {
                return
            }
            let index = totals.largest.firstIndex { $0.allocatedBytes < file.allocatedBytes } ?? totals.largest.endIndex
            totals.largest.insert(file, at: index)
            if totals.largest.count > cap { totals.largest.removeLast() }
        }
    }
}

/// Une lecture séquentielle (utilisée par une seule tâche).
private final class Walk {
    struct Listing {
        var ownBytes: Int64
        var files: [DiskNode]
        var subdirectories: [(name: String, stat: stat)]
    }

    let shared: WalkShared
    private var config: DiskMapper { shared.config }
    private var pendingVisited = 0
    private var pendingBytes: Int64 = 0
    private var pendingUnreadable = 0

    init(shared: WalkShared) {
        self.shared = shared
    }

    static func prefix(_ path: String) -> String { path == "/" ? "/" : path + "/" }

    /// Lit tout un dossier, récursivement.
    func directory(path: String, name: String, stat st: stat) throws -> DiskNode {
        guard let listing = try read(path: path, stat: st) else {
            return unreadableDirectory(path: path, name: name, stat: st)
        }
        var items = listing.files
        let prefix = Self.prefix(path)
        for sub in listing.subdirectories {
            items.append(try directory(path: prefix + sub.name, name: sub.name, stat: sub.stat))
        }
        return assemble(path: path, name: name, stat: st, items: items)
    }

    /// Lit le contenu direct d'un dossier ; `nil` s'il est illisible.
    /// Le descripteur est refermé avant de descendre (un seul ouvert par lecture).
    func read(path: String, stat st: stat) throws -> Listing? {
        pendingBytes += Int64(st.st_blocks) * 512
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            pendingUnreadable += 1
            return nil
        }
        guard let dir = fdopendir(fd) else {
            close(fd)
            pendingUnreadable += 1
            return nil
        }
        let prefix = Self.prefix(path)
        var listing = Listing(ownBytes: Int64(st.st_blocks) * 512, files: [], subdirectories: [])
        var cancelled = false
        while let entry = readdir(dir) {
            let entryName = withUnsafeMutablePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if entryName == "." || entryName == ".." { continue }
            var child = stat()
            guard fstatat(fd, entryName, &child, AT_SYMLINK_NOFOLLOW) == 0 else {
                pendingUnreadable += 1
                continue
            }
            if tick(path) { cancelled = true; break }
            if (child.st_mode & S_IFMT) == S_IFDIR {
                // Point de montage d'un autre volume : on ne le traverse pas.
                if child.st_dev == shared.device { listing.subdirectories.append((entryName, child)) }
                continue
            }
            if child.st_nlink > 1, !shared.firstSighting(device: child.st_dev, inode: child.st_ino) {
                continue
            }
            let size = Int64(child.st_blocks) * 512
            pendingBytes += size
            let fileDate = Self.date(child.st_mtimespec)
            listing.files.append(DiskNode(path: prefix + entryName, name: entryName, kind: .file,
                                          allocatedBytes: size, fileCount: 1, modified: fileDate, children: []))
            if size >= config.largeFileMinimum {
                shared.record(LargeFile(path: prefix + entryName, allocatedBytes: size, modified: fileDate))
            }
        }
        closedir(dir)
        if cancelled { throw CancellationError() }
        return listing
    }

    func unreadableDirectory(path: String, name: String, stat st: stat) -> DiskNode {
        DiskNode(path: path, name: name, kind: .directory, allocatedBytes: Int64(st.st_blocks) * 512,
                 fileCount: 0, modified: Self.date(st.st_mtimespec), children: [])
    }

    /// Construit le nœud d'un dossier à partir de son contenu.
    func assemble(path: String, name: String, stat st: stat, items: [DiskNode]) -> DiskNode {
        let total = items.reduce(Int64(st.st_blocks) * 512) { $0 + $1.allocatedBytes }
        let files = items.reduce(0) { $0 + $1.fileCount }
        return DiskNode(path: path, name: name, kind: .directory, allocatedBytes: total, fileCount: files,
                        modified: Self.date(st.st_mtimespec), children: prune(items, in: Self.prefix(path)))
    }

    /// Reporte les compteurs locaux dans les totaux partagés.
    func flush() {
        guard pendingVisited > 0 || pendingBytes > 0 || pendingUnreadable > 0 else { return }
        _ = shared.add(visited: pendingVisited, bytes: pendingBytes, unreadable: pendingUnreadable)
        pendingVisited = 0
        pendingBytes = 0
        pendingUnreadable = 0
    }

    /// Garde les plus gros éléments et regroupe les autres en un seul bloc.
    private func prune(_ items: [DiskNode], in prefix: String) -> [DiskNode] {
        let sorted = items.sorted { $0.allocatedBytes > $1.allocatedBytes }
        var kept: [DiskNode] = []
        var restCount = 0
        var restBytes: Int64 = 0
        var restFiles = 0
        for (index, item) in sorted.enumerated() {
            let keep = kept.count < config.maxChildren
                && (index < config.alwaysKept || item.allocatedBytes >= config.minKeptBytes)
            if keep {
                kept.append(item)
            } else {
                restCount += 1
                restBytes += item.allocatedBytes
                restFiles += item.fileCount
            }
        }
        if restCount > 0 {
            kept.append(DiskNode(path: prefix + "…", name: "\(restCount) autres éléments", kind: .others(count: restCount),
                                 allocatedBytes: restBytes, fileCount: restFiles, modified: nil, children: []))
        }
        return kept
    }

    /// Compte un élément vu ; renvoie `true` si la tâche est annulée.
    private func tick(_ path: String) -> Bool {
        pendingVisited += 1
        guard pendingVisited >= config.reportEvery else { return false }
        if Task.isCancelled { return true }
        let unreadable = pendingUnreadable
        let totals = shared.add(visited: pendingVisited, bytes: pendingBytes, unreadable: unreadable)
        pendingVisited = 0
        pendingBytes = 0
        pendingUnreadable = 0
        shared.progress?(DiskMapProgress(filesVisited: totals.visited, bytesFound: totals.bytes, currentPath: path))
        return false
    }

    private static func date(_ spec: timespec) -> Date {
        Date(timeIntervalSince1970: Double(spec.tv_sec) + Double(spec.tv_nsec) / 1_000_000_000)
    }
}
