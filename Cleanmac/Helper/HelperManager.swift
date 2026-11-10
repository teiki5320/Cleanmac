import Foundation
import Observation
import ServiceManagement
import Synchronization

/// Installation et pilotage de l'outil d'aide privilégié (démon `SMAppService`).
@MainActor
@Observable
final class HelperManager {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var installedVersion: String?
    private(set) var message: String?
    private(set) var isBusy = false

    private let service = SMAppService.daemon(plistName: HelperConstants.launchdPlistName)

    init() { refresh() }

    var statusLabel: String {
        switch status {
        case .notRegistered: "Non installé"
        case .enabled: "Installé et autorisé"
        case .requiresApproval: "En attente de votre autorisation"
        case .notFound: "Introuvable dans l'appli"
        @unknown default: "État inconnu"
        }
    }

    func refresh() {
        status = service.status
    }

    func install() {
        do {
            try service.register()
            message = "Outil d'aide installé."
        } catch {
            refresh()
            message = status == .requiresApproval
                ? "Autorisez « Cleanmac » dans Réglages système › Général › Ouverture et extensions."
                : "Installation impossible : \(error.localizedDescription)"
        }
        refresh()
    }

    func uninstall() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.unregister()
            installedVersion = nil
            message = "Outil d'aide désinstallé."
        } catch {
            message = "Désinstallation impossible : \(error.localizedDescription)"
        }
        refresh()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Vérifie la connexion XPC en demandant sa version à l'outil d'aide.
    func ping() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let version = try await HelperClient.version()
            installedVersion = version
            message = "L'outil d'aide répond (version \(version))."
        } catch {
            installedVersion = nil
            message = "Pas de réponse de l'outil d'aide : \(error.localizedDescription)"
        }
    }
}

enum HelperClientError: LocalizedError {
    case noProxy

    var errorDescription: String? { "connexion impossible" }
}

/// Client XPC de l'outil d'aide.
enum HelperClient {
    static func version() async throws -> String {
        try await call { proxy, resume in proxy.version { resume(.success($0)) } }
    }

    static func run(_ command: HelperCommand) async throws -> (Bool, String) {
        try await call { proxy, resume in
            proxy.run(command: command.rawValue) { ok, message in resume(.success((ok, message))) }
        }
    }

    private static func call<T: Sendable>(
        _ body: @escaping (CleanmacHelperProtocol, @escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: CleanmacHelperProtocol.self)
        // On ne parle qu'à notre outil d'aide, signé par notre équipe.
        connection.setCodeSigningRequirement(HelperConstants.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(.failure(error))
            }
            guard let helper = proxy as? CleanmacHelperProtocol else {
                once.resume(.failure(HelperClientError.noProxy))
                return
            }
            body(helper) { once.resume($0) }
        }
    }
}

/// Garantit qu'une continuation n'est reprise qu'une fois (réponse ou erreur XPC).
private final class ResumeOnce<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T, Error>?>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ result: Result<T, Error>) {
        let pending = continuation.withLock { value -> CheckedContinuation<T, Error>? in
            defer { value = nil }
            return value
        }
        pending?.resume(with: result)
    }
}
