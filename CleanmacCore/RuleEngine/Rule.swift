import Foundation

/// Niveau de risque d'une règle.
/// Seuls les éléments « sûrs » sont cochés par défaut.
public enum RiskLevel: String, Codable, Sendable, CaseIterable {
    case safe
    case review

    public var label: String {
        switch self {
        case .safe: "Sûr"
        case .review: "À vérifier"
        }
    }
}

/// Catégorie (module) à laquelle appartient une règle.
public enum RuleCategory: String, Codable, Sendable, CaseIterable {
    case systemJunk
    case developer
    case mail
    case trash
    case icloud
    case apps

    public var title: String {
        switch self {
        case .systemJunk: "Fichiers système inutiles"
        case .developer: "Développeur"
        case .mail: "Mail"
        case .trash: "Corbeilles"
        case .icloud: "iCloud Drive"
        case .apps: "Applications"
        }
    }
}

/// Une règle de nettoyage, déclarée dans `Rules/*.json`.
/// Rien n'est supprimé hors règle.
///
/// Format JSON d'un fichier de règles :
/// ```json
/// { "version": 1,
///   "rules": [ { "id": "systeme.caches", "name": "…", "category": "systemJunk",
///                "risk": "safe", "regenerable": true, "explanation": "…",
///                "paths": ["~/Library/Caches/*"], "excludes": ["~/Library/Caches/CloudKit"] } ] }
/// ```
/// - `paths` : motifs absolus (`/…`) ou relatifs au dossier personnel (`~/…`).
///   Jokers autorisés dans les composants : `*`, `?`, `[…]`.
/// - `regenerable` : caches recréés automatiquement. Seuls ces éléments peuvent être
///   supprimés définitivement, et seulement si l'utilisateur l'a activé.
public struct Rule: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let category: RuleCategory
    public let risk: RiskLevel
    public let explanation: String
    public let paths: [String]
    public let excludes: [String]
    public let regenerable: Bool

    public init(
        id: String,
        name: String,
        category: RuleCategory,
        risk: RiskLevel,
        explanation: String,
        paths: [String],
        excludes: [String] = [],
        regenerable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.risk = risk
        self.explanation = explanation
        self.paths = paths
        self.excludes = excludes
        self.regenerable = regenerable
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, risk, explanation, paths, excludes, regenerable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(RuleCategory.self, forKey: .category)
        risk = try c.decode(RiskLevel.self, forKey: .risk)
        explanation = try c.decode(String.self, forKey: .explanation)
        paths = try c.decode([String].self, forKey: .paths)
        excludes = try c.decodeIfPresent([String].self, forKey: .excludes) ?? []
        regenerable = try c.decodeIfPresent(Bool.self, forKey: .regenerable) ?? false
    }

    /// Un élément est coché par défaut seulement si la règle est « sûre ».
    public var isSelectedByDefault: Bool { risk == .safe }
}

/// Contenu d'un fichier `Rules/*.json`.
public struct RuleFile: Codable, Sendable {
    public let version: Int
    public let rules: [Rule]
}
