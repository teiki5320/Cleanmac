import Foundation
@testable import CleanmacCore

/// Faux dossier personnel temporaire, supprimé à la fin du test.
final class FakeHome {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanmacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Chemin réel (sans le lien /var → /private/var) pour des comparaisons fiables.
        path = base.withUnsafeFileSystemRepresentation { rep in
            guard let rep, let real = realpath(rep, nil) else { return base.path }
            defer { free(real) }
            return String(cString: real)
        }
    }

    deinit {
        // Nettoyage du dossier temporaire créé par le test lui-même.
        try? FileManager.default.removeItem(atPath: path)
    }

    func url(_ relative: String) -> String { path + "/" + relative }

    @discardableResult
    func file(_ relative: String, bytes: Int = 10) throws -> String {
        let full = url(relative)
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: URL(fileURLWithPath: full))
        return full
    }

    @discardableResult
    func dir(_ relative: String) throws -> String {
        let full = url(relative)
        try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }
}

/// Faux suppresseur : enregistre les appels sans rien supprimer.
final class RecordingRemover: FileRemoving, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var trashed: [String] = []
    private(set) var removed: [String] = []

    func trash(_ path: String) throws -> String? {
        lock.withLock { trashed.append(path) }
        return "/fake/.Trash/" + (path as NSString).lastPathComponent
    }

    func removePermanently(_ path: String) throws {
        lock.withLock { removed.append(path) }
    }
}

func makeRule(
    id: String = "test.caches",
    risk: RiskLevel = .safe,
    paths: [String] = ["~/Library/Caches/*"],
    excludes: [String] = [],
    regenerable: Bool = false
) -> Rule {
    Rule(
        id: id, name: "Règle \(id)", category: .systemJunk, risk: risk,
        explanation: "Test", paths: paths, excludes: excludes, regenerable: regenerable)
}
