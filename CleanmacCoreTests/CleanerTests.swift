import Foundation
import Testing
@testable import CleanmacCore

@Suite("Moteur de nettoyage")
struct CleanerTests {
    func makeCleaner(
        home: FakeHome, rules: [Rule], remover: RecordingRemover,
        permanent: Bool = false, exclusions: [String] = []
    ) throws -> Cleaner {
        Cleaner(
            rules: try RuleBook(rules: rules),
            policy: ProtectionPolicy(home: home.path, userExclusions: exclusions),
            remover: remover,
            journal: CleanJournal(fileURL: URL(fileURLWithPath: home.url("support/journal.json"))),
            allowPermanentDeletion: permanent)
    }

    @Test("Corbeille par défaut, et journal écrit")
    func trashByDefault() async throws {
        let home = try FakeHome()
        let path = try home.file("Library/Caches/com.a/f", bytes: 100)
        let dir = (path as NSString).deletingLastPathComponent
        let remover = RecordingRemover()
        let cleaner = try makeCleaner(home: home, rules: [makeRule(regenerable: true)], remover: remover)

        let entry = try await cleaner.clean([CleanRequest(path: dir, ruleID: "test.caches", bytes: 4096)])

        #expect(remover.trashed == [dir])
        #expect(remover.removed.isEmpty)
        #expect(entry.items.first?.method == .trash)
        #expect(entry.freedBytes == 4096)
        #expect(cleaner.journal.entries().map(\.id) == [entry.id])
        #expect(cleaner.journal.entries().first?.items == entry.items)
        #expect(cleaner.journal.totalFreedBytes == 4096)
    }

    @Test("Suppression définitive seulement si activée ET règle régénérable")
    func permanentOnlyWhenAllowed() async throws {
        let home = try FakeHome()
        let a = try home.dir("Library/Caches/a")
        let b = try home.dir("Library/Logs/b")
        let rules = [
            makeRule(id: "caches", regenerable: true),
            makeRule(id: "logs", paths: ["~/Library/Logs/*"], regenerable: false),
        ]
        let remover = RecordingRemover()
        let cleaner = try makeCleaner(home: home, rules: rules, remover: remover, permanent: true)
        _ = try await cleaner.clean([
            CleanRequest(path: a, ruleID: "caches", bytes: 1),
            CleanRequest(path: b, ruleID: "logs", bytes: 1),
        ])
        #expect(remover.removed == [a])
        #expect(remover.trashed == [b])

        let prudent = try makeCleaner(home: home, rules: rules, remover: RecordingRemover())
        #expect(prudent.method(for: rules[0]) == .trash)
    }

    @Test("Refus : règle inconnue, hors règle, protégé, absent")
    func refusals() async throws {
        let home = try FakeHome()
        try home.file("Library/Caches/repo/sous/.git/HEAD")
        try home.dir("Library/Caches/exclu")
        let doc = try home.file("Documents/important.txt")
        let remover = RecordingRemover()
        let cleaner = try makeCleaner(
            home: home, rules: [makeRule(paths: ["~/Library/Caches/*", "~/Documents/*"])],
            remover: remover, exclusions: ["~/Library/Caches/exclu"])

        #expect(throws: CleanRefusal.unknownRule("inconnue")) {
            try cleaner.validate(CleanRequest(path: home.url("Library/Caches/repo"), ruleID: "inconnue", bytes: 0))
        }
        #expect(throws: CleanRefusal.notMatchingRule(ruleID: "test.caches")) {
            try cleaner.validate(CleanRequest(path: home.url("Library/Other"), ruleID: "test.caches", bytes: 0))
        }
        // Même si une règle le couvrait, ~/Documents reste protégé.
        #expect(throws: CleanRefusal.self) {
            try cleaner.validate(CleanRequest(path: doc, ruleID: "test.caches", bytes: 0))
        }
        #expect(throws: CleanRefusal.self) {
            try cleaner.validate(CleanRequest(path: home.url("Library/Caches/repo"), ruleID: "test.caches", bytes: 0))
        }
        #expect(throws: CleanRefusal.self) {
            try cleaner.validate(CleanRequest(path: home.url("Library/Caches/exclu"), ruleID: "test.caches", bytes: 0))
        }
        #expect(throws: CleanRefusal.missing) {
            try cleaner.validate(CleanRequest(path: home.url("Library/Caches/fantome"), ruleID: "test.caches", bytes: 0))
        }

        let entry = try await cleaner.clean([
            CleanRequest(path: doc, ruleID: "test.caches", bytes: 99),
        ])
        #expect(remover.trashed.isEmpty && remover.removed.isEmpty)
        #expect(entry.items.first?.succeeded == false)
        #expect(entry.freedBytes == 0)
    }

    @Test("Scan puis nettoyage : de bout en bout avec la vraie Corbeille simulée")
    func scanThenClean() async throws {
        let home = try FakeHome()
        try home.file("Library/Caches/com.a/f", bytes: 1_000)
        try home.file("Library/Caches/com.b/f", bytes: 1_000)
        let rule = makeRule()
        let policy = ProtectionPolicy(home: home.path)
        let result = try await Scanner(policy: policy).scan(rules: [rule])
        let remover = RecordingRemover()
        let cleaner = try makeCleaner(home: home, rules: [rule], remover: remover)
        let entry = try await cleaner.clean(result.items.filter(\.isSelectedByDefault).map(CleanRequest.init))
        #expect(remover.trashed.count == 2)
        #expect(entry.freedBytes == result.totalBytes)
    }
}
