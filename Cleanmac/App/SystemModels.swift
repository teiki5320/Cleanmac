import AppKit
import CleanmacCore
import Foundation
import Observation

/// État du module « Espace purgeable » : instantanés locaux et espace que macOS peut libérer.
@MainActor
@Observable
final class PurgeableModel {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var space: VolumeSpace?
    private(set) var snapshots: [LocalSnapshots.Snapshot] = []
    private(set) var purging = false
    private(set) var message: String?
    let helper: HelperManager

    init(helper: HelperManager) { self.helper = helper }

    var isLoading: Bool { phase == .loading }
    var hasLoaded: Bool { phase == .loaded }
    var timeMachineCount: Int { snapshots.filter(\.isTimeMachine).count }

    func start() {
        guard !isLoading else { return }
        phase = .loading
        Task {
            space = VolumeSpace.current()
            do {
                snapshots = try await LocalSnapshots().list()
                phase = .loaded
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Purge les instantanés Time Machine locaux (via l'outil d'aide, en administrateur).
    func purge() {
        guard !purging else { return }
        purging = true
        message = nil
        Task {
            defer { purging = false }
            helper.refresh()
            guard helper.status == .enabled else {
                message = "Il faut l'outil d'aide pour purger les instantanés : installez-le dans Réglages › Accès et outil d'aide."
                return
            }
            do {
                let (ok, text) = try await HelperClient.run(.thinLocalSnapshots)
                message = ok ? "Instantanés purgés. " + text : text
            } catch {
                message = "L'outil d'aide n'a pas répondu : \(error.localizedDescription)"
            }
            space = VolumeSpace.current()
            snapshots = (try? await LocalSnapshots().list()) ?? snapshots
        }
    }
}

/// Une tâche de maintenance.
enum MaintenanceTask: String, CaseIterable, Identifiable {
    case flushDNS, launchServices, purgeMemory, reindexSpotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flushDNS: "Vider le cache DNS"
        case .launchServices: "Reconstruire les services de lancement"
        case .purgeMemory: "Libérer la mémoire vive"
        case .reindexSpotlight: "Réindexer Spotlight"
        }
    }

    var detail: String {
        switch self {
        case .flushDNS: "Quand un site ne s'ouvre plus ou pointe vers une ancienne adresse."
        case .launchServices: "Quand « Ouvrir avec » montre des doublons ou des applis disparues, ou que les icônes sont fausses."
        case .purgeMemory: "Vide les fichiers en cache de la mémoire. macOS gère très bien seul : utile surtout avant une grosse tâche."
        case .reindexSpotlight: "Quand Spotlight ne trouve plus vos fichiers. Le Mac travaille ensuite un long moment (jusqu'à une heure)."
        }
    }

    var symbol: String {
        switch self {
        case .flushDNS: "network"
        case .launchServices: "arrow.triangle.2.circlepath"
        case .purgeMemory: "memorychip"
        case .reindexSpotlight: "magnifyingglass"
        }
    }

    /// Commande de l'outil d'aide, ou `nil` si la tâche se fait sans droits administrateur.
    var helperCommand: HelperCommand? {
        switch self {
        case .flushDNS: .flushDNSCache
        case .launchServices: nil
        case .purgeMemory: .purgeMemory
        case .reindexSpotlight: .reindexSpotlight
        }
    }

    /// Demande une confirmation avant de lancer.
    var needsConfirmation: Bool { self == .reindexSpotlight }
}

/// État du module « Maintenance » : tâches et mémoire vive.
@MainActor
@Observable
final class MaintenanceModel {
    enum TaskState: Equatable { case idle, running, done(String), failed(String) }

    private(set) var states: [MaintenanceTask: TaskState] = [:]
    private(set) var memory: MemoryStatus?
    private(set) var processes: [ProcessMemory] = []
    let helper: HelperManager

    init(helper: HelperManager) { self.helper = helper }

    func state(_ task: MaintenanceTask) -> TaskState { states[task] ?? .idle }

    func run(_ task: MaintenanceTask) {
        guard state(task) != .running else { return }
        states[task] = .running
        Task {
            if let command = task.helperCommand {
                helper.refresh()
                guard helper.status == .enabled else {
                    states[task] = .failed("Il faut l'outil d'aide (droits administrateur).")
                    return
                }
                do {
                    let (ok, text) = try await HelperClient.run(command)
                    states[task] = ok ? .done("Terminé") : .failed(text)
                } catch {
                    states[task] = .failed("L'outil d'aide n'a pas répondu : \(error.localizedDescription)")
                }
            } else {
                do {
                    try await UserMaintenance.rebuildLaunchServices()
                    states[task] = .done("Terminé")
                } catch {
                    states[task] = .failed(error.localizedDescription)
                }
            }
            refreshMemory()
        }
    }

    func refreshMemory() {
        memory = MemoryStatus.current()
        processes = ProcessList.topMemory(limit: 10)
    }

    /// Appli ouverte correspondant à un processus (pour proposer « Quitter »).
    func runningApp(_ process: ProcessMemory) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: process.pid),
              app.activationPolicy == .regular, app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }
        return app
    }

    func displayName(_ process: ProcessMemory) -> String {
        runningApp(process)?.localizedName ?? process.name
    }

    /// Demande poliment à l'appli de se fermer (elle peut proposer d'enregistrer).
    func quit(_ process: ProcessMemory) {
        runningApp(process)?.terminate()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refreshMemory()
        }
    }
}
