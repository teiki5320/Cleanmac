import Darwin
import Foundation
import Testing
@testable import CleanmacCore

@Suite("Calcul des tailles")
struct SizeCalculatorTests {
    let calculator = SizeCalculator()

    /// Espace alloué attendu pour un fichier, d'après le système.
    func allocated(_ path: String) -> Int64 {
        var st = stat()
        lstat(path, &st)
        return Int64(st.st_blocks) * 512
    }

    @Test("Un fichier : espace alloué, au moins sa taille")
    func singleFile() throws {
        let home = try FakeHome()
        let file = try home.file("a", bytes: 10_000)
        let m = try calculator.measure(file)
        #expect(m.fileCount == 1)
        #expect(m.allocatedBytes == allocated(file))
        #expect(m.allocatedBytes >= 10_000)
        #expect(m.allocatedBytes % 512 == 0)
    }

    @Test("Un dossier : somme récursive")
    func directory() throws {
        let home = try FakeHome()
        let a = try home.file("d/a", bytes: 5_000)
        let b = try home.file("d/sous/b", bytes: 70_000)
        let m = try calculator.measure(home.url("d"))
        #expect(m.fileCount == 2)
        #expect(m.allocatedBytes >= allocated(a) + allocated(b))
        #expect(m.allocatedBytes >= 75_000)
    }

    @Test("Un lien physique n'est compté qu'une fois")
    func hardLinks() throws {
        let home = try FakeHome()
        let a = try home.file("d/a", bytes: 100_000)
        try FileManager.default.linkItem(atPath: a, toPath: home.url("d/b"))
        let m = try calculator.measure(home.url("d"))
        #expect(m.fileCount == 1)
        #expect(m.allocatedBytes < 2 * allocated(a))
    }

    @Test("Un lien symbolique n'est pas suivi")
    func symlinks() throws {
        let home = try FakeHome()
        try home.file("gros/f", bytes: 1_000_000)
        try home.dir("d")
        try FileManager.default.createSymbolicLink(
            atPath: home.url("d/lien"), withDestinationPath: home.url("gros"))
        let m = try calculator.measure(home.url("d"))
        #expect(m.allocatedBytes < 100_000)
    }

    @Test("Détection d'un .git à l'intérieur")
    func gitDetection() throws {
        let home = try FakeHome()
        try home.file("d/repo/.git/HEAD")
        let m = try calculator.measure(home.url("d"), stopAtGit: true)
        #expect(m.gitDirectory == home.url("d/repo/.git"))
    }

    @Test("Élément absent : compté illisible, taille nulle")
    func missing() throws {
        let m = try calculator.measure("/chemin/qui/n/existe/pas")
        #expect(m.allocatedBytes == 0)
        #expect(m.unreadableCount == 1)
    }

    @Test("Annulation pendant le calcul")
    func cancellation() async throws {
        let home = try FakeHome()
        for i in 0..<50 { try home.file("d/f\(i)", bytes: 1) }
        let calc = {
            var c = SizeCalculator()
            c.reportEvery = 5
            return c
        }()
        let path = home.url("d")
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try calc.measure(path)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
