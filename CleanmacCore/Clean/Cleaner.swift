import Foundation

/// Opérations de suppression réelles (remplaçables dans les tests).
public protocol FileRemoving: Sendable {
    /// Met l'élément à la Corbeille et renvoie son nouvel emplacement.
    func trash(_ path: String) throws -> String?
    /// Suppression définitive (réservée aux caches régénérables, si activée).
    func removePermanently(_ path: String) throws
}

/// Suppression via `FileManager` : Corbeille par défaut.
public struct SystemFileRemover: FileRemoving {
    public init() {}

    public func trash(_ path: String) throws -> String? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        return resulting?.path
    }

    public func removePermanently(_ path: String) throws {
        try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }
}

/// Un élément à nettoyer, validé à l'écran de vérification.
public struct CleanRequest: Sendable, Hashable {
    public let path: String
    public let ruleID: String
    public let bytes: Int64

    public init(path: String, ruleID: String, bytes: Int64) {
        self.path = path
        self.ruleID = ruleID
        self.bytes = bytes
    }

    public init(_ item: ScanItem) {
        self.init(path: item.path, ruleID: item.ruleID, bytes: item.allocatedBytes)
    }
}

/// Raisons pour lesquelles un élément est refusé au moment du nettoyage.
public enum CleanRefusal: Error, Equatable, CustomStringConvertible {
    case unknownRule(String)
    case notMatchingRule(ruleID: String)
    case protected(ProtectionReason)
    case missing
    case permanentDeletionDisabled
    case sourceUnavailable

    public var description: String {
        switch self {
        case let .unknownRule(id): "Règle inconnue : \(id)"
        case let .notMatchingRule(id): "Hors de la règle \(id)"
        case let .protected(reason): reason.description
        case .missing: "Élément introuvable"
        case .permanentDeletionDisabled:
            "Ne peut pas aller à la Corbeille : activez la suppression définitive dans les réglages"
        case .sourceUnavailable: "Outil du système indisponible"
        }
    }
}

/// Moteur de nettoyage. Chaque élément est revérifié juste avant d'être supprimé :
/// règle connue, chemin conforme à la règle, protections, absence de `.git`.
public struct Cleaner: Sendable {
    public let rules: RuleBook
    public let policy: ProtectionPolicy
    public let remover: any FileRemoving
    public let journal: CleanJournal
    public let sources: [RuleSource: any ExternalSource]
    /// Suppression définitive autorisée par l'utilisateur (caches régénérables uniquement).
    public let allowPermanentDeletion: Bool

    public init(
        rules: RuleBook,
        policy: ProtectionPolicy,
        remover: any FileRemoving = SystemFileRemover(),
        journal: CleanJournal = CleanJournal(),
        sources: [RuleSource: any ExternalSource] = ExternalSources.system,
        allowPermanentDeletion: Bool = false
    ) {
        self.rules = rules
        self.policy = policy
        self.remover = remover
        self.journal = journal
        self.sources = sources
        self.allowPermanentDeletion = allowPermanentDeletion
    }

    /// Méthode de suppression appliquée à une règle.
    public func method(for rule: Rule) -> RemovalMethod {
        if rule.source != nil { return .permanent }
        return allowPermanentDeletion && rule.regenerable ? .permanent : .trash
    }

    /// Les éléments de cette règle peuvent-ils être nettoyés avec les réglages actuels ?
    public func canClean(_ rule: Rule) -> Bool {
        rule.source == nil || (allowPermanentDeletion && rule.regenerable)
    }

    /// Vérifie qu'un élément peut être supprimé. Renvoie la règle qui l'autorise.
    public func validate(_ request: CleanRequest) throws(CleanRefusal) -> Rule {
        guard let rule = rules.rule(id: request.ruleID) else {
            throw .unknownRule(request.ruleID)
        }
        guard rule.source == nil else { throw .notMatchingRule(ruleID: rule.id) }
        let pattern = PathPattern(home: policy.home)
        guard pattern.matches(request.path, rule: rule) else {
            throw .notMatchingRule(ruleID: rule.id)
        }
        if let reason = policy.fullProtection(for: request.path) {
            throw .protected(reason)
        }
        guard PathPattern.exists(request.path) else { throw .missing }
        return rule
    }

    /// Nettoie les éléments validés et écrit une entrée dans le journal.
    @concurrent
    public func clean(
        _ requests: [CleanRequest],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> JournalEntry {
        var lines: [JournalItem] = []
        for (index, request) in requests.enumerated() {
            if Task.isCancelled { break }
            progress?(index, requests.count)
            if let rule = rules.rule(id: request.ruleID), let source = rule.source {
                lines.append(await cleanExternal(request, rule: rule, source: source))
                continue
            }
            do {
                let rule = try validate(request)
                let method = method(for: rule)
                var trashedPath: String?
                switch method {
                case .trash: trashedPath = try remover.trash(request.path)
                case .permanent: try remover.removePermanently(request.path)
                }
                lines.append(JournalItem(
                    path: request.path, ruleID: request.ruleID, bytes: request.bytes,
                    method: method, succeeded: true, message: nil, trashedPath: trashedPath))
            } catch {
                lines.append(JournalItem(
                    path: request.path, ruleID: request.ruleID, bytes: request.bytes,
                    method: .trash, succeeded: false,
                    message: (error as? CleanRefusal)?.description ?? error.localizedDescription,
                    trashedPath: nil))
            }
        }
        progress?(requests.count, requests.count)
        guard !lines.isEmpty else {
            return JournalEntry(id: UUID(), date: Date(), items: [])
        }
        let entry = JournalEntry(id: UUID(), date: Date(), items: lines)
        try journal.append(entry)
        return entry
    }

    /// Supprime un élément géré par un outil du système, après revérification.
    private func cleanExternal(_ request: CleanRequest, rule: Rule, source: RuleSource) async -> JournalItem {
        func failure(_ message: String) -> JournalItem {
            JournalItem(
                path: request.path, ruleID: request.ruleID, bytes: request.bytes,
                method: .permanent, succeeded: false, message: message, trashedPath: nil)
        }
        guard canClean(rule) else { return failure(CleanRefusal.permanentDeletionDisabled.description) }
        guard let id = ExternalReference.parse(request.path, source: source),
              let provider = sources[source] else {
            return failure(CleanRefusal.sourceUnavailable.description)
        }
        do {
            // L'élément doit toujours figurer dans la liste de l'outil.
            guard try await provider.list().contains(where: { $0.id == id }) else {
                return failure(CleanRefusal.missing.description)
            }
            try await provider.delete(id: id)
            return JournalItem(
                path: request.path, ruleID: request.ruleID, bytes: request.bytes,
                method: .permanent, succeeded: true, message: nil, trashedPath: nil)
        } catch {
            return failure(error.localizedDescription)
        }
    }
}
