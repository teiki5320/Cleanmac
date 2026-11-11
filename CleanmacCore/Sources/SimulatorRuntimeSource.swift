import Foundation

/// Systèmes des simulateurs (iOS, watchOS…), listés et supprimés par `xcrun simctl runtime`.
public struct SimulatorRuntimeSource: ExternalSource {
    public init() {}

    struct Entry: Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let platformIdentifier: String?
        let deletable: Bool?
        let sizeBytes: Int64?
        let lastUsedAt: String?
    }

    public func list() async throws -> [ExternalItem] {
        let data = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        return try Self.parse(data)
    }

    public func delete(id: String) async throws {
        // L'identifiant vient de la liste de simctl : on vérifie sa forme avant de le passer.
        guard UUID(uuidString: id) != nil else {
            throw ExternalSourceError.toolFailed("Identifiant de simulateur invalide : \(id)")
        }
        _ = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "runtime", "delete", id])
    }

    static func parse(_ data: Data) throws -> [ExternalItem] {
        let entries = try JSONDecoder().decode([String: Entry].self, from: data).values
        return entries
            .filter { $0.deletable == true }
            .sorted { ($0.version ?? "", $0.build ?? "") < ($1.version ?? "", $1.build ?? "") }
            .map { entry in
                let platform = platformName(entry.platformIdentifier)
                let build = entry.build ?? "?"
                let beta = build.last?.isLetter == true ? " bêta" : ""
                var detail: String?
                if let used = entry.lastUsedAt, let date = ISO8601DateFormatter().date(from: used) {
                    detail = "Dernière utilisation : " + date.formatted(date: .abbreviated, time: .omitted)
                }
                return ExternalItem(
                    id: entry.identifier,
                    name: "\(platform) \(entry.version ?? "?") (\(build)\(beta))",
                    detail: detail,
                    bytes: entry.sizeBytes ?? 0)
            }
    }

    static func platformName(_ identifier: String?) -> String {
        switch identifier {
        case "com.apple.platform.iphonesimulator": "iOS"
        case "com.apple.platform.watchsimulator": "watchOS"
        case "com.apple.platform.appletvsimulator": "tvOS"
        case "com.apple.platform.xrsimulator": "visionOS"
        default: "Simulateur"
        }
    }
}
