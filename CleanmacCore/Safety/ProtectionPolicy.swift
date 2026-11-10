import Darwin
import Foundation

/// Pourquoi un chemin est protégé (jamais supprimé).
public enum ProtectionReason: Sendable, Equatable, CustomStringConvertible {
    /// Le chemin est (ou est dans) un emplacement protégé d'office.
    case protectedLocation(String)
    /// Le chemin contient un emplacement protégé (le supprimer l'emporterait).
    case containsProtectedLocation(String)
    /// Exclusion ajoutée par l'utilisateur.
    case userExclusion(String)
    /// Dossier de code suivi par git (lui-même, un parent ou un sous-dossier contient `.git`).
    case gitRepository(String)
    /// Photothèque.
    case photoLibrary
    /// Chemin incohérent (relatif, « .. », trop proche de la racine…).
    case unsafePath(String)

    public var description: String {
        switch self {
        case let .protectedLocation(p): "Emplacement protégé : \(p)"
        case let .containsProtectedLocation(p): "Contient un emplacement protégé : \(p)"
        case let .userExclusion(p): "Exclu par vous : \(p)"
        case let .gitRepository(p): "Dossier de code (git) : \(p)"
        case .photoLibrary: "Photothèque"
        case let .unsafePath(why): "Chemin refusé : \(why)"
        }
    }
}

/// Règles de protection appliquées avant tout scan et tout nettoyage.
public struct ProtectionPolicy: Sendable {
    public let home: String
    /// Emplacements protégés d'office (absolus).
    public let protectedLocations: [String]
    /// Exclusions de l'utilisateur (absolues).
    public let userExclusions: [String]

    /// Emplacements protégés d'office, relatifs au dossier personnel.
    public static let protectedInHome = [
        "Pictures",
        "Documents",
        "Desktop",
        "Library/Messages",
        "Library/Keychains",
        "Library/Mobile Documents",   // iCloud Drive : supprimer ici supprime dans iCloud
        "Library/Photos",
    ]

    /// Emplacements système protégés d'office.
    public static let protectedSystem = [
        "/System",
        "/bin",
        "/sbin",
        "/usr",
        "/private/etc",
        "/Library/Keychains",
    ]

    public init(home: String = NSHomeDirectory(), userExclusions: [String] = []) {
        let home = PathPattern.trimmed(home)
        self.home = home
        self.protectedLocations = Self.protectedInHome.map { home + "/" + $0 } + Self.protectedSystem
        self.userExclusions = userExclusions.map { Self.expandTilde($0, home: home) }
    }

    static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + "/" + path.dropFirst(2) }
        return PathPattern.trimmed(path)
    }

    /// `child` est-il égal à `parent` ou à l'intérieur ?
    static func isSameOrInside(_ child: String, _ parent: String) -> Bool {
        child == parent || child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }

    /// Vérification rapide (sans parcourir le contenu du dossier).
    /// Renvoie la raison de protection, ou `nil` si le chemin peut être proposé.
    public func protection(for path: String) -> ProtectionReason? {
        if let why = Self.pathProblem(path, home: home) { return .unsafePath(why) }

        for location in protectedLocations {
            if Self.isSameOrInside(path, location) { return .protectedLocation(location) }
            if Self.isSameOrInside(location, path) { return .containsProtectedLocation(location) }
        }
        for exclusion in userExclusions {
            if Self.isSameOrInside(path, exclusion) || Self.isSameOrInside(exclusion, path) {
                return .userExclusion(exclusion)
            }
        }
        if path.split(separator: "/").contains(where: { $0.lowercased().hasSuffix(".photoslibrary") }) {
            return .photoLibrary
        }
        if let repo = Self.enclosingGitRepository(of: path) { return .gitRepository(repo) }
        return nil
    }

    /// Vérification complète : ajoute la recherche d'un `.git` à l'intérieur du dossier.
    public func fullProtection(for path: String) -> ProtectionReason? {
        if let reason = protection(for: path) { return reason }
        if let git = Self.firstGitDirectory(inside: path) { return .gitRepository(git) }
        return nil
    }

    /// Contrôles de cohérence d'un chemin candidat.
    static func pathProblem(_ path: String, home: String) -> String? {
        guard path.hasPrefix("/") else { return "chemin relatif" }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        if components.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) {
            return "chemin non normalisé"
        }
        if components.count < 2 { return "trop proche de la racine" }
        if isSameOrInside(home, path) { return "dossier personnel ou parent" }
        return nil
    }

    /// Le chemin ou l'un de ses parents est-il un dépôt git ?
    static func enclosingGitRepository(of path: String) -> String? {
        var current = path
        while current != "/" && !current.isEmpty {
            if PathPattern.exists(current + "/.git") { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Cherche un dossier `.git` à l'intérieur (sans suivre les liens).
    static func firstGitDirectory(inside path: String) -> String? {
        guard PathPattern.isRealDirectory(path) else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in true }
        ) else { return nil }
        for case let child as URL in enumerator where child.lastPathComponent == ".git" {
            return child.deletingLastPathComponent().path
        }
        return nil
    }
}
