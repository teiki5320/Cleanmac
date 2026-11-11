import Foundation
import Synchronization
import Testing
@testable import CleanmacCore

/// Fausse source externe : liste fixe, enregistre les suppressions.
final class FakeSource: ExternalSource, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ExternalItem]
    private(set) var deleted: [String] = []
    var failList = false

    init(_ items: [ExternalItem]) { self.items = items }

    func list() async throws -> [ExternalItem] {
        if failList { throw ExternalSourceError.toolFailed("simctl indisponible") }
        return lock.withLock { items }
    }

    func delete(id: String) async throws {
        lock.withLock {
            deleted.append(id)
            items.removeAll { $0.id == id }
        }
    }
}

@Suite("Module Développeur")
struct DeveloperModuleTests {
    let runtimeRule = Rule(
        id: "dev.sim", name: "Simulateurs", category: .developer, risk: .review,
        explanation: "x", paths: [], regenerable: true, source: .simulatorRuntimes)

    @Test("Les règles Développeur livrées sont valides et bien rangées")
    func bundledDeveloperRules() throws {
        let book = try RuleBook.bundled()
        let dev = book.rules(in: .developer)
        #expect(dev.count >= 15)
        #expect(book.rule(id: "dev.xcode-deriveddata")?.isSelectedByDefault == true)
        // Modèles d'IA et simulateurs : jamais cochés par défaut.
        #expect(book.rule(id: "dev.ollama-modeles")?.isSelectedByDefault == false)
        #expect(book.rule(id: "dev.comfyui-modeles")?.isSelectedByDefault == false)
        #expect(book.rule(id: "dev.simulateurs-runtimes")?.source == .simulatorRuntimes)
        #expect(book.rule(id: "dev.simulateurs-runtimes")?.isSelectedByDefault == false)
    }

    @Test("Une règle à source ne déclare pas de chemins et doit être régénérable")
    func sourceRuleValidation() {
        #expect(throws: RuleError.self) {
            try RuleBook(rules: [Rule(
                id: "x", name: "x", category: .developer, risk: .review, explanation: "x",
                paths: ["~/Library/Caches/*"], regenerable: true, source: .simulatorRuntimes)])
        }
        #expect(throws: RuleError.self) {
            try RuleBook(rules: [Rule(
                id: "x", name: "x", category: .developer, risk: .review, explanation: "x",
                paths: [], regenerable: false, source: .simulatorRuntimes)])
        }
    }

    @Test("Les caches dev sont pris par leur règle, pas par les caches génériques")
    func developerRulesClaimFirst() async throws {
        let home = try FakeHome()
        try home.file("Library/Caches/pip/http/x", bytes: 1_000)
        try home.file("Library/Caches/com.app/y", bytes: 1_000)
        try home.file("Library/Developer/Xcode/DerivedData/Projet-abc/Build/z", bytes: 1_000)
        let book = try RuleBook.bundled()
        let scanner = Scanner(policy: ProtectionPolicy(home: home.path), sources: [:])
        let result = try await scanner.scan(rules: book.rules)
        let byName = Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0.ruleID) })
        #expect(byName["pip"] == "dev.pip")
        #expect(byName["com.app"] == "systeme.caches-utilisateur")
        #expect(byName["Projet-abc"] == "dev.xcode-deriveddata")
    }

    @Test("Lecture de la liste des simulateurs (format simctl)")
    func parseSimctl() throws {
        let json = """
        { "A0000000-0000-0000-0000-000000000001": { "identifier": "A0000000-0000-0000-0000-000000000001",
            "version": "27.2", "build": "24B91016s", "platformIdentifier": "com.apple.platform.iphonesimulator",
            "deletable": true, "sizeBytes": 8000000000, "lastUsedAt": "2026-11-09T17:53:01Z" },
          "A0000000-0000-0000-0000-000000000002": { "identifier": "A0000000-0000-0000-0000-000000000002",
            "version": "26.0", "build": "23A1", "platformIdentifier": "com.apple.platform.watchsimulator",
            "deletable": false, "sizeBytes": 5 } }
        """
        let items = try SimulatorRuntimeSource.parse(Data(json.utf8))
        #expect(items.count == 1)
        #expect(items[0].name == "iOS 27.2 (24B91016s bêta)")
        #expect(items[0].bytes == 8_000_000_000)
        #expect(items[0].detail != nil)
    }

    @Test("Le scan liste les éléments externes, décochés")
    func scanExternal() async throws {
        let home = try FakeHome()
        let source = FakeSource([ExternalItem(id: "R1", name: "iOS 27.2", bytes: 8_000)])
        let scanner = Scanner(policy: ProtectionPolicy(home: home.path), sources: [.simulatorRuntimes: source])
        let result = try await scanner.scan(rules: [runtimeRule])
        let item = try #require(result.items.first)
        #expect(item.isExternal)
        #expect(item.name == "iOS 27.2")
        #expect(item.path == "simulatorRuntimes:R1")
        #expect(item.isSelectedByDefault == false)
        #expect(result.totalBytes == 8_000)
    }

    @Test("Une source en panne n'arrête pas le scan")
    func failingSource() async throws {
        let home = try FakeHome()
        try home.file("Library/Caches/a/f")
        let source = FakeSource([])
        source.failList = true
        let scanner = Scanner(policy: ProtectionPolicy(home: home.path), sources: [.simulatorRuntimes: source])
        let result = try await scanner.scan(rules: [runtimeRule, makeRule()])
        #expect(result.items.count == 1)
        #expect(result.sourceErrors.count == 1)
    }

    func cleaner(_ home: FakeHome, _ source: FakeSource, permanent: Bool) throws -> Cleaner {
        Cleaner(
            rules: try RuleBook(rules: [runtimeRule]),
            policy: ProtectionPolicy(home: home.path),
            remover: RecordingRemover(),
            journal: CleanJournal(fileURL: URL(fileURLWithPath: home.url("journal.json"))),
            sources: [.simulatorRuntimes: source],
            allowPermanentDeletion: permanent)
    }

    @Test("Élément externe refusé tant que la suppression définitive est désactivée")
    func externalNeedsPermanent() async throws {
        let home = try FakeHome()
        let source = FakeSource([ExternalItem(id: "R1", name: "iOS", bytes: 10)])
        let c = try cleaner(home, source, permanent: false)
        #expect(!c.canClean(runtimeRule))
        let entry = try await c.clean([CleanRequest(path: "simulatorRuntimes:R1", ruleID: "dev.sim", bytes: 10)])
        #expect(source.deleted.isEmpty)
        #expect(entry.items.first?.succeeded == false)
    }

    @Test("Élément externe supprimé via l'outil quand c'est autorisé")
    func externalDeleted() async throws {
        let home = try FakeHome()
        let source = FakeSource([ExternalItem(id: "R1", name: "iOS", bytes: 10)])
        let c = try cleaner(home, source, permanent: true)
        let entry = try await c.clean([
            CleanRequest(path: "simulatorRuntimes:R1", ruleID: "dev.sim", bytes: 10),
            CleanRequest(path: "simulatorRuntimes:R9", ruleID: "dev.sim", bytes: 10),
        ])
        #expect(source.deleted == ["R1"])
        #expect(entry.items.map(\.succeeded) == [true, false])
        #expect(entry.items.first?.method == .permanent)
        #expect(entry.freedBytes == 10)
    }

    @Test("Une référence externe ne passe jamais pour un chemin")
    func externalReferenceNotAPath() throws {
        let home = try FakeHome()
        let c = try cleaner(home, FakeSource([]), permanent: true)
        #expect(throws: CleanRefusal.self) {
            try c.validate(CleanRequest(path: "/Users/x/Documents", ruleID: "dev.sim", bytes: 0))
        }
    }
}
