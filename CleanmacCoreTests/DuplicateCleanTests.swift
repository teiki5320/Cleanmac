import Darwin
import Foundation
import Testing
@testable import CleanmacCore

@Suite("Doublons : mise à la Corbeille avec garde-fous")
struct DuplicateCleanTests {
    let rule = Rule(
        id: "doublons.copies", name: "Doublons", category: .duplicates, risk: .review,
        explanation: "Test", paths: ["~/Downloads", "~/Movies"], excludes: ["~/Movies/TV"],
        check: .duplicateCopy)

    func cleaner(_ home: FakeHome, _ remover: RecordingRemover, permanent: Bool = true) throws -> Cleaner {
        Cleaner(
            rules: try RuleBook(rules: [rule]),
            policy: ProtectionPolicy(home: home.path),
            remover: remover,
            journal: CleanJournal(fileURL: URL(fileURLWithPath: home.url("support/journal.json"))),
            allowPermanentDeletion: permanent)
    }

    @discardableResult
    func write(_ home: FakeHome, _ relative: String, _ content: String) throws -> String {
        let path = home.url(relative)
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data(content.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    func request(_ path: String, keeper: String?) -> CleanRequest {
        CleanRequest(path: path, ruleID: rule.id, bytes: 4_096, keeperPath: keeper)
    }

    @Test("Copie identique : à la Corbeille, jamais définitivement, et journalisée")
    func trashesIdenticalCopy() async throws {
        let home = try FakeHome()
        let keeper = try write(home, "Movies/film.mov", "contenu identique")
        let copy = try write(home, "Downloads/sous/dossier/film.mov", "contenu identique")
        let remover = RecordingRemover()
        let cleaner = try cleaner(home, remover)   // suppression définitive activée : ignorée ici
        let entry = try await cleaner.clean([request(copy, keeper: keeper)])
        #expect(remover.trashed == [copy])
        #expect(remover.removed.isEmpty)
        #expect(entry.items.first?.succeeded == true)
        #expect(entry.items.first?.method == .trash)
        #expect(cleaner.journal.entries().count == 1)
    }

    @Test("Contenu devenu différent (même taille) : copie conservée")
    func refusesChangedContent() async throws {
        let home = try FakeHome()
        let keeper = try write(home, "Movies/a.bin", "AAAAAAAAAA")
        let copy = try write(home, "Downloads/a.bin", "AAAAAAAAAB")
        let remover = RecordingRemover()
        let entry = try await cleaner(home, remover).clean([request(copy, keeper: keeper)])
        #expect(remover.trashed.isEmpty)
        #expect(entry.items.first?.succeeded == false)
        #expect(entry.items.first?.message == CleanRefusal.contentDiffers.description)
    }

    @Test("Exemplaire gardé absent, non indiqué ou supprimé dans le même nettoyage : refus")
    func refusesWithoutKeeper() async throws {
        let home = try FakeHome()
        let a = try write(home, "Downloads/a.txt", "pareil")
        let b = try write(home, "Downloads/b.txt", "pareil")
        let remover = RecordingRemover()
        let cleaner = try cleaner(home, remover)

        #expect(throws: CleanRefusal.keeperRequired) { try cleaner.validate(request(a, keeper: nil)) }
        #expect(throws: CleanRefusal.keeperRequired) { try cleaner.validate(request(a, keeper: a)) }
        #expect(throws: CleanRefusal.keeperMissing) {
            try cleaner.validate(request(a, keeper: home.url("Downloads/disparu.txt")))
        }
        // Chacun désigne l'autre comme exemplaire gardé : les deux sont refusés.
        let entry = try await cleaner.clean([request(a, keeper: b), request(b, keeper: a)])
        #expect(remover.trashed.isEmpty)
        #expect(entry.items.allSatisfy { $0.message == CleanRefusal.keeperInSameClean.description })
    }

    @Test("Hors des dossiers de la règle, dossier lui-même ou exclu : refus")
    func refusesOutsideRule() throws {
        let home = try FakeHome()
        let keeper = try write(home, "Downloads/k.txt", "x")
        let elsewhere = try write(home, "Autre/k.txt", "x")
        let excluded = try write(home, "Movies/TV/k.txt", "x")
        let cleaner = try cleaner(home, RecordingRemover())
        for path in [elsewhere, excluded, home.url("Downloads")] {
            #expect(throws: CleanRefusal.notMatchingRule(ruleID: rule.id)) {
                try cleaner.validate(request(path, keeper: keeper))
            }
        }
    }

    @Test("Les emplacements protégés restent protégés, même pour une copie identique")
    func protectedStaysProtected() throws {
        let home = try FakeHome()
        let keeper = try write(home, "Downloads/k.txt", "x")
        let doc = try write(home, "Documents/k.txt", "x")
        let protectedRule = Rule(
            id: "doublons.copies", name: "Doublons", category: .duplicates, risk: .review,
            explanation: "Test", paths: ["~/Documents"], check: .duplicateCopy)
        let cleaner = Cleaner(rules: try RuleBook(rules: [protectedRule]),
                              policy: ProtectionPolicy(home: home.path), remover: RecordingRemover())
        #expect(throws: CleanRefusal.protected(.protectedLocation(home.url("Documents")))) {
            try cleaner.validate(request(doc, keeper: keeper))
        }
    }

    @Test("Lien physique, lien symbolique, dossier : refus")
    func refusesNonRegularOrSameFile() throws {
        let home = try FakeHome()
        let keeper = try write(home, "Downloads/k.bin", "contenu")
        let link = home.url("Downloads/lien.bin")
        try FileManager.default.linkItem(atPath: keeper, toPath: link)
        let symlink = home.url("Downloads/symb.bin")
        try FileManager.default.createSymbolicLink(atPath: symlink, withDestinationPath: keeper)
        let cleaner = try cleaner(home, RecordingRemover())
        #expect(throws: CleanRefusal.sameFile) { try cleaner.verifyCopy(request(link, keeper: keeper), removing: []) }
        #expect(throws: CleanRefusal.notRegularFile) { try cleaner.verifyCopy(request(symlink, keeper: keeper), removing: []) }
        let dir = try home.dir("Downloads/dossier")
        #expect(throws: CleanRefusal.notRegularFile) { try cleaner.verifyCopy(request(dir, keeper: keeper), removing: []) }
    }

    @Test("Comparaison octet par octet, y compris au-delà d'un bloc de lecture")
    func sameContent() throws {
        let home = try FakeHome()
        let big = String(repeating: "z", count: (1 << 20) + 10)
        let a = try write(home, "a", big)
        let b = try write(home, "b", big)
        let c = try write(home, "c", String(big.dropLast()) + "y")
        let d = try write(home, "d", String(big.dropLast()))
        #expect(Cleaner.sameContent(a, b))
        #expect(!Cleaner.sameContent(a, c))
        #expect(!Cleaner.sameContent(a, d))
    }

    @Test("Règle à contrôle : validée strictement, ignorée par le scanner")
    func ruleValidationAndScanner() async throws {
        let glob = Rule(id: "x", name: "x", category: .duplicates, risk: .review, explanation: "",
                        paths: ["~/Downloads/*"], check: .duplicateCopy)
        #expect(throws: RuleError.self) { try RuleBook(rules: [glob]) }
        let safe = Rule(id: "x", name: "x", category: .duplicates, risk: .safe, explanation: "",
                        paths: ["~/Downloads"], check: .duplicateCopy)
        #expect(throws: RuleError.self) { try RuleBook(rules: [safe]) }
        let regenerable = Rule(id: "x", name: "x", category: .duplicates, risk: .review, explanation: "",
                               paths: ["~/Downloads"], regenerable: true, check: .duplicateCopy)
        #expect(throws: RuleError.self) { try RuleBook(rules: [regenerable]) }

        let home = try FakeHome()
        try write(home, "Downloads/f.txt", "x")
        let result = try await Scanner(policy: ProtectionPolicy(home: home.path)).scan(rules: [rule])
        #expect(result.items.isEmpty)
    }

    @Test("La règle livrée est chargée")
    func bundledRule() throws {
        let book = try RuleBook.bundled()
        let bundled = try #require(book.rule(id: "doublons.copies"))
        #expect(bundled.check == .duplicateCopy)
        #expect(bundled.risk == .review)
        #expect(!bundled.isSelectedByDefault)
    }
}
