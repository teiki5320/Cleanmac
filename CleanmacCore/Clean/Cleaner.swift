import Darwin
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
    /// Exemplaire gardé, pour les règles `duplicateCopy` : la copie n'est supprimée que s'il
    /// existe et a exactement le même contenu.
    public let keeperPath: String?

    public init(path: String, ruleID: String, bytes: Int64, keeperPath: String? = nil) {
        self.path = path
        self.ruleID = ruleID
        self.bytes = bytes
        self.keeperPath = keeperPath
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
    case keeperRequired
    case keeperMissing
    case keeperInSameClean
    case sameFile
    case notRegularFile
    case notDownloaded
    case contentDiffers

    public var description: String {
        switch self {
        case let .unknownRule(id): "Règle inconnue : \(id)"
        case let .notMatchingRule(id): "Hors de la règle \(id)"
        case let .protected(reason): reason.description
        case .missing: "Élément introuvable"
        case .permanentDeletionDisabled:
            "Ne peut pas aller à la Corbeille : activez la suppression définitive dans les réglages"
        case .sourceUnavailable: "Outil du système indisponible"
        case .keeperRequired: "Exemplaire à garder non indiqué"
        case .keeperMissing: "L'exemplaire gardé a disparu : copie conservée"
        case .keeperInSameClean: "L'exemplaire gardé serait supprimé lui aussi : copie conservée"
        case .sameFile: "C'est le même fichier que l'exemplaire gardé (lien physique)"
        case .notRegularFile: "Ce n'est pas un fichier ordinaire"
        case .notDownloaded: "Fichier iCloud non téléchargé : non vérifiable"
        case .contentDiffers: "Le contenu n'est plus identique à l'exemplaire gardé : copie conservée"
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
        if rule.check != nil { return .trash }
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
        if rule.check == .duplicateCopy {
            guard let keeper = request.keeperPath, keeper != request.path else { throw .keeperRequired }
            guard PathPattern.exists(keeper) else { throw .keeperMissing }
        }
        return rule
    }

    /// Contrôle d'une copie (règle `duplicateCopy`), fait juste avant la suppression :
    /// deux fichiers ordinaires distincts, présents sur ce Mac, de même taille et au contenu
    /// identique octet par octet ; l'exemplaire gardé ne fait pas partie du même nettoyage.
    public func verifyCopy(_ request: CleanRequest, removing batch: Set<String>) throws(CleanRefusal) {
        guard let keeper = request.keeperPath, keeper != request.path else { throw .keeperRequired }
        guard !batch.contains(keeper) else { throw .keeperInSameClean }
        var copy = stat(), kept = stat()
        guard lstat(request.path, &copy) == 0 else { throw .missing }
        guard lstat(keeper, &kept) == 0 else { throw .keeperMissing }
        guard (copy.st_mode & S_IFMT) == S_IFREG, (kept.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile }
        guard copy.st_dev != kept.st_dev || copy.st_ino != kept.st_ino else { throw .sameFile }
        let dataless = UInt32(SF_DATALESS)
        guard copy.st_flags & dataless == 0, kept.st_flags & dataless == 0 else { throw .notDownloaded }
        guard copy.st_size == kept.st_size else { throw .contentDiffers }
        guard Self.sameContent(request.path, keeper) else { throw .contentDiffers }
    }

    /// Compare deux fichiers octet par octet (sans suivre les liens). Faux en cas d'erreur de lecture.
    static func sameContent(_ a: String, _ b: String) -> Bool {
        let fa = open(a, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fa >= 0 else { return false }
        defer { close(fa) }
        let fb = open(b, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fb >= 0 else { return false }
        defer { close(fb) }
        let chunk = 1 << 20
        var bufA = [UInt8](repeating: 0, count: chunk)
        var bufB = [UInt8](repeating: 0, count: chunk)
        while true {
            let na = bufA.withUnsafeMutableBytes { read(fa, $0.baseAddress, chunk) }
            let nb = bufB.withUnsafeMutableBytes { read(fb, $0.baseAddress, chunk) }
            guard na >= 0, na == nb else { return false }
            if na == 0 { return true }
            let equal = bufA.withUnsafeBytes { pa in
                bufB.withUnsafeBytes { pb in memcmp(pa.baseAddress, pb.baseAddress, na) == 0 }
            }
            guard equal else { return false }
        }
    }

    /// Nettoie les éléments validés et écrit une entrée dans le journal.
    @concurrent
    public func clean(
        _ requests: [CleanRequest],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> JournalEntry {
        var lines: [JournalItem] = []
        let batch = Set(requests.map(\.path))
        for (index, request) in requests.enumerated() {
            if Task.isCancelled { break }
            progress?(index, requests.count)
            if let rule = rules.rule(id: request.ruleID), let source = rule.source {
                lines.append(await cleanExternal(request, rule: rule, source: source))
                continue
            }
            do {
                let rule = try validate(request)
                if rule.check == .duplicateCopy {
                    try verifyCopy(request, removing: batch)
                }
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
