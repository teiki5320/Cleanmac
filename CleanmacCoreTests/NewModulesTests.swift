import Foundation
import Testing
@testable import CleanmacCore

/// Faux état des applis.
struct FakeApps: AppChecking {
    var running: Set<String> = []
    var installed: Set<String> = []
    func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
    func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
}

@Suite("Corbeilles")
struct TrashTests {
    let rule = Rule(id: "corbeilles.mac", name: "Corbeille", category: .trash, risk: .review,
                    explanation: "x", paths: ["~/.Trash/*"], inTrash: true)

    @Test("Vider la Corbeille : définitif, même sans le réglage, et journalisé")
    func emptiesTrash() async throws {
        let home = try FakeHome()
        let item = try home.file(".Trash/vieux.zip")
        let remover = RecordingRemover()
        let cleaner = Cleaner(rules: try RuleBook(rules: [rule]), policy: ProtectionPolicy(home: home.path),
                              remover: remover, journal: CleanJournal(fileURL: URL(fileURLWithPath: home.url("j.json"))),
                              allowPermanentDeletion: false)
        #expect(cleaner.method(for: rule) == .permanent)
        let entry = try await cleaner.clean([CleanRequest(path: item, ruleID: rule.id, bytes: 10)])
        #expect(remover.removed == [item])
        #expect(remover.trashed.isEmpty)
        #expect(entry.items.first?.method == .permanent)
    }

    @Test("Hors Corbeille ou dans un sous-dossier : refus")
    func refusesOutsideTrash() throws {
        let home = try FakeHome()
        let nested = try home.file(".Trash/dossier/fichier.txt")
        let cleaner = Cleaner(rules: try RuleBook(rules: [rule]), policy: ProtectionPolicy(home: home.path), remover: RecordingRemover())
        #expect(throws: CleanRefusal.notMatchingRule(ruleID: rule.id)) {
            try cleaner.validate(CleanRequest(path: nested, ruleID: rule.id, bytes: 1))
        }
        #expect(!TrashLocation.isDirectlyInTrash(nested, home: home.path))
        #expect(TrashLocation.isDirectlyInTrash(home.url(".Trash/dossier"), home: home.path))
    }

    @Test("Corbeille qui est un lien symbolique : refus")
    func refusesSymlinkedTrash() throws {
        let home = try FakeHome()
        let elsewhere = try home.dir("ailleurs")
        try home.file("ailleurs/important.txt")
        try FileManager.default.createSymbolicLink(atPath: home.url(".Trash"), withDestinationPath: elsewhere)
        #expect(!TrashLocation.isDirectlyInTrash(home.url(".Trash/important.txt"), home: home.path))
        #expect(!TrashLocation.isDirectlyInTrash("/Volumes/Disque/.Trashes/501/x", home: home.path, uid: 501))
    }

    @Test("Le scanner liste le contenu de la Corbeille ; une Corbeille contenant un dépôt git est écartée")
    func scansTrash() async throws {
        let home = try FakeHome()
        try home.file(".Trash/a.bin", bytes: 5000)
        try home.dir(".Trash/projet/.git")
        let result = try await Scanner(policy: ProtectionPolicy(home: home.path)).scan(rules: [rule])
        #expect(result.items.map(\.path) == [home.url(".Trash/a.bin")])
        #expect(result.skipped.count == 1)
    }

    @Test("Règles de Corbeille validées")
    func validation() {
        let bad = Rule(id: "x", name: "x", category: .trash, risk: .review, explanation: "",
                       paths: ["~/Downloads/*"], inTrash: true)
        #expect(throws: RuleError.self) { try RuleBook(rules: [bad]) }
        let volume = Rule(id: "y", name: "y", category: .trash, risk: .review, explanation: "",
                          paths: ["/Volumes/*/.Trashes/{uid}/*"], inTrash: true)
        #expect(throws: Never.self) { try RuleBook(rules: [volume]) }
        #expect(PathPattern(home: "/Users/a", uid: 501).absolute("/Volumes/*/.Trashes/{uid}/*") == "/Volumes/*/.Trashes/501/*")
    }
}

@Suite("Applications")
struct AppRulesTests {
    let files = Rule(id: "applications.appli", name: "Appli", category: .apps, risk: .safe, explanation: "x",
                     paths: ["~/Applications/{appName}.app", "~/Library/Preferences/{bundleID}.plist",
                             "~/Library/Preferences/ByHost/{bundleID}.[0-9A-F]*.plist"], check: .appFiles)
    let leftover = Rule(id: "applications.restes", name: "Restes", category: .apps, risk: .review, explanation: "x",
                        paths: ["~/Library/Caches/{bundleID}", "~/Library/Preferences/{bundleID}.plist"], check: .appLeftover)
    let app = AppIdentity(bundleID: "com.exemple.Truc", name: "Truc")

    func cleaner(_ home: FakeHome, apps: FakeApps = FakeApps(), remover: RecordingRemover = RecordingRemover()) throws -> Cleaner {
        Cleaner(rules: try RuleBook(rules: [files, leftover]), policy: ProtectionPolicy(home: home.path),
                remover: remover, journal: CleanJournal(fileURL: URL(fileURLWithPath: home.url("j.json"))), apps: apps)
    }

    @Test("Fichiers de l'appli nommée : autorisés ; ceux d'une autre appli : refusés")
    func templateMatching() throws {
        let home = try FakeHome()
        let prefs = try home.file("Library/Preferences/com.exemple.Truc.plist")
        let host = try home.file("Library/Preferences/ByHost/com.exemple.Truc.ABC-123.plist")
        let other = try home.file("Library/Preferences/com.exemple.Trucmuche.plist")
        let cleaner = try cleaner(home)
        #expect(throws: Never.self) { try cleaner.validate(CleanRequest(path: prefs, ruleID: files.id, bytes: 1, app: app)) }
        #expect(throws: Never.self) { try cleaner.validate(CleanRequest(path: host, ruleID: files.id, bytes: 1, app: app)) }
        #expect(throws: CleanRefusal.notMatchingRule(ruleID: files.id)) {
            try cleaner.validate(CleanRequest(path: other, ruleID: files.id, bytes: 1, app: app))
        }
        #expect(throws: CleanRefusal.appRequired) { try cleaner.validate(CleanRequest(path: prefs, ruleID: files.id, bytes: 1)) }
        let sneaky = AppIdentity(bundleID: "com.exemple.Truc", name: "*")
        #expect(throws: CleanRefusal.appRequired) { try cleaner.validate(CleanRequest(path: prefs, ruleID: files.id, bytes: 1, app: sneaky)) }
    }

    @Test("Appli ouverte ou Cleanmac lui-même : refus")
    func runningAndSelf() throws {
        let home = try FakeHome()
        let prefs = try home.file("Library/Preferences/com.exemple.Truc.plist")
        let running = try cleaner(home, apps: FakeApps(running: ["com.exemple.Truc"]))
        #expect(throws: CleanRefusal.appRunning("Truc")) {
            try running.validate(CleanRequest(path: prefs, ruleID: files.id, bytes: 1, app: app))
        }
        let own = try home.file("Library/Preferences/com.teiki.cleanmac.plist")
        #expect(throws: CleanRefusal.ownApp) {
            try running.validate(CleanRequest(path: own, ruleID: files.id, bytes: 1,
                                              app: AppIdentity(bundleID: "com.teiki.cleanmac", name: "Cleanmac")))
        }
    }

    @Test("Désinstallation : tout à la Corbeille")
    func uninstallTrashes() async throws {
        let home = try FakeHome()
        let bundle = try home.dir("Applications/Truc.app/Contents")
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.exemple.Truc"], format: .xml, options: 0)
        try info.write(to: URL(fileURLWithPath: bundle + "/Info.plist"))
        let prefs = try home.file("Library/Preferences/com.exemple.Truc.plist")
        let remover = RecordingRemover()
        let cleaner = try cleaner(home, remover: remover)
        let appPath = (bundle as NSString).deletingLastPathComponent
        _ = try await cleaner.clean([CleanRequest(path: appPath, ruleID: files.id, bytes: 1, app: app),
                                     CleanRequest(path: prefs, ruleID: files.id, bytes: 1, app: app)])
        #expect(remover.trashed.sorted() == [appPath, prefs].sorted())
        #expect(remover.removed.isEmpty)
    }

    @Test("Restes : refusés si l'appli est installée")
    func leftoverInstalled() throws {
        let home = try FakeHome()
        let cache = try home.dir("Library/Caches/com.vieux.Machin")
        let id = AppIdentity(bundleID: "com.vieux.Machin", name: "com.vieux.Machin")
        #expect(throws: Never.self) { try cleaner(home).validate(CleanRequest(path: cache, ruleID: leftover.id, bytes: 1, app: id)) }
        #expect(throws: CleanRefusal.appStillInstalled) {
            try cleaner(home, apps: FakeApps(installed: ["com.vieux.Machin"]))
                .validate(CleanRequest(path: cache, ruleID: leftover.id, bytes: 1, app: id))
        }
    }

    @Test("Repérage des restes : éditeur encore installé et Apple écartés")
    func findsLeftovers() throws {
        let home = try FakeHome()
        try home.dir("Library/Caches/com.vieux.Machin")
        try home.file("Library/Preferences/com.vieux.Machin.plist")
        try home.dir("Library/Caches/com.google.Chrome")          // éditeur installé
        try home.dir("Library/Caches/com.apple.Safari")           // Apple
        try home.dir("Library/Caches/pas-un-identifiant")
        let catalog = AppCatalog(home: home.path)
        let found = catalog.leftovers(rules: [leftover], knownIDs: ["com.google.Drive"],
                                      policy: ProtectionPolicy(home: home.path), isInstalled: { _ in false })
        #expect(found.map(\.bundleID) == ["com.vieux.Machin"])
        #expect(found.first?.files.count == 2)
    }

    @Test("Fichiers d'une appli trouvés par les règles")
    func findsAppFiles() throws {
        let home = try FakeHome()
        try home.file("Applications/Truc.app/Contents/Info.plist")
        try home.file("Library/Preferences/com.exemple.Truc.plist")
        let installed = InstalledApp(path: home.url("Applications/Truc.app"), fileName: "Truc", displayName: "Truc",
                                     bundleID: "com.exemple.Truc", version: "1", build: "1", sparkleFeed: nil, isAppStore: false)
        let found = AppCatalog(home: home.path).files(of: installed, rules: [files], policy: ProtectionPolicy(home: home.path))
        #expect(found.first?.path == installed.path)
        #expect(found.count == 2)
    }

    @Test("Validation des règles à jetons")
    func validation() {
        let noToken = Rule(id: "x", name: "x", category: .apps, risk: .safe, explanation: "",
                           paths: ["~/Library/Caches/truc"], check: .appFiles)
        #expect(throws: RuleError.self) { try RuleBook(rules: [noToken]) }
        let glued = Rule(id: "x", name: "x", category: .apps, risk: .safe, explanation: "",
                         paths: ["~/Library/Caches/{bundleID}*"], check: .appFiles)
        #expect(throws: RuleError.self) { try RuleBook(rules: [glued]) }
        let tokenElsewhere = Rule(id: "x", name: "x", category: .systemJunk, risk: .safe, explanation: "",
                                  paths: ["~/Library/Caches/{bundleID}"])
        #expect(throws: RuleError.self) { try RuleBook(rules: [tokenElsewhere]) }
        #expect(AppCatalog.looksLikeBundleID("com.vieux.Machin"))
        #expect(!AppCatalog.looksLikeBundleID("com.figma"))
        #expect(!AppCatalog.looksLikeBundleID("Google"))
    }

    @Test("Les règles livrées se chargent")
    func bundled() throws {
        let book = try RuleBook.bundled()
        for id in ["corbeilles.mac", "corbeilles.disques-externes", "mail.pieces-jointes", "mail.thunderbird-caches",
                   "applications.appli", "applications.donnees", "applications.restes"] {
            #expect(book.rule(id: id) != nil, "règle \(id)")
        }
    }
}

@Suite("iCloud Drive")
struct ICloudTests {
    struct FakeEvictor: ICloudEvicting, @unchecked Sendable {
        var uploaded: Set<String>
        let log = Log()
        final class Log: @unchecked Sendable { var paths: [String] = [] }
        func isUploaded(_ path: String) -> Bool { uploaded.contains(path) }
        func evict(_ path: String) async throws { log.paths.append(path) }
    }

    @Test("Inventaire : gros fichiers listés, petits ignorés, nom du dossier lisible")
    func scan() async throws {
        let home = try FakeHome()
        try home.file("Library/Mobile Documents/com~apple~CloudDocs/Films/gros.mov", bytes: 300_000)
        try home.file("Library/Mobile Documents/com~apple~CloudDocs/petit.txt", bytes: 10)
        try home.file("Library/Mobile Documents/iCloud~md~obsidian/notes.zip", bytes: 200_000)
        let result = try await ICloudScanner(root: home.url("Library/Mobile Documents"), minimumBytes: 100_000).scan()
        #expect(result.files.count == 2)
        #expect(Set(result.files.map(\.container)) == ["iCloud Drive", "obsidian"])
    }

    @Test("Libération : seulement dans iCloud Drive, et seulement si envoyé")
    func evict() async throws {
        let home = try FakeHome()
        let ok = try home.file("Library/Mobile Documents/com~apple~CloudDocs/a.mov", bytes: 100)
        let pending = try home.file("Library/Mobile Documents/com~apple~CloudDocs/b.mov", bytes: 100)
        let outside = try home.file("Downloads/c.mov", bytes: 100)
        let evictor = FakeEvictor(uploaded: [ok, outside])
        let service = ICloudEvictionService(home: home.path, evictor: evictor,
                                            journal: CleanJournal(fileURL: URL(fileURLWithPath: home.url("j.json"))))
        let entry = try await service.evict([(ok, 100), (pending, 100), (outside, 100)])
        #expect(evictor.log.paths == [ok])
        #expect(entry.items.map(\.succeeded) == [true, false, false])
        #expect(entry.items[1].message == EvictRefusal.notUploaded.description)
        #expect(entry.items[2].message == EvictRefusal.outsideICloud.description)
        #expect(entry.items.allSatisfy { $0.method == .evicted })
    }
}

@Suite("Démarrage, mises à jour, système")
struct ParsingTests {
    @Test("launchctl : désactivés et chargés")
    func launchctl() {
        let disabled = LaunchItems.parseDisabled("""
        disabled services = {
            "com.google.keystone.agent" => disabled
            "com.foo.bar" => enabled
            "com.old.style" => true
        }
        """)
        #expect(disabled == ["com.google.keystone.agent", "com.old.style"])
        let loaded = LaunchItems.parseLoaded("PID\tStatus\tLabel\n123\t0\tcom.a\n-\t0\tcom.b\n")
        #expect(loaded == ["com.a", "com.b"])
        #expect(LaunchItems.isValidLabel("com.teiki.drama-studio"))
        #expect(!LaunchItems.isValidLabel("com.x; rm"))
    }

    @Test("Versions et flux Sparkle")
    func versions() {
        #expect(VersionCompare.isNewer("1.10.2", than: "1.9"))
        #expect(!VersionCompare.isNewer("2.0", than: "2.0.0"))
        #expect(!VersionCompare.isNewer("1.2", than: "1.10"))
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><title>1.1</title><enclosure url="https://x/1.zip" sparkle:version="110" sparkle:shortVersionString="1.1"/></item>
        <item><title>1.2</title><sparkle:version>120</sparkle:version><sparkle:shortVersionString>1.2</sparkle:shortVersionString><enclosure url="https://x/2.zip"/></item>
        </channel></rss>
        """
        let latest = Appcast.latest(Appcast.parse(Data(xml.utf8)))
        #expect(latest?.version == "120")
        #expect(latest?.shortVersion == "1.2")
    }

    @Test("Homebrew : casks en retard")
    func brew() throws {
        let json = #"{"formulae":[],"casks":[{"name":"firefox","installed_versions":["120.0"],"current_version":"121.0"}]}"#
        let updates = try UpdateChecker.parseBrew(Data(json.utf8))
        #expect(updates.first?.caskToken == "firefox")
        #expect(updates.first?.available == "121.0")
    }

    @Test("Instantanés locaux")
    func snapshots() {
        let list = LocalSnapshots.parse("""
        Snapshots for volume group containing disk /:
        com.apple.TimeMachine.2026-11-12-165502.local
        com.apple.os.update-182F06D7
        """)
        #expect(list.count == 2)
        #expect(list[0].isTimeMachine && list[0].date != nil)
        #expect(!list[1].isTimeMachine)
    }

    @Test("Mémoire et processus lisibles")
    func memory() throws {
        let status = try #require(MemoryStatus.current())
        #expect(status.total > 0 && status.used > 0)
        #expect(!ProcessList.topMemory(limit: 5).isEmpty)
        #expect((VolumeSpace.current()?.total ?? 0) > 0)
    }
}

@Suite("Simulateurs indisponibles")
struct UnavailableSimulatorTests {
    @Test("Seuls les simulateurs indisponibles, à l'identifiant valide")
    func parse() throws {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-16-0":[
          {"udid":"2F1D3B4A-1111-2222-3333-444455556666","name":"iPhone 14","isAvailable":false,
           "dataPath":"/tmp/x/data","availabilityError":"runtime profile not found"},
          {"udid":"pas-un-uuid","name":"Bizarre","isAvailable":false},
          {"udid":"2F1D3B4A-1111-2222-3333-444455556667","name":"iPhone 15","isAvailable":true}]}}
        """
        let items = try UnavailableSimulatorSource.parse(Data(json.utf8), measure: { _ in 42 })
        #expect(items.map(\.name) == ["iPhone 14"])
        #expect(items.first?.bytes == 42)
    }
}

@Suite("Retouches après essai réel")
struct RealDataTweaksTests {
    @Test("Pièce jointe de Mail : nom du fichier plutôt que l'identifiant du dossier")
    func readableMailName() throws {
        let home = try FakeHome()
        let folder = home.url("Mail Downloads/32900957-29DE-4F9B-926E-3681CA7106DD")
        try home.file("Mail Downloads/32900957-29DE-4F9B-926E-3681CA7106DD/facture.pdf")
        #expect(Scanner.readableName(folder) == "facture.pdf")
        #expect(Scanner.readableName(home.url("Mail Downloads")) == nil)
    }

    @Test("Outils de développement écartés des restes")
    func toolsAreNotLeftovers() throws {
        let home = try FakeHome()
        try home.dir("Library/Caches/org.swift.swiftpm")
        let rule = Rule(id: "r", name: "r", category: .apps, risk: .review, explanation: "",
                        paths: ["~/Library/Caches/{bundleID}"], check: .appLeftover)
        let found = AppCatalog(home: home.path).leftovers(rules: [rule], knownIDs: [], policy: ProtectionPolicy(home: home.path), isInstalled: { _ in false })
        #expect(found.isEmpty)
    }
}
