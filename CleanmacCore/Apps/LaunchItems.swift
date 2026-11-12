import Foundation

/// Un élément lancé automatiquement par launchd (agent ou démon).
public struct LaunchItem: Sendable, Identifiable, Hashable {
    public enum Scope: String, Sendable, CaseIterable {
        /// `~/Library/LaunchAgents` : modifiable par l'utilisateur.
        case userAgent
        /// `/Library/LaunchAgents` : pour tous les utilisateurs.
        case globalAgent
        /// `/Library/LaunchDaemons` : en administrateur, au démarrage.
        case globalDaemon

        public var title: String {
            switch self {
            case .userAgent: "Vos agents"
            case .globalAgent: "Agents de tous les utilisateurs"
            case .globalDaemon: "Services du système (démons)"
            }
        }
    }

    public var id: String { plistPath }
    public let label: String
    public let plistPath: String
    /// Programme lancé (premier argument), pour l'affichage.
    public let program: String?
    public let scope: Scope
    /// Désactivé dans launchd (persistant).
    public let isDisabled: Bool
    /// Chargé en ce moment (agents de l'utilisateur seulement).
    public let isLoaded: Bool
    /// Lancé à l'ouverture de session.
    public let runAtLoad: Bool

    /// Seuls vos agents peuvent être activés ou désactivés depuis Cleanmac.
    public var isEditable: Bool { scope == .userAgent }

    public init(label: String, plistPath: String, program: String?, scope: Scope, isDisabled: Bool, isLoaded: Bool, runAtLoad: Bool) {
        self.label = label
        self.plistPath = plistPath
        self.program = program
        self.scope = scope
        self.isDisabled = isDisabled
        self.isLoaded = isLoaded
        self.runAtLoad = runAtLoad
    }
}

public enum LaunchItemError: Error, LocalizedError, Equatable {
    case notEditable
    case invalidLabel
    case plistChanged
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notEditable: "Cet élément appartient au système : il ne se modifie pas depuis Cleanmac."
        case .invalidLabel: "Identifiant d'élément invalide."
        case .plistChanged: "Le fichier de l'élément a changé : actualisez la liste."
        case let .failed(message): message
        }
    }
}

/// Lecture et activation des éléments de démarrage launchd.
public struct LaunchItems: Sendable {
    public let home: String
    public let uid: UInt32

    public init(home: String = NSHomeDirectory(), uid: UInt32 = getuid()) {
        self.home = PathPattern.trimmed(home)
        self.uid = uid
    }

    public var userAgentsFolder: String { home + "/Library/LaunchAgents" }

    func folder(_ scope: LaunchItem.Scope) -> String {
        switch scope {
        case .userAgent: userAgentsFolder
        case .globalAgent: "/Library/LaunchAgents"
        case .globalDaemon: "/Library/LaunchDaemons"
        }
    }

    static func isValidLabel(_ label: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return !label.isEmpty && label.count <= 200 && !label.hasPrefix("-")
            && label.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Lit le libellé, le programme et RunAtLoad d'un fichier plist launchd.
    static func readPlist(_ path: String) -> (label: String, program: String?, runAtLoad: Bool)? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String
        else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let runAtLoad = (plist["RunAtLoad"] as? Bool) ?? false || plist["KeepAlive"] != nil
        return (label, program, runAtLoad)
    }

    /// Analyse la sortie de `launchctl print-disabled` : libellés désactivés.
    static func parseDisabled(_ text: String) -> Set<String> {
        var result = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if value == "disabled" || value == "true" { result.insert(label) }
        }
        return result
    }

    /// Analyse la sortie de `launchctl list` : libellés chargés.
    static func parseLoaded(_ text: String) -> Set<String> {
        Set(text.split(separator: "\n").dropFirst().compactMap { line in
            line.split(separator: "\t").last.map(String.init)
        })
    }

    public func list() async -> [LaunchItem] {
        let userDisabled = (try? await ToolRunner.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"]))
            .map { Self.parseDisabled(String(decoding: $0, as: UTF8.self)) } ?? []
        let systemDisabled = (try? await ToolRunner.run("/bin/launchctl", ["print-disabled", "system"]))
            .map { Self.parseDisabled(String(decoding: $0, as: UTF8.self)) } ?? []
        let loaded = (try? await ToolRunner.run("/bin/launchctl", ["list"]))
            .map { Self.parseLoaded(String(decoding: $0, as: UTF8.self)) } ?? []
        var result: [LaunchItem] = []
        for scope in LaunchItem.Scope.allCases {
            let dir = folder(scope)
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted() where name.hasSuffix(".plist") {
                let path = dir + "/" + name
                guard let info = Self.readPlist(path) else { continue }
                let disabled = scope == .globalDaemon ? systemDisabled.contains(info.label) : userDisabled.contains(info.label)
                result.append(LaunchItem(
                    label: info.label, plistPath: path, program: info.program, scope: scope,
                    isDisabled: disabled, isLoaded: scope != .globalDaemon && loaded.contains(info.label),
                    runAtLoad: info.runAtLoad))
            }
        }
        return result
    }

    /// Active ou désactive un de vos agents (réversible : `launchctl enable/disable` + chargement).
    public func setEnabled(_ enabled: Bool, _ item: LaunchItem) async throws {
        guard item.scope == .userAgent,
              (item.plistPath as NSString).deletingLastPathComponent == userAgentsFolder,
              PathPattern.exists(item.plistPath), !PathPattern.isRealDirectory(item.plistPath)
        else { throw LaunchItemError.notEditable }
        guard Self.isValidLabel(item.label) else { throw LaunchItemError.invalidLabel }
        guard Self.readPlist(item.plistPath)?.label == item.label else { throw LaunchItemError.plistChanged }
        let target = "gui/\(uid)/\(item.label)"
        do {
            if enabled {
                _ = try await ToolRunner.run("/bin/launchctl", ["enable", target])
                // Déjà chargé : launchctl renvoie une erreur sans gravité.
                _ = try? await ToolRunner.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", item.plistPath])
            } else {
                _ = try await ToolRunner.run("/bin/launchctl", ["disable", target])
                _ = try? await ToolRunner.run("/bin/launchctl", ["bootout", target])
            }
        } catch {
            throw LaunchItemError.failed(error.localizedDescription)
        }
    }
}
