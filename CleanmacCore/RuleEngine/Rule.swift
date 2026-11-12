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
    case duplicates

    public var title: String {
        switch self {
        case .systemJunk: "Fichiers système inutiles"
        case .developer: "Développeur"
        case .mail: "Mail"
        case .trash: "Corbeilles"
        case .icloud: "iCloud Drive"
        case .apps: "Applications"
        case .duplicates: "Doublons"
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
/// - `source` (facultatif) : les éléments ne sont pas des chemins mais sont listés et supprimés
///   par un outil du système (ex. `simulatorRuntimes` via `xcrun simctl`). `paths` est alors vide.
///   Ces éléments ne peuvent pas aller à la Corbeille : ils exigent donc une règle `regenerable`
///   et la suppression définitive activée par l'utilisateur.
/// - `check` (facultatif) : contrôle supplémentaire fait juste avant chaque suppression.
///   Les `paths` désignent alors des dossiers (sans joker) et la règle couvre les fichiers situés
///   à l'intérieur, à n'importe quelle profondeur. Le scanner ignore ces règles : leurs éléments
///   viennent d'un autre module (ex. `duplicateCopy` pour les doublons). Elles sont toujours
///   « à vérifier », jamais régénérables : leurs éléments vont uniquement à la Corbeille.
public struct Rule: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let category: RuleCategory
    public let risk: RiskLevel
    public let explanation: String
    public let paths: [String]
    public let excludes: [String]
    public let regenerable: Bool
    public let source: RuleSource?
    public let check: RuleCheck?

    public init(
        id: String,
        name: String,
        category: RuleCategory,
        risk: RiskLevel,
        explanation: String,
        paths: [String],
        excludes: [String] = [],
        regenerable: Bool = false,
        source: RuleSource? = nil,
        check: RuleCheck? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.risk = risk
        self.explanation = explanation
        self.paths = paths
        self.excludes = excludes
        self.regenerable = regenerable
        self.source = source
        self.check = check
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, risk, explanation, paths, excludes, regenerable, source, check
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
        source = try c.decodeIfPresent(RuleSource.self, forKey: .source)
        check = try c.decodeIfPresent(RuleCheck.self, forKey: .check)
    }

    /// Un élément est coché par défaut seulement si la règle est « sûre ».
    public var isSelectedByDefault: Bool { risk == .safe }
}

/// Outils du système qui listent et suppriment eux-mêmes certains éléments.
public enum RuleSource: String, Codable, Sendable, CaseIterable {
    /// Systèmes des simulateurs, gérés par `xcrun simctl runtime`.
    case simulatorRuntimes
}

/// Contrôles supplémentaires faits par le nettoyeur juste avant de supprimer.
public enum RuleCheck: String, Codable, Sendable, CaseIterable {
    /// Copie d'un fichier gardé ailleurs : la demande nomme l'exemplaire gardé, qui doit
    /// exister, ne pas être supprimé dans le même nettoyage et avoir exactement le même contenu
    /// (comparaison octet par octet au moment du nettoyage).
    case duplicateCopy
}

/// Contenu d'un fichier `Rules/*.json`.
public struct RuleFile: Codable, Sendable {
    public let version: Int
    public let rules: [Rule]
}
