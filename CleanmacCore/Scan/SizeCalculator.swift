import Darwin
import Foundation

/// Résultat de la mesure d'un élément (fichier ou dossier).
public struct SizeMeasurement: Sendable, Equatable {
    /// Espace réellement alloué sur le disque, en octets (blocs × 512).
    public var allocatedBytes: Int64 = 0
    /// Nombre de fichiers (hors dossiers).
    public var fileCount: Int = 0
    /// Éléments illisibles (droits insuffisants…).
    public var unreadableCount: Int = 0
    /// Chemin du premier `.git` rencontré à l'intérieur, s'il y en a un.
    public var gitDirectory: String?
}

/// Calcul des tailles réelles (espace alloué), sans suivre les liens symboliques.
/// Les liens physiques (hard links) ne sont comptés qu'une fois.
public struct SizeCalculator: Sendable {
    /// Fréquence des vérifications d'annulation et des rapports de progression.
    public var reportEvery = 1_000

    public init() {}

    /// Mesure un fichier ou un dossier. Lève `CancellationError` si la tâche est annulée.
    /// - Parameter onFiles: appelé régulièrement avec le nombre de fichiers vus depuis le dernier appel.
    public func measure(
        _ path: String,
        stopAtGit: Bool = false,
        onFiles: ((Int) -> Void)? = nil
    ) throws -> SizeMeasurement {
        var result = SizeMeasurement()
        var seenInodes = Set<InodeKey>()

        var st = stat()
        guard lstat(path, &st) == 0 else {
            result.unreadableCount = 1
            return result
        }
        add(st, to: &result, seen: &seenInodes)
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return result }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        var unreadable = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [],
            options: [],
            errorHandler: { _, _ in
                unreadable += 1
                return true
            }
        ) else {
            result.unreadableCount += 1
            return result
        }

        var sinceReport = 0
        for case let child as URL in enumerator {
            sinceReport += 1
            if sinceReport >= reportEvery {
                try Task.checkCancellation()
                onFiles?(sinceReport)
                sinceReport = 0
            }
            if child.lastPathComponent == ".git", result.gitDirectory == nil {
                result.gitDirectory = child.path
                if stopAtGit { break }
            }
            var childStat = stat()
            let ok = child.withUnsafeFileSystemRepresentation { rep in
                guard let rep else { return false }
                return lstat(rep, &childStat) == 0
            }
            if ok {
                add(childStat, to: &result, seen: &seenInodes)
            } else {
                unreadable += 1
            }
        }
        try Task.checkCancellation()
        onFiles?(sinceReport)
        result.unreadableCount += unreadable
        return result
    }

    private struct InodeKey: Hashable {
        let device: Int32
        let inode: UInt64
    }

    private func add(_ st: stat, to result: inout SizeMeasurement, seen: inout Set<InodeKey>) {
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        if !isDir && st.st_nlink > 1 {
            guard seen.insert(InodeKey(device: st.st_dev, inode: st.st_ino)).inserted else { return }
        }
        result.allocatedBytes += Int64(st.st_blocks) * 512
        if !isDir { result.fileCount += 1 }
    }
}
