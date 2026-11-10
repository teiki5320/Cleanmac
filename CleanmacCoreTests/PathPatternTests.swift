import Foundation
import Testing
@testable import CleanmacCore

@Suite("Motifs de chemins")
struct PathPatternTests {
    @Test("Expansion de ~ et des jokers")
    func expandGlob() throws {
        let home = try FakeHome()
        try home.file("Library/Caches/com.a/f")
        try home.file("Library/Caches/com.b")
        try home.file("Library/Caches/.cache-cache")
        try home.file("Library/Other/x")
        let pattern = PathPattern(home: home.path)
        let found = pattern.expand(makeRule())
        #expect(found == [
            home.url("Library/Caches/.cache-cache"),
            home.url("Library/Caches/com.a"),
            home.url("Library/Caches/com.b"),
        ])
    }

    @Test("Les exclusions de la règle sont respectées")
    func excludes() throws {
        let home = try FakeHome()
        try home.file("Library/Caches/garder/f")
        try home.file("Library/Caches/jeter/f")
        let rule = makeRule(excludes: ["~/Library/Caches/garder"])
        let found = PathPattern(home: home.path).expand(rule: rule)
        #expect(found == [home.url("Library/Caches/jeter")])
    }

    @Test("Aucun résultat si le dossier n'existe pas")
    func missingDirectory() throws {
        let home = try FakeHome()
        #expect(PathPattern(home: home.path).expand(rule: makeRule()).isEmpty)
    }

    @Test("Les jokers ne traversent pas un lien symbolique")
    func noSymlinkTraversal() throws {
        let home = try FakeHome()
        try home.file("Secret/document")
        try home.dir("Library/Caches")
        try FileManager.default.createSymbolicLink(
            atPath: home.url("Library/Caches/lien"), withDestinationPath: home.url("Secret"))
        let rule = makeRule(paths: ["~/Library/Caches/*/*"])
        #expect(PathPattern(home: home.path).expand(rule: rule).isEmpty)
    }

    @Test("Correspondance d'un chemin avec la règle")
    func matching() throws {
        let pattern = PathPattern(home: "/Users/test")
        let rule = makeRule(excludes: ["~/Library/Caches/CloudKit"])
        #expect(pattern.matches("/Users/test/Library/Caches/com.a", rule: rule))
        #expect(!pattern.matches("/Users/test/Library/Caches/com.a/sous", rule: rule))
        #expect(!pattern.matches("/Users/test/Library/Caches/CloudKit", rule: rule))
        #expect(!pattern.matches("/Users/test/Documents/x", rule: rule))
    }
}

extension PathPattern {
    func expand(_ rule: Rule) -> [String] { expand(rule: rule) }
}
