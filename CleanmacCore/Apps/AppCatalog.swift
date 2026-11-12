import Darwin
import Foundation

/// Une appli installée.
public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: String { path }
    /// Chemin du paquet `.app`.
    public let path: String
    /// Nom du paquet, sans « .app » (sert au jeton `{appName}`).
    public let fileName: String
    /// Nom affiché.
    public let displayName: String
    public let bundleID: String
    /// Version affichée (`CFBundleShortVersionString`).
    public let version: String?
    /// Numéro de build (`CFBundleVersion`).
    public let build: String?
    /// Adresse du flux de mises à jour Sparkle, si l'appli en déclare un (https uniquement).
    public let sparkleFeed: URL?
    /// Installée depuis le Mac App Store.
    public let isAppStore: Bool
    /// Appartient à Apple (com.apple.*).
    public var isApple: Bool { bundleID.hasPrefix("com.apple.") }

    public var identity: AppIdentity { AppIdentity(bundleID: bundleID, name: fileName) }

    public init(path: String, fileName: String, displayName: String, bundleID: String, version: String?,
                build: String?, sparkleFeed: URL?, isAppStore: Bool) {
        self.path = path
        self.fileName = fileName
        self.displayName = displayName
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.sparkleFeed = sparkleFeed
        self.isAppStore = isAppStore
    }
}

/// Un fichier rattaché à une appli (ou à une appli supprimée), autorisé par une règle d'applis.
public struct AppFile: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let ruleID: String
    public let allocatedBytes: Int64
    public let isSelectedByDefault: Bool

    public init(path: String, ruleID: String, allocatedBytes: Int64, isSelectedByDefault: Bool) {
        self.path = path
        self.ruleID = ruleID
        self.allocatedBytes = allocatedBytes
        self.isSelectedByDefault = isSelectedByDefault
    }

    /// Nature du fichier, d'après son emplacement.
    public var kind: String {
        if path.hasSuffix(".app") { return "Appli" }
        let library = path.components(separatedBy: "/Library/")
        guard library.count > 1, let folder = library.last?.split(separator: "/").first else { return "Fichier" }
        switch folder {
        case "Preferences": return "Préférences"
        case "Caches": return "Caches"
        case "HTTPStorages", "Cookies", "WebKit": return "Données web"
        case "Saved Application State": return "État des fenêtres"
        case "Logs": return "Journaux"
        case "Application Scripts": return "Scripts"
        case "Application Support": return "Données"
        case "Containers": return "Conteneur"
        case "Group Containers": return "Conteneur partagé"
        case "LaunchAgents": return "Agent de démarrage"
        default: return String(folder)
        }
    }
}

/// Restes d'une appli supprimée.
public struct Leftover: Sendable, Identifiable, Hashable {
    public var id: String { bundleID }
    public let bundleID: String
    public let files: [AppFile]
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.allocatedBytes } }
    public var identity: AppIdentity { AppIdentity(bundleID: bundleID, name: bundleID) }

    public init(bundleID: String, files: [AppFile]) {
        self.bundleID = bundleID
        self.files = files
    }
}

/// Inventaire des applis et de leurs fichiers.
public struct AppCatalog: Sendable {
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = PathPattern.trimmed(home)
    }

    /// Dossiers d'applis qu'on peut désinstaller.
    public var uninstallRoots: [String] { ["/Applications", home + "/Applications"] }

    /// Applis désinstallables : premier niveau de /Applications et ~/Applications.
    public func installedApps() -> [InstalledApp] {
        uninstallRoots.flatMap { root in
            ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
                .filter { $0.hasSuffix(".app") && !$0.hasPrefix(".") }
                .compactMap { Self.readApp(at: root + "/" + $0) }
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Lit l'Info.plist d'un paquet d'appli (sans suivre de lien).
    public static func readApp(at path: String) -> InstalledApp? {
        guard PathPattern.isRealDirectory(path) else { return nil }
        let plistPath = path + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String
        else { return nil }
        let fileName = String((path as NSString).lastPathComponent.dropLast(4))
        let display = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? fileName
        var feed: URL?
        if let raw = info["SUFeedURL"] as? String, let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
           url.scheme?.lowercased() == "https" {
            feed = url
        }
        let receipt = path + "/Contents/_MASReceipt/receipt"
        return InstalledApp(
            path: path, fileName: fileName, displayName: display.isEmpty ? fileName : display,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String,
            build: info["CFBundleVersion"] as? String,
            sparkleFeed: feed,
            isAppStore: FileManager.default.fileExists(atPath: receipt))
    }

    /// Identifiants de toutes les applis connues du Mac (y compris système), pour repérer les restes.
    public func knownBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let roots = uninstallRoots + ["/System/Applications", "/System/Applications/Utilities",
                                      "/Applications/Utilities", "/System/Library/CoreServices",
                                      "/Library/Application Support"]
        for root in roots {
            var stack = [(root, 0)]
            while let (dir, depth) = stack.popLast() {
                for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where !name.hasPrefix(".") {
                    let path = dir + "/" + name
                    if name.hasSuffix(".app") {
                        if let app = Self.readApp(at: path) { ids.insert(app.bundleID) }
                    } else if depth < 2, PathPattern.isRealDirectory(path), !PackageExtensions.isPackage(name) {
                        stack.append((path, depth + 1))
                    }
                }
            }
        }
        return ids
    }

    /// Fichiers d'une appli installée, d'après les règles d'applis (`appFiles`).
    public func files(of app: InstalledApp, rules: [Rule], policy: ProtectionPolicy) -> [AppFile] {
        guard app.identity.problem == nil else { return [] }
        let pattern = PathPattern(home: home)
        var seen = Set<String>()
        var result: [AppFile] = []
        for rule in rules where rule.check == .appFiles {
            for path in pattern.expand(rule: rule, app: app.identity) where !seen.contains(path) {
                seen.insert(path)
                // Une appli du même nom ailleurs (/Applications et ~/Applications) n'est pas celle-ci.
                if path.hasSuffix(".app") && path != app.path { continue }
                guard policy.protection(for: path) == nil else { continue }
                let bytes = (try? SizeCalculator().measure(path).allocatedBytes) ?? 0
                result.append(AppFile(path: path, ruleID: rule.id, allocatedBytes: bytes,
                                      isSelectedByDefault: rule.isSelectedByDefault))
            }
        }
        // L'appli d'abord, puis le plus gros.
        return result.sorted { a, b in
            if a.path == app.path { return true }
            if b.path == app.path { return false }
            return a.allocatedBytes > b.allocatedBytes
        }
    }

    /// Un nom ressemble-t-il à un identifiant d'appli (« com.editeur.appli ») ?
    public static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let tld = parts.first, (2...6).contains(tld.count), tld.allSatisfy({ $0.isLowercase && $0.isLetter }) else { return false }
        return AppIdentity(bundleID: name, name: name).problem == nil
    }

    /// Identifiants d'outils (pas d'applis) qui laissent des fichiers sans être des « restes ».
    static let toolPrefixes = ["org.swift.", "org.python.", "org.llvm.", "org.gnu.", "sh.brew.", "org.homebrew.",
                               "org.nodejs.", "com.github.githubcli", "org.rust-lang.", "org.golang."]

    /// Éditeur d'un identifiant : ses deux premiers éléments (« com.google »).
    static func vendor(_ bundleID: String) -> String {
        bundleID.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Restes d'applis supprimées, d'après la règle `appLeftover`.
    /// Écarte prudemment : Apple, Cleanmac, et tout identifiant dont l'éditeur a encore une appli installée.
    public func leftovers(rules: [Rule], knownIDs: Set<String>, policy: ProtectionPolicy,
                          isInstalled: (String) -> Bool) -> [Leftover] {
        let pattern = PathPattern(home: home)
        let vendors = Set(knownIDs.map(Self.vendor))
        let known = Set(knownIDs.map { $0.lowercased() })
        var candidates = Set<String>()
        for rule in rules where rule.check == .appLeftover {
            for template in rule.paths {
                let absolute = pattern.absolute(template)
                let folder = (absolute as NSString).deletingLastPathComponent
                let last = (absolute as NSString).lastPathComponent
                guard !folder.contains("{"), let range = last.range(of: "{bundleID}") else { continue }
                let prefix = String(last[..<range.lowerBound])
                let suffix = String(last[range.upperBound...])
                for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
                    guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else { continue }
                    let id = String(name.dropFirst(prefix.count).dropLast(suffix.count))
                    guard Self.looksLikeBundleID(id) else { continue }
                    let lower = id.lowercased()
                    if lower.hasPrefix("com.apple.") || lower == Cleaner.ownBundleID { continue }
                    if Self.toolPrefixes.contains(where: { lower.hasPrefix($0) }) { continue }
                    if known.contains(lower) || vendors.contains(Self.vendor(id)) { continue }
                    candidates.insert(id)
                }
            }
        }
        var result: [Leftover] = []
        for id in candidates.sorted() where !isInstalled(id) {
            let identity = AppIdentity(bundleID: id, name: id)
            var files: [AppFile] = []
            for rule in rules where rule.check == .appLeftover {
                for path in pattern.expand(rule: rule, app: identity) where policy.protection(for: path) == nil {
                    let bytes = (try? SizeCalculator().measure(path).allocatedBytes) ?? 0
                    files.append(AppFile(path: path, ruleID: rule.id, allocatedBytes: bytes, isSelectedByDefault: false))
                }
            }
            if !files.isEmpty { result.append(Leftover(bundleID: id, files: files)) }
        }
        return result.sorted { $0.totalBytes > $1.totalBytes }
    }
}
