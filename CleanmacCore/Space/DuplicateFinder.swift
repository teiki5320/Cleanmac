import CryptoKit
import Darwin
import Foundation

/// Un exemplaire d'un fichier en double.
public struct DuplicateFile: Sendable, Identifiable, Hashable {
    public let path: String
    /// Espace alloué sur le disque.
    public let allocatedBytes: Int64
    public let modified: Date
    /// Copie APFS (« clone ») : le fichier peut partager ses blocs avec un autre,
    /// le supprimer ne libère alors peut-être rien.
    public let mayShareBlocks: Bool

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, allocatedBytes: Int64, modified: Date, mayShareBlocks: Bool) {
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.modified = modified
        self.mayShareBlocks = mayShareBlocks
    }
}

/// Fichiers au contenu identique (même taille, même empreinte SHA-256).
public struct DuplicateGroup: Sendable, Identifiable {
    /// Empreinte du contenu.
    public let id: String
    /// Taille du contenu, en octets.
    public let size: Int64
    /// Exemplaires ; le premier est celui qu'on suggère de garder.
    public let files: [DuplicateFile]

    public init(id: String, size: Int64, files: [DuplicateFile]) {
        self.id = id
        self.size = size
        self.files = files
    }

    public var kind: FileKind { FileKind.of(files.first?.path ?? "") }
    public var suggestedKeep: DuplicateFile? { files.first }

    /// Espace occupé par les exemplaires en trop (sans compter les copies APFS, qui partagent leurs blocs).
    public var wastedBytes: Int64 {
        files.dropFirst().filter { !$0.mayShareBlocks }.reduce(0) { $0 + $1.allocatedBytes }
    }

    /// Au moins un exemplaire est une copie APFS.
    public var hasClones: Bool { files.contains(where: \.mayShareBlocks) }
}

public struct DuplicateScan: Sendable {
    /// Groupes, du plus d'espace perdu au moins.
    public let groups: [DuplicateGroup]
    /// Fichiers examinés (assez gros pour être comparés).
    public let filesExamined: Int
    public let unreadableCount: Int
    public let duration: Duration

    public init(groups: [DuplicateGroup], filesExamined: Int, unreadableCount: Int, duration: Duration) {
        self.groups = groups
        self.filesExamined = filesExamined
        self.unreadableCount = unreadableCount
        self.duration = duration
    }

    public var wastedBytes: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
}

public struct DuplicateProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Inventaire des fichiers.
        case listing
        /// Comparaison du contenu des fichiers de même taille.
        case comparing
    }

    public var phase: Phase
    public var filesSeen: Int
    /// Fichiers à comparer (même taille qu'un autre) et déjà comparés.
    public var candidates: Int
    public var compared: Int
    public var currentPath: String
    /// Octets à lire au plus (tous les candidats en entier) et déjà traités :
    /// la jauge avance aussi pendant la lecture complète des gros fichiers.
    public var bytesTotal: Int64 = 0
    public var bytesDone: Int64 = 0

    public var fractionCompleted: Double? {
        guard phase == .comparing, candidates > 0 else { return nil }
        if bytesTotal > 0 { return min(1, Double(bytesDone) / Double(bytesTotal)) }
        return Double(compared) / Double(candidates)
    }
}

/// Recherche des doublons : lecture seule, asynchrone, annulable, avec progression.
/// Les fichiers sont d'abord regroupés par taille, puis comparés par empreinte du début,
/// puis par empreinte complète. Liens physiques, fichiers iCloud non téléchargés,
/// dossiers cachés, paquets (applis, photothèques…) et dépôts de code sont ignorés.
public struct DuplicateFinder: Sendable {
    /// Taille minimale des fichiers comparés.
    public var minimumSize: Int64 = 1 << 20
    /// Taille de l'empreinte rapide (début du fichier).
    public var headBytes = 64 * 1024
    public var reportEvery = 500
    /// Extensions des dossiers traités comme un seul document (jamais ouverts).
    public var packageExtensions: Set<String> = [
        "app", "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "aplibrary", "lrlibrary",
        "fcpbundle", "imovielibrary", "logicx", "band", "bundle", "framework", "plugin", "kext",
        "xcodeproj", "xcworkspace", "xcarchive", "sparsebundle", "pkg", "mpkg", "theater",
    ]

    public init() {}

    /// Cherche les doublons sous `roots`, sans entrer dans `excluded` (chemins absolus).
    @concurrent
    public func find(
        in roots: [String],
        excluding excluded: [String] = [],
        progress: (@Sendable (DuplicateProgress) -> Void)? = nil
    ) async throws -> DuplicateScan {
        let clock = ContinuousClock()
        let start = clock.now
        var inventory = Inventory(finder: self, excluded: Set(excluded), progress: progress)
        for root in roots {
            try inventory.walk(root)
        }

        // Seules les tailles partagées par plusieurs fichiers peuvent cacher des doublons.
        let candidates = inventory.bySize.values.filter { $0.count > 1 }
        var state = DuplicateProgress(
            phase: .comparing, filesSeen: inventory.seen,
            candidates: candidates.reduce(0) { $0 + $1.count }, compared: 0, currentPath: "")
        state.bytesTotal = candidates.joined().reduce(Int64(0)) { $0 + $1.size }
        progress?(state)
        let head = Int64(headBytes)

        var groups: [DuplicateGroup] = []
        var unreadable = inventory.unreadable
        for sameSize in candidates {
            try Task.checkCancellation()
            // 1. Empreinte du début du fichier.
            var byHead: [String: [Entry]] = [:]
            for entry in sameSize {
                try Task.checkCancellation()
                state.compared += 1
                state.currentPath = entry.path
                state.bytesDone += min(entry.size, head)
                if state.compared % 50 == 0 { progress?(state) }
                if let digest = try Self.digest(entry.path, limit: headBytes) {
                    byHead[digest, default: []].append(entry)
                } else {
                    unreadable += 1
                    state.bytesDone += max(0, entry.size - head)
                }
            }
            // Fichiers sans jumeau au début : leur suite ne sera pas lue.
            for alone in byHead.values where alone.count == 1 {
                state.bytesDone += max(0, alone[0].size - head)
            }
            // 2. Empreinte complète, si le fichier dépasse le début déjà lu.
            for sameHead in byHead.values where sameHead.count > 1 {
                var byFull: [String: [Entry]] = [:]
                if sameHead[0].size <= head {
                    byFull[UUID().uuidString] = sameHead
                } else {
                    for entry in sameHead {
                        try Task.checkCancellation()
                        let base = state.bytesDone
                        state.currentPath = entry.path
                        progress?(state)
                        let full = try Self.digest(entry.path, limit: nil) { read in
                            state.bytesDone = base + max(0, Int64(read) - head)
                            progress?(state)
                        }
                        state.bytesDone = base + max(0, entry.size - head)
                        if let full {
                            byFull[full, default: []].append(entry)
                        } else {
                            unreadable += 1
                        }
                    }
                }
                for (hash, entries) in byFull where entries.count > 1 {
                    let files = Self.ordered(entries.map(\.file))
                    groups.append(DuplicateGroup(id: hash, size: entries[0].size, files: files))
                }
            }
        }
        progress?(state)
        groups.sort { ($0.wastedBytes, $0.size) > ($1.wastedBytes, $1.size) }
        return DuplicateScan(groups: groups, filesExamined: inventory.examined,
                             unreadableCount: unreadable, duration: clock.now - start)
    }

    /// Ordre de suggestion : d'abord ce qui n'est pas dans Téléchargements, puis le plus ancien,
    /// puis le chemin le plus court.
    static func ordered(_ files: [DuplicateFile]) -> [DuplicateFile] {
        func inDownloads(_ file: DuplicateFile) -> Bool {
            file.path.contains("/Downloads/") || file.path.contains("/Téléchargements/")
        }
        return files.sorted { a, b in
            if inDownloads(a) != inDownloads(b) { return !inDownloads(a) }
            if a.modified != b.modified { return a.modified < b.modified }
            if a.path.count != b.path.count { return a.path.count < b.path.count }
            return a.path < b.path
        }
    }

    /// Empreinte SHA-256 des `limit` premiers octets (tout le fichier si `nil`) ; `nil` si illisible.
    /// `onRead` reçoit régulièrement le nombre d'octets lus depuis le début (tous les 32 Mo).
    static func digest(_ path: String, limit: Int?, onRead: ((Int) -> Void)? = nil) throws -> String? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var hasher = SHA256()
        let chunk = 1 << 20
        var buffer = [UInt8](repeating: 0, count: chunk)
        var remaining = limit ?? Int.max
        var total = 0
        var chunks = 0
        while remaining > 0 {
            try Task.checkCancellation()
            let wanted = min(chunk, remaining)
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, wanted) }
            if count < 0 { return nil }
            if count == 0 { break }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
            remaining -= count
            total += count
            chunks += 1
            if chunks % 32 == 0 { onRead?(total) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Vrai si le fichier peut partager ses blocs avec un autre (copie APFS).
    public static func mayShareBlocks(_ path: String) -> Bool {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_EXT_FLAGS)
        var buffer = [UInt8](repeating: 0, count: 32)
        let options = UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW)
        let result = buffer.withUnsafeMutableBytes { getattrlist(path, &list, $0.baseAddress, $0.count, options) }
        guard result == 0 else { return false }
        // Réponse : longueur (UInt32), puis les drapeaux étendus (UInt64).
        let flags = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt64.self) }
        return flags & UInt64(EF_MAY_SHARE_BLOCKS) != 0
    }
}

private struct Entry {
    let path: String
    let size: Int64
    let file: DuplicateFile
}

/// Inventaire des fichiers, regroupés par taille.
private struct Inventory {
    struct InodeKey: Hashable {
        let device: Int32
        let inode: UInt64
    }

    let finder: DuplicateFinder
    let excluded: Set<String>
    let progress: (@Sendable (DuplicateProgress) -> Void)?
    var bySize: [Int64: [Entry]] = [:]
    var inodes = Set<InodeKey>()
    var seen = 0
    var examined = 0
    var unreadable = 0

    init(finder: DuplicateFinder, excluded: Set<String>, progress: (@Sendable (DuplicateProgress) -> Void)?) {
        self.finder = finder
        self.excluded = excluded
        self.progress = progress
    }

    mutating func walk(_ root: String) throws {
        var st = stat()
        guard lstat(root, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            unreadable += 1
            return
        }
        try directory(root, device: st.st_dev)
    }

    private mutating func directory(_ path: String, device: dev_t) throws {
        if excluded.contains(path) { return }
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            unreadable += 1
            return
        }
        guard let dir = fdopendir(fd) else {
            close(fd)
            unreadable += 1
            return
        }
        let prefix = path == "/" ? "/" : path + "/"
        var subdirectories: [String] = []
        var files: [Entry] = []
        var isRepository = false
        var cancelled = false
        while let entry = readdir(dir) {
            let name = withUnsafeMutablePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == ".git" { isRepository = true; break }
            // Dossiers et fichiers cachés : gérés par les applis, jamais comparés.
            if name.hasPrefix(".") { continue }
            var child = stat()
            guard fstatat(fd, name, &child, AT_SYMLINK_NOFOLLOW) == 0 else {
                unreadable += 1
                continue
            }
            seen += 1
            if seen % finder.reportEvery == 0 {
                if Task.isCancelled { cancelled = true; break }
                progress?(DuplicateProgress(phase: .listing, filesSeen: seen, candidates: 0, compared: 0, currentPath: path))
            }
            switch child.st_mode & S_IFMT {
            case S_IFDIR:
                let ext = (name as NSString).pathExtension.lowercased()
                if child.st_dev == device, !finder.packageExtensions.contains(ext) {
                    subdirectories.append(prefix + name)
                }
            case S_IFREG:
                guard child.st_size >= finder.minimumSize else { continue }
                // Fichier iCloud non téléchargé : le lire le téléchargerait.
                if child.st_flags & UInt32(SF_DATALESS) != 0 { continue }
                if child.st_nlink > 1, !inodes.insert(InodeKey(device: child.st_dev, inode: child.st_ino)).inserted {
                    continue
                }
                let filePath = prefix + name
                let file = DuplicateFile(
                    path: filePath,
                    allocatedBytes: Int64(child.st_blocks) * 512,
                    modified: Date(timeIntervalSince1970: Double(child.st_mtimespec.tv_sec)),
                    mayShareBlocks: DuplicateFinder.mayShareBlocks(filePath))
                files.append(Entry(path: filePath, size: Int64(child.st_size), file: file))
            default:
                continue
            }
        }
        closedir(dir)
        if cancelled { throw CancellationError() }
        // Dépôt de code : protégé, on n'y cherche pas de doublons.
        if isRepository { return }
        examined += files.count
        for file in files { bySize[file.size, default: []].append(file) }
        for sub in subdirectories {
            try directory(sub, device: device)
        }
    }
}
