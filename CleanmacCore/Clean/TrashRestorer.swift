import Foundation

/// Raisons pour lesquelles un élément ne peut pas être remis en place.
public enum RestoreRefusal: Error, Equatable, CustomStringConvertible {
    case notRestorable
    case notInTrash
    case missing
    case originalExists
    case parentMissing
    case failed(String)

    public var description: String {
        switch self {
        case .notRestorable: "Cet élément n'a pas été mis à la Corbeille"
        case .notInTrash: "L'élément n'est plus dans une Corbeille"
        case .missing: "L'élément n'est plus dans la Corbeille (déjà vidée ou déplacé)"
        case .originalExists: "Un élément porte déjà ce nom à l'emplacement d'origine"
        case .parentMissing: "Le dossier d'origine n'existe plus"
        case let .failed(message): message
        }
    }
}

/// Remet à sa place d'origine un élément mis à la Corbeille par Cleanmac, d'après le journal.
/// N'écrase jamais rien et ne recrée pas de dossier : l'emplacement d'origine doit être libre
/// et son dossier parent présent.
public struct TrashRestorer: Sendable {
    public static let journalRuleID = "corbeille.remise-en-place"
    public let home: String
    public let journal: CleanJournal

    public init(home: String = NSHomeDirectory(), journal: CleanJournal = CleanJournal()) {
        self.home = PathPattern.trimmed(home)
        self.journal = journal
    }

    /// Vérifie qu'un élément du journal peut être remis en place ; renvoie son chemin dans la Corbeille.
    public func validate(_ item: JournalItem) throws(RestoreRefusal) -> String {
        guard item.succeeded, item.method == .trash, let trashed = item.trashedPath else { throw .notRestorable }
        guard PathPattern.exists(trashed) else { throw .missing }
        guard TrashLocation.isDirectlyInTrash(trashed, home: home) else { throw .notInTrash }
        guard ProtectionPolicy.pathProblem(item.path, home: home) == nil else { throw .notRestorable }
        guard !PathPattern.exists(item.path) else { throw .originalExists }
        let parent = (item.path as NSString).deletingLastPathComponent
        guard PathPattern.isRealDirectory(parent), !PathPattern.hasSymlinkedParent(item.path) else { throw .parentMissing }
        return trashed
    }

    /// Peut-on proposer « Remettre en place » ?
    public func canRestore(_ item: JournalItem) -> Bool {
        (try? validate(item)) != nil
    }

    /// Remet l'élément en place et l'inscrit au journal.
    public func restore(_ item: JournalItem) throws -> JournalEntry {
        let trashed = try validate(item)
        do {
            try FileManager.default.moveItem(atPath: trashed, toPath: item.path)
        } catch {
            throw RestoreRefusal.failed("Remise en place impossible : \(error.localizedDescription)")
        }
        let entry = JournalEntry(items: [JournalItem(path: item.path, ruleID: Self.journalRuleID, bytes: item.bytes,
                                                     method: .restored, succeeded: true, message: nil, trashedPath: nil)])
        try? journal.append(entry)
        return entry
    }
}
