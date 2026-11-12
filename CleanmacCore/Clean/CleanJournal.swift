import Foundation

/// Façon dont un élément a été supprimé.
public enum RemovalMethod: String, Codable, Sendable {
    case trash
    case permanent
    /// Fichier iCloud libéré du Mac : il reste dans iCloud et se retélécharge à l'ouverture.
    case evicted

    public var label: String {
        switch self {
        case .trash: "Mis à la Corbeille"
        case .permanent: "Supprimé définitivement"
        case .evicted: "Libéré du Mac, toujours dans iCloud"
        }
    }
}

/// Une ligne du journal : un élément traité lors d'un nettoyage.
public struct JournalItem: Codable, Sendable, Equatable {
    public let path: String
    public let ruleID: String
    public let bytes: Int64
    public let method: RemovalMethod
    public let succeeded: Bool
    public let message: String?
    /// Emplacement dans la Corbeille, si l'élément y a été mis.
    public let trashedPath: String?

    public init(path: String, ruleID: String, bytes: Int64, method: RemovalMethod,
                succeeded: Bool, message: String?, trashedPath: String?) {
        self.path = path
        self.ruleID = ruleID
        self.bytes = bytes
        self.method = method
        self.succeeded = succeeded
        self.message = message
        self.trashedPath = trashedPath
    }
}

/// Un nettoyage complet.
public struct JournalEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let items: [JournalItem]

    public init(id: UUID = UUID(), date: Date = Date(), items: [JournalItem]) {
        self.id = id
        self.date = date
        self.items = items
    }

    /// Tout ce qui a été traité (Corbeille, définitif, iCloud).
    public var freedBytes: Int64 {
        items.filter(\.succeeded).reduce(0) { $0 + $1.bytes }
    }

    /// Place vraiment libérée tout de suite : suppressions définitives et fichiers iCloud libérés.
    /// (Ce qui va à la Corbeille ne libère rien tant qu'elle n'est pas vidée.)
    public var releasedBytes: Int64 {
        items.filter { $0.succeeded && $0.method != .trash }.reduce(0) { $0 + $1.bytes }
    }

    /// Mis à la Corbeille.
    public var trashedBytes: Int64 {
        items.filter { $0.succeeded && $0.method == .trash }.reduce(0) { $0 + $1.bytes }
    }
}

/// Journal des nettoyages, stocké en JSON dans le dossier de l'appli.
public struct CleanJournal: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("journal.json")) {
        self.fileURL = fileURL
    }

    /// Une seule écriture à la fois (nettoyages de plusieurs modules en parallèle).
    private static let writeLock = NSLock()

    public func entries() -> [JournalEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? Self.decoder.decode([JournalEntry].self, from: data)) ?? []
    }

    public func append(_ entry: JournalEntry) throws {
        try Self.writeLock.withLock {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var all: [JournalEntry] = []
            if let data = try? Data(contentsOf: fileURL) {
                if let decoded = try? Self.decoder.decode([JournalEntry].self, from: data) {
                    all = decoded
                } else {
                    // Journal illisible : mis de côté plutôt qu'écrasé.
                    let stamp = Int(Date().timeIntervalSince1970)
                    let aside = fileURL.deletingPathExtension().appendingPathExtension("illisible-\(stamp).json")
                    try? FileManager.default.moveItem(at: fileURL, to: aside)
                }
            }
            all.append(entry)
            try Self.encoder.encode(all).write(to: fileURL, options: .atomic)
        }
    }

    public var totalFreedBytes: Int64 {
        entries().reduce(0) { $0 + $1.freedBytes }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
