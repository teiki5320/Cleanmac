import Foundation
import Testing
@testable import CleanmacCore

@Suite("Base de règles")
struct RuleBookTests {
    @Test("Les règles livrées se chargent et sont valides")
    func bundledRulesLoad() throws {
        let book = try RuleBook.bundled()
        #expect(!book.rules.isEmpty)
        #expect(book.rule(id: "systeme.caches-utilisateur")?.risk == .safe)
        #expect(book.rule(id: "systeme.etat-applications")?.isSelectedByDefault == false)
    }

    @Test("Décodage d'un fichier avec valeurs par défaut")
    func decodeDefaults() throws {
        let json = """
        { "version": 1, "rules": [
          { "id": "a", "name": "A", "category": "developer", "risk": "review",
            "explanation": "x", "paths": ["~/Library/Developer/Xcode/DerivedData/*"] } ] }
        """
        let book = try RuleBook.decode(Data(json.utf8))
        let rule = try #require(book.rule(id: "a"))
        #expect(rule.category == .developer)
        #expect(rule.excludes.isEmpty)
        #expect(rule.regenerable == false)
        #expect(rule.isSelectedByDefault == false)
    }

    @Test("Catégorie inconnue refusée")
    func unknownCategory() {
        let json = """
        { "version": 1, "rules": [
          { "id": "a", "name": "A", "category": "virus", "risk": "safe",
            "explanation": "x", "paths": ["~/Library/Caches/*"] } ] }
        """
        #expect(throws: (any Error).self) { try RuleBook.decode(Data(json.utf8)) }
    }

    @Test("Identifiants en double refusés")
    func duplicateIDs() {
        #expect(throws: RuleError.duplicateID("x")) {
            try RuleBook(rules: [makeRule(id: "x"), makeRule(id: "x")])
        }
    }

    @Test("Règle sans chemin refusée")
    func emptyPaths() {
        #expect(throws: RuleError.emptyPaths(ruleID: "x")) {
            try RuleBook(rules: [makeRule(id: "x", paths: [])])
        }
    }

    @Test("Chemins dangereux refusés", arguments: [
        "/", "~", "~/", "~/*", "/*", "/Users", "Library/Caches",
        "~/Library/../Documents", "~/./Library", "~/Library//Caches", "~/**/x",
    ])
    func dangerousPaths(path: String) {
        #expect(throws: RuleError.self) {
            try RuleBook(rules: [makeRule(paths: [path])])
        }
    }

    @Test("Chemins raisonnables acceptés", arguments: [
        "~/Library/Caches/*", "~/.Trash/*", "/Library/Caches/*", "~/Library/Logs/*.log",
    ])
    func acceptablePaths(path: String) throws {
        _ = try RuleBook(rules: [makeRule(paths: [path])])
    }

    @Test("Chargement d'un dossier de règles")
    func loadDirectory() throws {
        let home = try FakeHome()
        try Data("""
        { "version": 1, "rules": [ { "id": "b", "name": "B", "category": "trash",
          "risk": "safe", "explanation": "x", "paths": ["~/.Trash/*"] } ] }
        """.utf8).write(to: URL(fileURLWithPath: home.url("b.json")))
        try Data("pas du json".utf8).write(to: URL(fileURLWithPath: home.url("notes.txt")))
        let book = try RuleBook.load(directory: URL(fileURLWithPath: home.path))
        #expect(book.rules.map(\.id) == ["b"])
    }
}
