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
///   Les contrôles `appFiles` et `appLeftover` (fichiers d'une appli, restes d'une appli supprimée)
///   utilisent des chemins à jetons : `{bundleID}` et `{appName}` sont remplacés, au moment de la
///   vérification, par l'identité de l'appli nommée dans la demande (validée). Jokers autorisés.
/// - `inTrash` (facultatif) : les éléments sont déjà dans une Corbeille (`~/.Trash/*`,
///   `/Volumes/*/.Trashes/{uid}/*`). Vider une Corbeille est forcément définitif : ces éléments
///   sont supprimés définitivement, sans dépendre du réglage, après l'écran de vérification.
///   Le nettoyeur revérifie que chaque élément est bien directement dans une vraie Corbeille.
/// - Jeton `{uid}` : remplacé par l'identifiant numérique de l'utilisateur, dans toute règle.
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
    public let inTrash: Bool

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
        check: RuleCheck? = nil,
        inTrash: Bool = false
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
        self.inTrash = inTrash
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, risk, explanation, paths, excludes, regenerable, source, check, inTrash
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
        inTrash = try c.decodeIfPresent(Bool.self, forKey: .inTrash) ?? false
    }

    /// Règle à chemins à jetons (`{bundleID}`, `{appName}`), propres à une appli.
    public var isAppTemplate: Bool { check == .appFiles || check == .appLeftover }

    /// Un élément est coché par défaut seulement si la règle est « sûre ».
    public var isSelectedByDefault: Bool { risk == .safe }
}

/// Outils du système qui listent et suppriment eux-mêmes certains éléments.
public enum RuleSource: String, Codable, Sendable, CaseIterable {
    /// Systèmes des simulateurs, gérés par `xcrun simctl runtime`.
    case simulatorRuntimes
    /// Simulateurs indisponibles, supprimés par `xcrun simctl delete`.
    case unavailableSimulators
}

/// Contrôles supplémentaires faits par le nettoyeur juste avant de supprimer.
public enum RuleCheck: String, Codable, Sendable, CaseIterable {
    /// Copie d'un fichier gardé ailleurs : la demande nomme l'exemplaire gardé, qui doit
    /// exister, ne pas être supprimé dans le même nettoyage et avoir exactement le même contenu
    /// (comparaison octet par octet au moment du nettoyage).
    case duplicateCopy
    /// Fichiers d'une appli installée (paquet, préférences, caches…) : la demande nomme l'appli,
    /// qui ne doit pas être ouverte au moment de la suppression.
    case appFiles
    /// Restes d'une appli supprimée : la demande nomme l'identifiant, et aucune appli installée
    /// ne doit le porter au moment de la suppression.
    case appLeftover
}

/// Identité d'une appli, utilisée pour remplacer les jetons des règles à chemins à jetons.
public struct AppIdentity: Sendable, Hashable, Codable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Raison pour laquelle l'identité est refusée, ou `nil` si elle peut servir dans un chemin.
    public var problem: String? {
        let idChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        if bundleID.isEmpty || bundleID.count > 200 { return "identifiant vide ou trop long" }
        if bundleID.unicodeScalars.contains(where: { !idChars.contains($0) }) { return "identifiant invalide" }
        if !bundleID.contains(".") || bundleID.hasPrefix(".") || bundleID.hasSuffix(".") || bundleID.contains("..") {
            return "identifiant invalide"
        }
        if name.isEmpty || name.count > 200 { return "nom vide ou trop long" }
        if name.hasPrefix(".") || name.contains("/") || name.contains(":") { return "nom invalide" }
        if name.contains(where: { $0 == "*" || $0 == "?" || $0 == "[" || $0 == "]" || $0 == "{" || $0 == "}" || $0 == "\\" || $0.isNewline }) {
            return "nom invalide"
        }
        return nil
    }
}

/// Contenu d'un fichier `Rules/*.json`.
public struct RuleFile: Codable, Sendable {
    public let version: Int
    public let rules: [Rule]
}
