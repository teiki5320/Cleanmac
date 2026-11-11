import Foundation

/// Un élément listé par un outil du système (pas un chemin du disque).
public struct ExternalItem: Sendable, Equatable {
    /// Identifiant propre à l'outil (ex. identifiant du système de simulateur).
    public let id: String
    public let name: String
    public let detail: String?
    public let bytes: Int64

    public init(id: String, name: String, detail: String? = nil, bytes: Int64) {
        self.id = id
        self.name = name
        self.detail = detail
        self.bytes = bytes
    }
}

/// Outil du système qui liste et supprime lui-même ses éléments.
public protocol ExternalSource: Sendable {
    /// Éléments supprimables.
    func list() async throws -> [ExternalItem]
    /// Supprime un élément (définitif : ces éléments ne vont pas à la Corbeille).
    func delete(id: String) async throws
}

/// Préfixe des identifiants d'éléments externes dans les résultats de scan.
public enum ExternalReference {
    public static func make(source: RuleSource, id: String) -> String {
        "\(source.rawValue):\(id)"
    }

    public static func parse(_ reference: String, source: RuleSource) -> String? {
        let prefix = source.rawValue + ":"
        guard reference.hasPrefix(prefix) else { return nil }
        let id = String(reference.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}

/// Les sources réelles du système.
public enum ExternalSources {
    public static var system: [RuleSource: any ExternalSource] {
        [.simulatorRuntimes: SimulatorRuntimeSource()]
    }
}

public enum ExternalSourceError: Error, LocalizedError {
    case toolFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .toolFailed(message): message
        }
    }
}

/// Exécute un outil en ligne de commande (chemin absolu, arguments fixes, sans shell).
enum ToolRunner {
    static func run(_ executable: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let message = String(decoding: errorData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ExternalSourceError.toolFailed(
                        "\((executable as NSString).lastPathComponent) a échoué : \(message)"))
                }
            }
        }
    }
}
