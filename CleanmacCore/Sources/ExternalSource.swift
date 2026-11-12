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
        [.simulatorRuntimes: SimulatorRuntimeSource(), .unavailableSimulators: UnavailableSimulatorSource()]
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
/// Annulable (le processus est arrêté) et borné dans le temps.
enum ToolRunner {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:],
                    timeout: TimeInterval = 180) async throws -> Data {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    if !environment.isEmpty {
                        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                    }
                    let output = Pipe()
                    let errors = Pipe()
                    process.standardOutput = output
                    process.standardError = errors
                    guard box.attach(process) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    let watchdog = DispatchWorkItem { box.timeOut() }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
                    // Les deux sorties sont lues en même temps : un outil bavard sur l'une ne bloque pas l'autre.
                    let errorBox = DataBox()
                    let reading = DispatchGroup()
                    reading.enter()
                    DispatchQueue.global(qos: .utility).async {
                        errorBox.data = errors.fileHandleForReading.readDataToEndOfFile()
                        reading.leave()
                    }
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    reading.wait()
                    process.waitUntilExit()
                    watchdog.cancel()
                    let name = (executable as NSString).lastPathComponent
                    if box.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if box.didTimeOut {
                        continuation.resume(throwing: ExternalSourceError.toolFailed("\(name) n'a pas répondu à temps"))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: data)
                    } else {
                        let message = String(decoding: errorBox.data, as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: ExternalSourceError.toolFailed("\(name) a échoué : \(message)"))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Processus partagé entre la tâche, son annulation et le chien de garde.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    var didTimeOut: Bool { lock.withLock { timedOut } }

    /// Faux si la tâche a déjà été annulée (le processus ne doit pas démarrer).
    func attach(_ process: Process) -> Bool {
        lock.withLock {
            self.process = process
            return !cancelled
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process?.isRunning == true { process?.terminate() }
        }
    }

    func timeOut() {
        lock.withLock {
            guard process?.isRunning == true else { return }
            timedOut = true
            process?.terminate()
        }
    }
}

/// Tampon partagé entre deux files de lecture (écrit une fois, lu après `wait`).
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
