import Foundation

/// Un élément trouvé par le scan, rattaché à la règle qui l'autorise.
public struct ScanItem: Sendable, Identifiable, Hashable {
    public var id: String { path }
    /// Chemin sur le disque, ou référence `source:identifiant` pour un élément externe.
    public let path: String
    public let ruleID: String
    public let allocatedBytes: Int64
    public let fileCount: Int
    public let isSelectedByDefault: Bool
    /// Nom affiché (éléments externes) ; sinon le dernier composant du chemin.
    public var displayName: String?
    /// Précision affichée sous le nom (ex. date de dernière utilisation).
    public var detail: String?
    /// Vrai si l'élément est géré par un outil du système (pas un chemin).
    public var isExternal = false

    public var name: String { displayName ?? (path as NSString).lastPathComponent }
}

/// Un élément écarté par les protections.
public struct SkippedItem: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let ruleID: String
    public let reason: ProtectionReason
}

/// Avancement du scan.
public struct ScanProgress: Sendable, Equatable {
    public var ruleIndex: Int
    public var ruleCount: Int
    public var currentRuleName: String
    public var filesVisited: Int
    public var itemsFound: Int
    public var bytesFound: Int64

    /// Entre 0 et 1.
    public var fractionCompleted: Double {
        ruleCount == 0 ? 1 : Double(ruleIndex) / Double(ruleCount)
    }
}

/// Résultat d'un scan.
public struct ScanResult: Sendable {
    public let items: [ScanItem]
    public let skipped: [SkippedItem]
    public let unreadableCount: Int
    public let duration: Duration
    /// Messages des sources externes qui n'ont pas pu être interrogées.
    public var sourceErrors: [String] = []

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.allocatedBytes } }
    public var selectedByDefaultBytes: Int64 {
        items.filter(\.isSelectedByDefault).reduce(0) { $0 + $1.allocatedBytes }
    }

    public func items(forRule id: String) -> [ScanItem] {
        items.filter { $0.ruleID == id }
    }

    /// Résultat sans les éléments déjà nettoyés.
    public func removing(_ paths: Set<String>) -> ScanResult {
        ScanResult(
            items: items.filter { !paths.contains($0.path) }, skipped: skipped,
            unreadableCount: unreadableCount, duration: duration, sourceErrors: sourceErrors)
    }
}

/// Moteur de scan : lecture seule, asynchrone, annulable, avec progression.
public struct Scanner: Sendable {
    /// Nom lisible d'un dossier nommé par un identifiant (pièces jointes de Mail : « UUID/facture.pdf »).
    static func readableName(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        guard UUID(uuidString: name) != nil, PathPattern.isRealDirectory(path) else { return nil }
        let children = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
        guard let first = children.first else { return nil }
        return children.count == 1 ? first : "\(first) et \(children.count - 1) autre\(children.count > 2 ? "s" : "")"
    }

    public let policy: ProtectionPolicy
    public let pattern: PathPattern
    public let sources: [RuleSource: any ExternalSource]
    public var calculator = SizeCalculator()

    public init(policy: ProtectionPolicy, sources: [RuleSource: any ExternalSource] = ExternalSources.system) {
        self.policy = policy
        self.pattern = PathPattern(home: policy.home)
        self.sources = sources
    }

    /// Parcourt les règles et mesure chaque élément trouvé.
    /// S'exécute hors du fil principal ; lève `CancellationError` en cas d'annulation.
    @concurrent
    public func scan(
        rules: [Rule],
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanResult {
        let clock = ContinuousClock()
        let start = clock.now
        var items: [ScanItem] = []
        var skipped: [SkippedItem] = []
        var unreadable = 0
        var sourceErrors: [String] = []
        var claimed: [String] = []   // chemins déjà retenus (évite les doublons entre règles)
        var state = ScanProgress(
            ruleIndex: 0, ruleCount: rules.count, currentRuleName: "",
            filesVisited: 0, itemsFound: 0, bytesFound: 0)

        for (index, rule) in rules.enumerated() {
            try Task.checkCancellation()
            // Les règles à contrôle (doublons…) ne se scannent pas : leurs éléments viennent d'un autre module.
            if rule.check != nil { continue }
            state.ruleIndex = index
            state.currentRuleName = rule.name
            progress?(state)

            if let source = rule.source {
                guard let provider = sources[source] else { continue }
                do {
                    for external in try await provider.list() {
                        var item = ScanItem(
                            path: ExternalReference.make(source: source, id: external.id),
                            ruleID: rule.id,
                            allocatedBytes: external.bytes,
                            fileCount: 0,
                            isSelectedByDefault: rule.isSelectedByDefault)
                        item.displayName = external.name
                        item.detail = external.detail
                        item.isExternal = true
                        items.append(item)
                        state.bytesFound += external.bytes
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    sourceErrors.append("\(rule.name) : \(error.localizedDescription)")
                }
                state.itemsFound = items.count
                progress?(state)
                continue
            }

            for path in pattern.expand(rule: rule) {
                try Task.checkCancellation()
                if claimed.contains(where: { ProtectionPolicy.isSameOrInside(path, $0) }) { continue }
                // Corbeilles : seulement ce qui est directement dans une vraie Corbeille (aucun lien suivi).
                if rule.inTrash, !TrashLocation.isDirectlyInTrash(path, home: policy.home, uid: pattern.uid) { continue }

                if let reason = policy.protection(for: path) {
                    skipped.append(SkippedItem(path: path, ruleID: rule.id, reason: reason))
                    continue
                }
                let snapshot = state
                var visited = 0
                let measure = try calculator.measure(path, stopAtGit: true) { count in
                    visited += count
                    var update = snapshot
                    update.filesVisited += visited
                    progress?(update)
                }
                state.filesVisited += measure.fileCount
                unreadable += measure.unreadableCount

                if let git = measure.gitDirectory {
                    let repo = (git as NSString).deletingLastPathComponent
                    skipped.append(SkippedItem(path: path, ruleID: rule.id, reason: .gitRepository(repo)))
                    continue
                }
                claimed.append(path)
                var item = ScanItem(
                    path: path,
                    ruleID: rule.id,
                    allocatedBytes: measure.allocatedBytes,
                    fileCount: measure.fileCount,
                    isSelectedByDefault: rule.isSelectedByDefault)
                item.displayName = Self.readableName(path)
                items.append(item)
                state.itemsFound = items.count
                state.bytesFound += measure.allocatedBytes
                progress?(state)
            }
        }
        state.ruleIndex = rules.count
        progress?(state)
        return ScanResult(
            items: items, skipped: skipped, unreadableCount: unreadable,
            duration: clock.now - start, sourceErrors: sourceErrors)
    }
}
