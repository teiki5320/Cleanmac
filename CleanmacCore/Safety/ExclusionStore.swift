import Foundation

/// Liste d'exclusions de l'utilisateur, enregistrée dans le dossier de l'appli.
public struct ExclusionStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("exclusions.json")) {
        self.fileURL = fileURL
    }

    public func load() -> [String] {
        (try? loadStrict()) ?? []
    }

    /// Lecture qui échoue si le fichier existe mais est illisible : mieux vaut bloquer le nettoyage
    /// que d'oublier les exclusions de l'utilisateur.
    public func loadStrict() throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String].self, from: data)
    }

    public func save(_ paths: [String]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let unique = Array(Set(paths)).sorted()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(unique).write(to: fileURL, options: .atomic)
    }

    public func add(_ path: String) throws {
        try save(loadStrict() + [path])
    }

    public func remove(_ path: String) throws {
        try save(loadStrict().filter { $0 != path })
    }
}

/// Emplacements de l'appli sur le disque.
public enum AppPaths {
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cleanmac", isDirectory: true)
    }
}
