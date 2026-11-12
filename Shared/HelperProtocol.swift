import Foundation

// Fichier partagé entre l'appli et l'outil d'aide privilégié.

/// Constantes de l'outil d'aide.
enum HelperConstants {
    static let machServiceName = "com.teiki.cleanmac.helper"
    static let launchdPlistName = "com.teiki.cleanmac.helper.plist"
    static let appIdentifier = "com.teiki.cleanmac"
    static let teamIdentifier = "K597U7X3FZ"
    /// Incrémenter à chaque changement du protocole ou des commandes.
    static let helperVersion = "2"

    /// Exigence de signature imposée à l'appli qui se connecte à l'outil d'aide.
    static let clientRequirement =
        "identifier \"\(appIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""

    /// Exigence de signature imposée à l'outil d'aide par l'appli.
    static let helperRequirement =
        "identifier \"\(machServiceName)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
}

/// Liste fermée des commandes que l'outil d'aide accepte d'exécuter en administrateur.
/// Chaque commande correspond à des programmes et arguments fixes, sans shell
/// et sans aucun paramètre venant de l'appli.
enum HelperCommand: String, CaseIterable, Sendable {
    case flushDNSCache
    case reindexSpotlight
    case purgeMemory
    case thinLocalSnapshots

    var label: String {
        switch self {
        case .flushDNSCache: "Vider le cache DNS"
        case .reindexSpotlight: "Réindexer Spotlight"
        case .purgeMemory: "Libérer la mémoire vive"
        case .thinLocalSnapshots: "Purger les instantanés Time Machine locaux"
        }
    }

    /// Programmes exécutés, dans l'ordre (chemin absolu + arguments).
    var steps: [(executable: String, arguments: [String])] {
        switch self {
        case .flushDNSCache:
            [("/usr/bin/dscacheutil", ["-flushcache"]),
             ("/usr/bin/killall", ["-HUP", "mDNSResponder"])]
        case .reindexSpotlight:
            [("/usr/bin/mdutil", ["-E", "/"])]
        case .purgeMemory:
            [("/usr/sbin/purge", [])]
        case .thinLocalSnapshots:
            [("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"])]
        }
    }
}

/// Protocole XPC de l'outil d'aide.
@objc(CleanmacHelperProtocol)
protocol CleanmacHelperProtocol {
    /// Version de l'outil d'aide installé.
    func version(reply: @escaping @Sendable (String) -> Void)

    /// Exécute une commande de la liste fermée (`HelperCommand.rawValue`).
    /// Toute autre valeur est refusée.
    func run(command: String, reply: @escaping @Sendable (Bool, String) -> Void)
}
