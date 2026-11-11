import Darwin
import Foundation
import Testing
@testable import CleanmacCore

@Suite("Carte du disque")
struct DiskMapTests {
    @Test("La taille de la racine égale celle du calcul des tailles")
    func totalMatchesSizeCalculator() async throws {
        let home = try FakeHome()
        try home.file("a/un", bytes: 30_000)
        try home.file("a/b/deux", bytes: 120_000)
        try home.file("trois", bytes: 5_000)
        let map = try await DiskMapper().map(home.path)
        let expected = try SizeCalculator().measure(home.path)
        #expect(map.root.allocatedBytes == expected.allocatedBytes)
        #expect(map.root.fileCount == 3)
        #expect(map.unreadableCount == 0)
    }

    @Test("Contenu trié du plus gros au plus petit")
    func sortedChildren() async throws {
        let home = try FakeHome()
        try home.file("petit/f", bytes: 1_000)
        try home.file("gros/f", bytes: 500_000)
        try home.file("moyen", bytes: 50_000)
        let map = try await DiskMapper().map(home.path)
        #expect(map.root.children.map(\.name) == ["gros", "moyen", "petit"])
        #expect(map.root.children.first?.isDirectory == true)
        #expect(map.root.children[1].kind == .file)
    }

    @Test("Les petits éléments sont regroupés, sans perte de taille")
    func grouping() async throws {
        let home = try FakeHome()
        for i in 0..<6 { try home.file("f\(i)", bytes: 4_096 * (i + 1)) }
        var mapper = DiskMapper()
        mapper.alwaysKept = 2
        mapper.maxChildren = 3
        mapper.minKeptBytes = 1 << 30
        let map = try await mapper.map(home.path)
        let children = map.root.children
        #expect(children.count == 3)
        #expect(children.map(\.name).prefix(2) == ["f5", "f4"])
        #expect(children.last?.kind == .others(count: 4))
        #expect(children.last?.fileCount == 4)
        let sum = children.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        #expect(sum <= map.root.allocatedBytes)
        #expect(map.root.fileCount == 6)
    }

    @Test("Un lien symbolique n'est pas suivi")
    func symlinks() async throws {
        let home = try FakeHome()
        try home.file("dehors/gros", bytes: 2_000_000)
        try home.dir("carte")
        try FileManager.default.createSymbolicLink(atPath: home.url("carte/lien"), withDestinationPath: home.url("dehors"))
        let map = try await DiskMapper().map(home.url("carte"))
        #expect(map.root.allocatedBytes < 100_000)
    }

    @Test("Un lien physique n'est compté qu'une fois")
    func hardLinks() async throws {
        let home = try FakeHome()
        let a = try home.file("a", bytes: 300_000)
        try FileManager.default.linkItem(atPath: a, toPath: home.url("b"))
        let map = try await DiskMapper().map(home.path)
        #expect(map.root.fileCount == 1)
        #expect(map.root.allocatedBytes < 600_000)
    }

    @Test("Gros fichiers repérés, du plus gros au plus petit")
    func largestFiles() async throws {
        let home = try FakeHome()
        try home.file("x/moyen", bytes: 200_000)
        try home.file("gros", bytes: 900_000)
        try home.file("petit", bytes: 1_000)
        var mapper = DiskMapper()
        mapper.largeFileMinimum = 100_000
        mapper.largeFileCount = 5
        let map = try await mapper.map(home.path)
        #expect(map.largestFiles.map(\.name) == ["gros", "moyen"])
        #expect(map.largestFiles.first?.path == home.url("gros"))
    }

    @Test("Le nombre de gros fichiers est plafonné")
    func largestFilesCap() async throws {
        let home = try FakeHome()
        for i in 1...5 { try home.file("f\(i)", bytes: 20_000 * i) }
        var mapper = DiskMapper()
        mapper.largeFileMinimum = 1
        mapper.largeFileCount = 2
        let map = try await mapper.map(home.path)
        #expect(map.largestFiles.map(\.name) == ["f5", "f4"])
    }

    @Test("Retrouver un dossier par son chemin")
    func descendant() async throws {
        let home = try FakeHome()
        try home.file("a/b/c/f", bytes: 10_000)
        let map = try await DiskMapper().map(home.path)
        #expect(map.root.descendant(at: home.url("a/b"))?.name == "b")
        #expect(map.root.descendant(at: home.url("a/b/c"))?.fileCount == 1)
        #expect(map.root.descendant(at: home.url("ailleurs")) == nil)
        #expect(map.root.descendant(at: "/tmp") == nil)
    }

    @Test("Racine absente : erreur claire")
    func missingRoot() async {
        await #expect(throws: DiskMapError.unreadableRoot("/chemin/absent")) {
            try await DiskMapper().map("/chemin/absent")
        }
    }

    @Test("Annulation pendant la cartographie")
    func cancellation() async throws {
        let home = try FakeHome()
        for i in 0..<50 { try home.file("d/f\(i)", bytes: 1) }
        let mapper = {
            var m = DiskMapper()
            m.reportEvery = 1
            return m
        }()
        let path = home.path
        let task = Task { try await mapper.map(path) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Anneaux : secteurs proportionnels, couleur héritée")
    func sunburst() async throws {
        let home = try FakeHome()
        try home.file("a/un", bytes: 400_000)
        try home.file("a/deux", bytes: 400_000)
        try home.file("b", bytes: 200_000)
        let map = try await DiskMapper().map(home.path)
        let segments = SunburstLayout.segments(for: map.root, levels: 2)
        let first = segments.filter { $0.depth == 1 }
        #expect(first.map(\.node.name) == ["a", "b"])
        #expect(first[0].start == 0)
        #expect(first[0].span > first[1].span)
        let total = first.reduce(0) { $0 + $1.span }
        #expect(total <= 1.000_001)
        let inner = segments.filter { $0.depth == 2 }
        #expect(inner.count == 2)
        #expect(inner.allSatisfy { $0.colorIndex == first[0].colorIndex })
        #expect(inner.allSatisfy { $0.start >= first[0].start && $0.end <= first[0].end + 1e-9 })
    }

    @Test("Anneaux : nombre de niveaux respecté et petits secteurs ignorés")
    func sunburstLimits() async throws {
        let home = try FakeHome()
        try home.file("a/b/c/d/f", bytes: 100_000)
        try home.file("gros", bytes: 10_000_000)
        try home.file("minuscule", bytes: 1)
        let map = try await DiskMapper().map(home.path)
        let segments = SunburstLayout.segments(for: map.root, levels: 2, minSpan: 0.001)
        #expect(segments.allSatisfy { $0.depth <= 2 })
        #expect(!segments.contains { $0.node.name == "minuscule" })
    }
}
