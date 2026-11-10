import Foundation
import Synchronization
import Testing
@testable import CleanmacCore

@Suite("Moteur de scan")
struct ScannerTests {
    @Test("Trouve et mesure les éléments, coche seulement les sûrs")
    func scanBasics() async throws {
        let home = try FakeHome()
        try home.file("Library/Caches/com.a/f", bytes: 20_000)
        try home.file("Library/Caches/com.b", bytes: 5_000)
        try home.file("Library/Saved Application State/x.savedState/w", bytes: 1_000)
        let rules = [
            makeRule(id: "caches"),
            makeRule(id: "etat", risk: .review, paths: ["~/Library/Saved Application State/*"]),
        ]
        let scanner = Scanner(policy: ProtectionPolicy(home: home.path))
        let result = try await scanner.scan(rules: rules)

        #expect(result.items.count == 3)
        let cachesChecked = result.items(forRule: "caches").map(\.isSelectedByDefault)
        let etatChecked = result.items(forRule: "etat").map(\.isSelectedByDefault)
        #expect(cachesChecked == [true, true])
        #expect(etatChecked == [false])
        #expect(result.totalBytes >= 26_000)
        #expect(result.selectedByDefaultBytes < result.totalBytes)
    }

    @Test("Les éléments protégés sont écartés, avec la raison")
    func protectedSkipped() async throws {
        let home = try FakeHome()
        try home.file("Library/Caches/repo/.git/HEAD")
        try home.file("Library/Caches/profond/a/b/.git/HEAD")
        try home.file("Library/Caches/garder/f")
        try home.file("Library/Caches/ok/f")
        let policy = ProtectionPolicy(home: home.path, userExclusions: ["~/Library/Caches/garder"])
        let result = try await Scanner(policy: policy).scan(rules: [makeRule()])

        #expect(result.items.map(\.name) == ["ok"])
        #expect(Set(result.skipped.map(\.path)) == [
            home.url("Library/Caches/repo"),
            home.url("Library/Caches/profond"),
            home.url("Library/Caches/garder"),
        ])
    }

    @Test("Un même élément n'est pas compté deux fois par deux règles")
    func noDoubleCounting() async throws {
        let home = try FakeHome()
        try home.file("Library/Logs/app/x.log")
        try home.file("Library/Logs/DiagnosticReports/crash.ips")
        let rules = [
            makeRule(id: "logs", paths: ["~/Library/Logs/*"]),
            makeRule(id: "crash", paths: ["~/Library/Logs/DiagnosticReports/*"]),
        ]
        let result = try await Scanner(policy: ProtectionPolicy(home: home.path)).scan(rules: rules)
        #expect(result.items.map(\.ruleID) == ["logs", "logs"])
    }

    @Test("La progression est signalée et se termine à 100 %")
    func progressReported() async throws {
        let home = try FakeHome()
        try home.file("Library/Caches/a/f")
        let last = Mutex<ScanProgress?>(nil)
        _ = try await Scanner(policy: ProtectionPolicy(home: home.path))
            .scan(rules: [makeRule()]) { p in last.withLock { $0 = p } }
        let final = try #require(last.withLock { $0 })
        #expect(final.fractionCompleted == 1)
        #expect(final.itemsFound == 1)
    }

    @Test("Le scan s'arrête quand on l'annule")
    func cancellation() async throws {
        let home = try FakeHome()
        for i in 0..<20 { try home.file("Library/Caches/c\(i)/f") }
        let scanner = Scanner(policy: ProtectionPolicy(home: home.path))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan(rules: [makeRule()])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
