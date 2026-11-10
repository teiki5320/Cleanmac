import Foundation

/// Un élément trouvé par le scan, rattaché à la règle qui l'autorise.
public struct ScanItem: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let ruleID: String
    public let allocatedBytes: Int64
    public let fileCount: Int
    public let isSelectedByDefault: Bool

    public var name: String { (path as NSString).lastPathComponent }
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

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.allocatedBytes } }
    public var selectedByDefaultBytes: Int64 {
        items.filter(\.isSelectedByDefault).reduce(0) { $0 + $1.allocatedBytes }
    }

    public func items(forRule id: String) -> [ScanItem] {
        items.filter { $0.ruleID == id }
    }
}

/// Moteur de scan : lecture seule, asynchrone, annulable, avec progression.
public struct Scanner: Sendable {
    public let policy: ProtectionPolicy
    public let pattern: PathPattern
    public var calculator = SizeCalculator()

    public init(policy: ProtectionPolicy) {
        self.policy = policy
        self.pattern = PathPattern(home: policy.home)
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
        var claimed: [String] = []   // chemins déjà retenus (évite les doublons entre règles)
        var state = ScanProgress(
            ruleIndex: 0, ruleCount: rules.count, currentRuleName: "",
            filesVisited: 0, itemsFound: 0, bytesFound: 0)

        for (index, rule) in rules.enumerated() {
            try Task.checkCancellation()
            state.ruleIndex = index
            state.currentRuleName = rule.name
            progress?(state)

            for path in pattern.expand(rule: rule) {
                try Task.checkCancellation()
                if claimed.contains(where: { ProtectionPolicy.isSameOrInside(path, $0) }) { continue }

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
                items.append(ScanItem(
                    path: path,
                    ruleID: rule.id,
                    allocatedBytes: measure.allocatedBytes,
                    fileCount: measure.fileCount,
                    isSelectedByDefault: rule.isSelectedByDefault))
                state.itemsFound = items.count
                state.bytesFound += measure.allocatedBytes
                progress?(state)
            }
        }
        state.ruleIndex = rules.count
        progress?(state)
        return ScanResult(
            items: items, skipped: skipped, unreadableCount: unreadable,
            duration: clock.now - start)
    }
}
