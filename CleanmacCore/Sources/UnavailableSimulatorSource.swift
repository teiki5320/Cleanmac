import Foundation

/// Simulateurs « indisponibles » (leur système n'est plus installé), supprimés par `xcrun simctl delete`.
public struct UnavailableSimulatorSource: ExternalSource {
    public init() {}

    struct Listing: Decodable {
        struct Device: Decodable {
            let udid: String
            let name: String
            let isAvailable: Bool?
            let dataPath: String?
            let availabilityError: String?
        }
        let devices: [String: [Device]]
    }

    public func list() async throws -> [ExternalItem] {
        let data = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"])
        return try Self.parse(data)
    }

    public func delete(id: String) async throws {
        guard UUID(uuidString: id) != nil else {
            throw ExternalSourceError.toolFailed("Identifiant de simulateur invalide : \(id)")
        }
        _ = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "delete", id])
    }

    static func parse(_ data: Data, measure: (String) -> Int64 = Self.size) throws -> [ExternalItem] {
        try JSONDecoder().decode(Listing.self, from: data).devices.values.flatMap { $0 }
            .filter { $0.isAvailable == false && UUID(uuidString: $0.udid) != nil }
            .sorted { $0.name < $1.name }
            .map { device in
                let folder = device.dataPath.map { ($0 as NSString).deletingLastPathComponent }
                return ExternalItem(id: device.udid, name: device.name,
                                    detail: device.availabilityError ?? "Système du simulateur absent",
                                    bytes: folder.map(measure) ?? 0)
            }
    }

    static func size(_ path: String) -> Int64 {
        (try? SizeCalculator().measure(path).allocatedBytes) ?? 0
    }
}
