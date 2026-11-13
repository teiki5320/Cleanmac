import Foundation
import Testing
@testable import CleanmacCore

/// Suppresseur qui refuse de mettre à la Corbeille les chemins donnés (paquet appartenant au système…).
final class FailingRemover: FileRemoving, @unchecked Sendable {
    let refused: Set<String>
    private let lock = NSLock()
    private(set) var trashed: [String] = []
    init(refusing refused: Set<String>) { self.refused = refused }
    func trash(_ path: String) throws -> String? {
        if refused.contains(path) { throw CocoaError(.fileWriteNoPermission) }
        lock.withLock { trashed.append(path) }
        return nil
    }
    func removePermanently(_ path: String) throws {}
}

@Suite("Corrections de l'audit")
struct AuditFixesTests {
    func appRule() -> Rule {
        Rule(id: "applications.appli", name: "Appli", category: .apps, risk: .safe, explanation: "x",
             paths: ["~/Applications/{appName}.app", "~/Library/Preferences/{bundleID}.plist"], check: .appFiles)
    }

    func makeApp(_ home: FakeHome, id: String = "com.exemple.Truc") throws -> String {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
        let path = home.url("Applications/Truc.app/Contents/Info.plist")
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try plist.write(to: URL(fileURLWithPath: path))
        return home.url("Applications/Truc.app")
    }

    @Test("Désinstallation : si l'appli reste en place, ses réglages sont gardés")
    func uninstallIsAllOrNothing() async throws {
        let home = try FakeHome()
        let app = try makeApp(home)
        let prefs = try home.file("Library/Preferences/com.exemple.Truc.plist")
        let remover = FailingRemover(refusing: [app])
        let cleaner = Cleaner(rules: try RuleBook(rules: [appRule()]), policy: ProtectionPolicy(home: home.path),
                              remover: remover, journal: CleanJournal(fileURL: URL(fileURLWithPath: home.url("j.json"))), apps: FakeApps())
        let identity = AppIdentity(bundleID: "com.exemple.Truc", name: "Truc")
        // Les réglages sont demandés en premier : le paquet passe quand même d'abord.
        let entry = try await cleaner.clean([CleanRequest(path: prefs, ruleID: "applications.appli", bytes: 1, app: identity),
                                             CleanRequest(path: app, ruleID: "applications.appli", bytes: 1, app: identity)])
        #expect(remover.trashed.isEmpty)
        #expect(entry.items.first { $0.path == prefs }?.message == CleanRefusal.appBundleKept.description)
    }

    @Test("Le paquet doit être celui de l'appli nommée")
    func bundleMismatch() throws {
        let home = try FakeHome()
        let app = try makeApp(home, id: "com.autre.Appli")
        let cleaner = Cleaner(rules: try RuleBook(rules: [appRule()]), policy: ProtectionPolicy(home: home.path),
                              remover: RecordingRemover(), apps: FakeApps())
        #expect(throws: CleanRefusal.appBundleMismatch) {
            try cleaner.validate(CleanRequest(path: app, ruleID: "applications.appli", bytes: 1,
                                              app: AppIdentity(bundleID: "com.exemple.Truc", name: "Truc")))
        }
    }

    @Test("Un lien symbolique au milieu du chemin est refusé, et pas proposé")
    func symlinkedParent() async throws {
        let home = try FakeHome()
        try home.file("Documents/ComfyUI/models/gros.bin", bytes: 5000)
        try FileManager.default.createSymbolicLink(atPath: home.url("ComfyUI"), withDestinationPath: home.url("Documents/ComfyUI"))
        let rule = makeRule(id: "dev.comfy", risk: .review, paths: ["~/ComfyUI/models/*"])
        let cleaner = Cleaner(rules: try RuleBook(rules: [rule]), policy: ProtectionPolicy(home: home.path), remover: RecordingRemover())
        #expect(throws: CleanRefusal.symlinkInPath) {
            try cleaner.validate(CleanRequest(path: home.url("ComfyUI/models/gros.bin"), ruleID: rule.id, bytes: 1))
        }
        let result = try await Scanner(policy: ProtectionPolicy(home: home.path)).scan(rules: [rule])
        #expect(result.items.isEmpty)
    }

    @Test("Préférences ByHost : pas celles d'une variante (Canary, Beta)")
    func byHostIsStrict() throws {
        let book = try RuleBook.bundled()
        let rule = try #require(book.rule(id: "applications.appli"))
        let pattern = PathPattern(home: "/Users/x")
        let chrome = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")
        #expect(pattern.matches("/Users/x/Library/Preferences/ByHost/com.google.Chrome.1A2B3C4D-1111-2222-3333-444455556666.plist", rule: rule, app: chrome))
        #expect(!pattern.matches("/Users/x/Library/Preferences/ByHost/com.google.Chrome.canary.1A2B3C4D-1111-2222-3333-444455556666.plist", rule: rule, app: chrome))
    }

    @Test("Un parent d'un chemin déjà pris n'est pas compté une seconde fois")
    func parentNotDoubleCounted() async throws {
        let home = try FakeHome()
        try home.file("Library/Caches/Homebrew/downloads/a.tar.gz", bytes: 4000)
        let child = makeRule(id: "dev.homebrew", paths: ["~/Library/Caches/Homebrew/*"])
        let parent = makeRule(id: "systeme.caches", paths: ["~/Library/Caches/*"])
        let result = try await Scanner(policy: ProtectionPolicy(home: home.path)).scan(rules: [child, parent])
        #expect(result.items.map(\.ruleID) == ["dev.homebrew"])
    }

    @Test("Journal illisible : mis de côté, pas écrasé")
    func corruptJournalIsKept() throws {
        let home = try FakeHome()
        let url = URL(fileURLWithPath: home.url("support/journal.json"))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pas du JSON".utf8).write(to: url)
        try CleanJournal(fileURL: url).append(JournalEntry(items: []))
        let files = try FileManager.default.contentsOfDirectory(atPath: home.url("support"))
        #expect(files.contains { $0.contains("illisible") })
        #expect(CleanJournal(fileURL: url).entries().count == 1)
    }

    @Test("Exclusions illisibles : erreur, et rien n'est écrasé")
    func corruptExclusions() throws {
        let home = try FakeHome()
        let url = URL(fileURLWithPath: home.url("exclusions.json"))
        try Data("{".utf8).write(to: url)
        let store = ExclusionStore(fileURL: url)
        #expect(throws: (any Error).self) { try store.loadStrict() }
        #expect(throws: (any Error).self) { try store.add("/tmp/x") }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{")
    }

    @Test("Règles plus strictes : Corbeille jamais « sûre », journaux non régénérables")
    func stricterRules() throws {
        let safeTrash = Rule(id: "x", name: "x", category: .trash, risk: .safe, explanation: "", paths: ["~/.Trash/*"], inTrash: true)
        #expect(throws: RuleError.self) { try RuleBook(rules: [safeTrash]) }
        let book = try RuleBook.bundled()
        #expect(book.rule(id: "systeme.journaux-utilisateur")?.regenerable == false)
        #expect(ProtectionPolicy(home: "/Users/x").protection(for: "/Users/x/.ssh/id_ed25519") != nil)
    }

    @Test("Doublons : un fichier rangé dans un paquet est refusé")
    func duplicateInsidePackage() throws {
        let home = try FakeHome()
        let keeper = try home.file("Downloads/a.wav", bytes: 50)
        let inside = try home.file("Music/Projet.logicx/Media/a.wav", bytes: 50)
        let rule = Rule(id: "doublons.copies", name: "d", category: .duplicates, risk: .review, explanation: "",
                        paths: ["~/Downloads", "~/Music"], check: .duplicateCopy)
        let cleaner = Cleaner(rules: try RuleBook(rules: [rule]), policy: ProtectionPolicy(home: home.path), remover: RecordingRemover())
        #expect(throws: CleanRefusal.insidePackage) {
            try cleaner.validate(CleanRequest(path: inside, ruleID: rule.id, bytes: 1, keeperPath: keeper))
        }
    }

    @Test("iCloud : jamais un dossier entier")
    func icloudRefusesFolders() throws {
        let home = try FakeHome()
        let folder = try home.dir("Library/Mobile Documents/com~apple~CloudDocs/Projets")
        try home.file("Library/Mobile Documents/com~apple~CloudDocs/Projets/a.txt")
        let service = ICloudEvictionService(home: home.path, evictor: ICloudTests.FakeEvictor(uploaded: [folder]))
        #expect(throws: EvictRefusal.outsideICloud) { try service.validate(folder) }
    }

    @Test("Sparkle : versions bêta et incompatibles ignorées")
    func sparkleChannels() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>200</sparkle:version><sparkle:channel>beta</sparkle:channel></item>
        <item><sparkle:version>150</sparkle:version><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion></item>
        <item><sparkle:version>120</sparkle:version></item>
        </channel></rss>
        """
        #expect(Appcast.latest(Appcast.parse(Data(xml.utf8)))?.version == "120")
    }

    @Test("Outil arrêté quand la tâche est annulée")
    func toolCancellation() async throws {
        let task = Task { try await ToolRunner.run("/bin/sleep", ["30"]) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let start = ContinuousClock.now
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}

@Suite("Progression des doublons")
struct DuplicateProgressTests {
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        func add(_ v: Double?) { if let v { lock.withLock { values.append(v) } } }
        var all: [Double] { lock.withLock { values } }
    }

    @Test("La jauge avance pendant la lecture des gros fichiers et finit à 100 %")
    func progressesThroughBigFiles() async throws {
        let home = try FakeHome()
        let size = 80 << 20
        try home.file("a/gros.bin", bytes: size)
        try home.file("b/gros.bin", bytes: size)
        let log = Log()
        _ = try await DuplicateFinder().find(in: [home.path], excluding: []) { log.add($0.fractionCompleted) }
        let values = log.all
        #expect(values.last == 1)
        // Des valeurs intermédiaires pendant la lecture complète, toujours croissantes.
        #expect(values.contains { $0 > 0.1 && $0 < 0.95 })
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }
}

@Suite("Remettre en place")
struct RestoreTests {
    func trashed(_ home: FakeHome, original: String) throws -> JournalItem {
        let inTrash = try home.file(".Trash/" + (original as NSString).lastPathComponent, bytes: 100)
        return JournalItem(path: original, ruleID: "systeme.caches-utilisateur", bytes: 100, method: .trash,
                           succeeded: true, message: nil, trashedPath: inTrash)
    }

    @Test("Remet l'élément à sa place et l'inscrit au journal")
    func restores() throws {
        let home = try FakeHome()
        try home.dir("Library/Caches")
        let original = home.url("Library/Caches/com.exemple")
        let item = try trashed(home, original: original)
        let journal = CleanJournal(fileURL: URL(fileURLWithPath: home.url("j.json")))
        let entry = try TrashRestorer(home: home.path, journal: journal).restore(item)
        #expect(FileManager.default.fileExists(atPath: original))
        #expect(!FileManager.default.fileExists(atPath: item.trashedPath!))
        #expect(entry.items.first?.method == .restored)
        #expect(entry.trashedBytes == -100 && entry.freedBytes == 0)
        #expect(journal.entries().count == 1)
    }

    @Test("N'écrase jamais, ne recrée pas de dossier, refuse hors Corbeille")
    func refuses() throws {
        let home = try FakeHome()
        let existing = try home.file("Library/Caches/pris", bytes: 1)
        let restorer = TrashRestorer(home: home.path, journal: CleanJournal(fileURL: URL(fileURLWithPath: home.url("j.json"))))
        #expect(throws: RestoreRefusal.originalExists) { try restorer.validate(try trashed(home, original: existing)) }
        #expect(throws: RestoreRefusal.parentMissing) {
            try restorer.validate(try trashed(home, original: home.url("Disparu/dossier/x")))
        }
        let outside = try home.file("Ailleurs/x", bytes: 1)
        let fake = JournalItem(path: home.url("Library/Caches/y"), ruleID: "r", bytes: 1, method: .trash,
                               succeeded: true, message: nil, trashedPath: outside)
        #expect(throws: RestoreRefusal.notInTrash) { try restorer.validate(fake) }
        let permanent = JournalItem(path: home.url("Library/Caches/z"), ruleID: "r", bytes: 1, method: .permanent,
                                    succeeded: true, message: nil, trashedPath: nil)
        #expect(throws: RestoreRefusal.notRestorable) { try restorer.validate(permanent) }
    }

    @Test("Nouvelles règles : caches App Store (hors Apple), sauvegardes iOS, installeurs, Docker")
    func newRules() throws {
        let book = try RuleBook.bundled()
        let pattern = PathPattern(home: "/Users/x")
        let caches = try #require(book.rule(id: "systeme.caches-applis-app-store"))
        #expect(pattern.matches("/Users/x/Library/Containers/com.tiers.App/Data/Library/Caches/images", rule: caches))
        #expect(!pattern.matches("/Users/x/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/x", rule: caches))
        for id in ["systeme.sauvegardes-ios", "systeme.installeurs-macos", "systeme.docker-disque"] {
            #expect(book.rule(id: id)?.risk == .review, "règle \(id)")
        }
    }
}
