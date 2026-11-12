import Foundation

/// Une mise à jour disponible.
public struct AppUpdate: Sendable, Identifiable, Hashable {
    public enum Source: String, Sendable {
        case sparkle
        case homebrew

        public var title: String {
            switch self {
            case .sparkle: "Mise à jour intégrée"
            case .homebrew: "Homebrew"
            }
        }
    }

    public var id: String { "\(source.rawValue):\(name)" }
    public let name: String
    /// Chemin de l'appli, si elle est connue.
    public let appPath: String?
    public let installed: String
    public let available: String
    public let source: Source
    /// Nom du paquet Homebrew (`brew upgrade --cask <nom>`).
    public let caskToken: String?

    public init(name: String, appPath: String?, installed: String, available: String, source: Source, caskToken: String? = nil) {
        self.name = name
        self.appPath = appPath
        self.installed = installed
        self.available = available
        self.source = source
        self.caskToken = caskToken
    }
}

/// Comparaison de numéros de version (« 1.10.2 » > « 1.9 »).
public enum VersionCompare {
    static func parts(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0.prefix(9)) }
    }

    /// Vrai si `candidate` est plus récente que `installed`.
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = parts(candidate), b = parts(installed)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Lecture d'un flux Sparkle (appcast) : la version la plus récente proposée.
public enum Appcast {
    public struct Entry: Sendable, Equatable {
        public let version: String?
        public let shortVersion: String?
        /// Canal (« beta »…) : absent pour les versions publiques.
        public var channel: String? = nil
        public var minimumSystemVersion: String? = nil

        /// Version publique, installable sur ce Mac.
        public var isEligible: Bool {
            guard channel?.isEmpty ?? true else { return false }
            guard let minimum = minimumSystemVersion else { return true }
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return !VersionCompare.isNewer(minimum, than: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        }
    }

    final class Parser: NSObject, XMLParserDelegate {
        var entries: [Entry] = []
        private var inItem = false
        private var version: String?
        private var shortVersion: String?
        private var channel: String?
        private var minimumSystem: String?
        private var element = ""
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            element = qualifiedName ?? name
            text = ""
            if element == "item" { inItem = true; version = nil; shortVersion = nil; channel = nil; minimumSystem = nil }
            if inItem, element == "enclosure" {
                version = attributes["sparkle:version"] ?? version
                shortVersion = attributes["sparkle:shortVersionString"] ?? shortVersion
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let tag = qualifiedName ?? name
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if inItem, tag == "sparkle:version", !value.isEmpty { version = value }
            if inItem, tag == "sparkle:shortVersionString", !value.isEmpty { shortVersion = value }
            if inItem, tag == "sparkle:channel", !value.isEmpty { channel = value }
            if inItem, tag == "sparkle:minimumSystemVersion", !value.isEmpty { minimumSystem = value }
            if tag == "item" {
                inItem = false
                if version != nil || shortVersion != nil {
                    entries.append(Entry(version: version, shortVersion: shortVersion, channel: channel, minimumSystemVersion: minimumSystem))
                }
            }
            text = ""
        }
    }

    public static func parse(_ data: Data) -> [Entry] {
        let parser = XMLParser(data: data)
        let delegate = Parser()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return delegate.entries
    }

    /// Entrée la plus récente (par numéro de build, sinon par version affichée).
    public static func latest(_ entries: [Entry]) -> Entry? {
        entries.filter(\.isEligible).max { a, b in
            VersionCompare.isNewer(b.version ?? b.shortVersion ?? "", than: a.version ?? a.shortVersion ?? "")
        }
    }
}

/// Recherche des mises à jour : flux Sparkle des applis et casks Homebrew. Lecture seule.
public struct UpdateChecker: Sendable {
    public init() {}

    /// Applis dont le flux Sparkle propose une version plus récente.
    public func sparkleUpdates(for apps: [InstalledApp]) async -> [AppUpdate] {
        let candidates = apps.filter { $0.sparkleFeed != nil && !$0.isAppStore }
        return await withTaskGroup(of: AppUpdate?.self) { group in
            var results: [AppUpdate] = []
            var iterator = candidates.makeIterator()
            func addNext() {
                guard let app = iterator.next() else { return }
                group.addTask { await Self.check(app) }
            }
            for _ in 0..<6 { addNext() }
            while let next = await group.next() {
                if let next { results.append(next) }
                addNext()
            }
            return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    static func check(_ app: InstalledApp) async -> AppUpdate? {
        guard let feed = app.sparkleFeed else { return nil }
        var request = URLRequest(url: feed, timeoutInterval: 12)
        request.setValue("Cleanmac", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = Appcast.latest(Appcast.parse(data))
        else { return nil }
        // Comparer de préférence les numéros de build, sinon les versions affichées.
        let newer: Bool
        if let remote = latest.version, let local = app.build {
            newer = VersionCompare.isNewer(remote, than: local)
        } else if let remote = latest.shortVersion, let local = app.version {
            newer = VersionCompare.isNewer(remote, than: local)
        } else {
            newer = false
        }
        guard newer else { return nil }
        return AppUpdate(name: app.displayName, appPath: app.path, installed: app.version ?? app.build ?? "?",
                         available: latest.shortVersion ?? latest.version ?? "?", source: .sparkle)
    }

    /// Emplacement de Homebrew, s'il est installé.
    public static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    struct BrewOutdated: Decodable {
        struct Cask: Decodable {
            let name: String
            let installed_versions: [String]
            let current_version: String
        }
        let casks: [Cask]
    }

    static func parseBrew(_ data: Data) throws -> [AppUpdate] {
        try JSONDecoder().decode(BrewOutdated.self, from: data).casks.map { cask in
            AppUpdate(name: cask.name, appPath: nil, installed: cask.installed_versions.joined(separator: ", "),
                      available: cask.current_version, source: .homebrew, caskToken: cask.name)
        }
    }

    /// Casks Homebrew en retard (`brew outdated --cask --greedy`), sans mise à jour de Homebrew lui-même.
    public func homebrewUpdates() async throws -> [AppUpdate] {
        guard let brew = Self.brewPath else { return [] }
        let data = try await ToolRunner.run(brew, ["outdated", "--cask", "--greedy", "--json=v2"],
                                            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1"],
                                            timeout: 300)
        return try Self.parseBrew(data)
    }
}
