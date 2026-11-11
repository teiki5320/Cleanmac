import Darwin
import Foundation
import Testing
@testable import CleanmacCore

@Suite("Doublons et types de fichiers")
struct DuplicateFinderTests {
    /// Recherche avec un seuil bas, adapté aux petits fichiers de test.
    func finder() -> DuplicateFinder {
        var finder = DuplicateFinder()
        finder.minimumSize = 1
        finder.headBytes = 1_024
        return finder
    }

    @discardableResult
    func write(_ home: FakeHome, _ relative: String, _ content: String) throws -> String {
        let path = home.url(relative)
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data(content.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test("Deux fichiers identiques forment un groupe, un fichier différent non")
    func basicGroup() async throws {
        let home = try FakeHome()
        let content = String(repeating: "abc", count: 2_000)
        try write(home, "a/photo.jpg", content)
        try write(home, "b/photo copie.jpg", content)
        try write(home, "c/autre.jpg", String(repeating: "xyz", count: 2_000))
        let scan = try await finder().find(in: [home.path])
        #expect(scan.groups.count == 1)
        #expect(Set(scan.groups[0].files.map(\.name)) == ["photo.jpg", "photo copie.jpg"])
        #expect(scan.groups[0].kind == .image)
        #expect(scan.filesExamined == 3)
    }

    @Test("Même taille et même début, mais fin différente : pas un doublon")
    func sameHeadDifferentTail() async throws {
        let home = try FakeHome()
        let head = String(repeating: "a", count: 5_000)
        try write(home, "un.bin", head + "1")
        try write(home, "deux.bin", head + "2")
        let scan = try await finder().find(in: [home.path])
        #expect(scan.groups.isEmpty)
    }

    @Test("Petits fichiers identiques (plus courts que l'empreinte rapide)")
    func smallFiles() async throws {
        let home = try FakeHome()
        try write(home, "un.txt", "bonjour")
        try write(home, "deux.txt", "bonjour")
        let scan = try await finder().find(in: [home.path])
        #expect(scan.groups.count == 1)
    }

    @Test("Sous le seuil de taille : ignoré")
    func minimumSize() async throws {
        let home = try FakeHome()
        try write(home, "un.txt", "bonjour")
        try write(home, "deux.txt", "bonjour")
        var finder = finder()
        finder.minimumSize = 1_000
        let scan = try await finder.find(in: [home.path])
        #expect(scan.groups.isEmpty)
        #expect(scan.filesExamined == 0)
    }

    @Test("Un lien physique n'est pas un doublon")
    func hardLink() async throws {
        let home = try FakeHome()
        let a = try write(home, "a.bin", String(repeating: "z", count: 3_000))
        try FileManager.default.linkItem(atPath: a, toPath: home.url("b.bin"))
        let scan = try await finder().find(in: [home.path])
        #expect(scan.groups.isEmpty)
    }

    @Test("Cachés, paquets, dépôts de code et dossiers exclus sont ignorés")
    func skippedPlaces() async throws {
        let home = try FakeHome()
        let content = String(repeating: "q", count: 3_000)
        try write(home, "garde.bin", content)
        try write(home, ".cache/copie.bin", content)
        try write(home, "Truc.app/Contents/copie.bin", content)
        try write(home, "Photos.photoslibrary/copie.bin", content)
        try write(home, "code/projet/copie.bin", content)
        try home.dir("code/projet/.git")
        try write(home, "Library/copie.bin", content)
        try write(home, ".cachee.bin", content)
        let scan = try await finder().find(in: [home.path], excluding: [home.url("Library")])
        #expect(scan.groups.isEmpty)
        #expect(scan.filesExamined == 1)
    }

    @Test("Un lien symbolique n'est pas suivi")
    func symlinks() async throws {
        let home = try FakeHome()
        let content = String(repeating: "s", count: 3_000)
        try write(home, "dehors/a.bin", content)
        try write(home, "dehors/b.bin", content)
        try home.dir("dedans")
        try FileManager.default.createSymbolicLink(atPath: home.url("dedans/lien"), withDestinationPath: home.url("dehors"))
        let scan = try await finder().find(in: [home.url("dedans")])
        #expect(scan.groups.isEmpty)
    }

    @Test("Suggestion : garder l'exemplaire hors Téléchargements, puis le plus ancien")
    func suggestedKeep() {
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        let files = [
            DuplicateFile(path: "/u/Downloads/a.pdf", allocatedBytes: 10, modified: old, mayShareBlocks: false),
            DuplicateFile(path: "/u/Documents/recent/a.pdf", allocatedBytes: 10, modified: recent, mayShareBlocks: false),
            DuplicateFile(path: "/u/Documents/a.pdf", allocatedBytes: 10, modified: old, mayShareBlocks: false),
        ]
        let ordered = DuplicateFinder.ordered(files).map(\.path)
        #expect(ordered == ["/u/Documents/a.pdf", "/u/Documents/recent/a.pdf", "/u/Downloads/a.pdf"])
    }

    @Test("Espace perdu : les exemplaires en trop, hors copies APFS")
    func wastedBytes() {
        let date = Date()
        let group = DuplicateGroup(id: "x", size: 100, files: [
            DuplicateFile(path: "/a", allocatedBytes: 4_096, modified: date, mayShareBlocks: false),
            DuplicateFile(path: "/b", allocatedBytes: 4_096, modified: date, mayShareBlocks: false),
            DuplicateFile(path: "/c", allocatedBytes: 4_096, modified: date, mayShareBlocks: true),
        ])
        #expect(group.wastedBytes == 4_096)
        #expect(group.hasClones)
    }

    @Test("Une copie APFS (clone) est reconnue")
    func cloneDetection() async throws {
        let home = try FakeHome()
        let original = try write(home, "original.bin", String(repeating: "c", count: 200_000))
        let clone = home.url("clone.bin")
        #expect(clonefile(original, clone, 0) == 0)
        #expect(DuplicateFinder.mayShareBlocks(clone))
        let plain = try write(home, "seul.bin", String(repeating: "d", count: 200_000))
        #expect(!DuplicateFinder.mayShareBlocks(plain))
        let scan = try await finder().find(in: [home.path])
        #expect(scan.groups.count == 1)
        #expect(scan.groups[0].hasClones)
    }

    @Test("Annulation pendant la recherche")
    func cancellation() async throws {
        let home = try FakeHome()
        for i in 0..<40 { try write(home, "f\(i).bin", "identique") }
        let finder = finder()
        let path = home.path
        let task = Task { try await finder.find(in: [path]) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Types de fichiers d'après l'extension")
    func fileKinds() {
        #expect(FileKind.of("/a/film.MOV") == .video)
        #expect(FileKind.of("/a/Xcode.xip") == .archive)
        #expect(FileKind.of("/a/disque.dmg") == .archive)
        #expect(FileKind.of("/a/photo.HEIC") == .image)
        #expect(FileKind.of("/a/son.m4a") == .audio)
        #expect(FileKind.of("/a/facture.pdf") == .document)
        #expect(FileKind.of("/a/sans-extension") == .other)
    }
}
