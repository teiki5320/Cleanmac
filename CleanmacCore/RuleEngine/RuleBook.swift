import Foundation

/// Erreurs de chargement ou de validation des règles.
public enum RuleError: Error, Equatable, LocalizedError {
    case unreadable(file: String, reason: String)
    case duplicateID(String)
    case emptyPaths(ruleID: String)
    case invalidSource(ruleID: String, reason: String)
    case invalidPath(ruleID: String, path: String, reason: String)
    case invalidCheck(ruleID: String, reason: String)
    case noRuleFiles

    public var errorDescription: String? {
        switch self {
        case let .unreadable(file, reason):
            "Fichier de règles illisible (\(file)) : \(reason)"
        case let .duplicateID(id):
            "Identifiant de règle en double : \(id)"
        case let .emptyPaths(id):
            "La règle \(id) ne déclare aucun chemin."
        case let .invalidSource(id, reason):
            "Règle \(id) : \(reason)"
        case let .invalidPath(id, path, reason):
            "Chemin refusé dans la règle \(id) (\(path)) : \(reason)"
        case let .invalidCheck(id, reason):
            "Règle \(id) : \(reason)"
        case .noRuleFiles:
            "Aucun fichier de règles trouvé."
        }
    }
}

/// L'ensemble des règles chargées et validées.
public struct RuleBook: Sendable {
    public let rules: [Rule]

    public init(rules: [Rule]) throws {
        try Self.validate(rules)
        self.rules = rules
    }

    public func rule(id: String) -> Rule? {
        rules.first { $0.id == id }
    }

    public func rules(in category: RuleCategory) -> [Rule] {
        rules.filter { $0.category == category }
    }

    // MARK: Chargement

    /// Charge les règles livrées avec CleanmacCore (`Rules/*.json`).
    public static func bundled() throws -> RuleBook {
        let bundle = Bundle(for: BundleToken.self)
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return try load(files: urls)
    }

    /// Charge tous les `*.json` d'un dossier.
    public static func load(directory: URL) throws -> RuleBook {
        let urls = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try load(files: urls)
    }

    public static func load(files: [URL]) throws -> RuleBook {
        guard !files.isEmpty else { throw RuleError.noRuleFiles }
        var all: [Rule] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let data = try Data(contentsOf: url)
                all += try JSONDecoder().decode(RuleFile.self, from: data).rules
            } catch {
                throw RuleError.unreadable(file: url.lastPathComponent, reason: String(describing: error))
            }
        }
        return try RuleBook(rules: all)
    }

    public static func decode(_ data: Data) throws -> RuleBook {
        let file = try JSONDecoder().decode(RuleFile.self, from: data)
        return try RuleBook(rules: file.rules)
    }

    // MARK: Validation

    static func validate(_ rules: [Rule]) throws {
        var seen = Set<String>()
        for rule in rules {
            guard seen.insert(rule.id).inserted else { throw RuleError.duplicateID(rule.id) }
            if rule.source != nil {
                guard rule.check == nil else {
                    throw RuleError.invalidCheck(ruleID: rule.id, reason: "une règle à source ne peut pas avoir de contrôle")
                }
                guard rule.paths.isEmpty, rule.excludes.isEmpty else {
                    throw RuleError.invalidSource(ruleID: rule.id, reason: "une règle à source ne déclare pas de chemins")
                }
                guard rule.regenerable else {
                    throw RuleError.invalidSource(ruleID: rule.id, reason: "une règle à source doit être régénérable")
                }
                continue
            }
            guard !rule.paths.isEmpty else { throw RuleError.emptyPaths(ruleID: rule.id) }
            for path in rule.paths + rule.excludes {
                if let reason = PathPattern.problem(with: path) {
                    throw RuleError.invalidPath(ruleID: rule.id, path: path, reason: reason)
                }
                if rule.check != nil, path.split(separator: "/").contains(where: { PathPattern.hasGlob(String($0)) }) {
                    throw RuleError.invalidPath(ruleID: rule.id, path: path, reason: "joker interdit dans une règle à contrôle")
                }
            }
            if rule.check != nil {
                guard rule.risk == .review, !rule.regenerable else {
                    throw RuleError.invalidCheck(ruleID: rule.id, reason: "une règle à contrôle est « à vérifier » et non régénérable")
                }
            }
        }
    }
}

final class BundleToken {}
