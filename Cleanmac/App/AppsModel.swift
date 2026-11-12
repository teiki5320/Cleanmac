import AppKit
import CleanmacCore
import Foundation
import Observation

/// État du module « Applications » : désinstallation, restes, démarrage, mises à jour.
@MainActor
@Observable
final class AppsModel {
    enum Tab: String, CaseIterable, Identifiable {
        case uninstall, leftovers, startup, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .uninstall: "Désinstaller"
            case .leftovers: "Restes"
            case .startup: "Démarrage"
            case .updates: "Mises à jour"
            }
        }
        var symbol: String {
            switch self {
            case .uninstall: "xmark.app"
            case .leftovers: "magnifyingglass"
            case .startup: "power"
            case .updates: "arrow.down.circle"
            }
        }
    }

    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var tab: Tab = .uninstall
    private(set) var phase: Phase = .idle
    private(set) var apps: [InstalledApp] = []
    /// Taille des paquets, calculée en arrière-plan.
    private(set) var sizes: [String: Int64] = [:]

    // Désinstallation
    private(set) var chosen: InstalledApp?
    private(set) var chosenFiles: [AppFile]?
    private(set) var fileSelection: Set<String> = []

    // Restes
    private(set) var leftovers: [Leftover] = []
    private(set) var leftoverSelection: Set<String> = []

    // Démarrage
    private(set) var launchItems: [LaunchItem] = []
    private(set) var launchMessage: String?
    private(set) var launchBusy: String?

    // Mises à jour
    enum UpdatesPhase: Equatable { case idle, checking, done, failed(String) }
    private(set) var updatesPhase: UpdatesPhase = .idle
    private(set) var updates: [AppUpdate] = []
    private(set) var brewMessage: String?

    private(set) var cleanState: CleanPhase = .idle
    var makeCleaner: () -> Cleaner? = { nil }
    var makePolicy: () -> ProtectionPolicy = { ProtectionPolicy() }
    var rules: () -> [Rule] = { [] }
    var onCleaned: () -> Void = {}

    private var sizeTask: Task<Void, Never>?
    /// Change à chaque lancement ou fermeture d'appli : l'état « ouverte » se remet à jour.
    private(set) var runningRevision = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runningRevision += 1 }
            })
        }
    }

    var isLoading: Bool { phase == .loading }
    var hasLoaded: Bool { phase == .loaded }
    var isCleaning: Bool { cleanState.isRunning }

    // MARK: Chargement

    func start() {
        guard !isLoading, !isCleaning else { return }
        phase = .loading
        sizes = [:]
        let rules = rules()
        let policy = makePolicy()
        // Identifiants encore utilisés sans appli installée : applis ouvertes, éléments de démarrage.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task {
            let catalog = AppCatalog()
            let labels = Set(await LaunchItems().list().map(\.label))
            let (apps, leftovers) = await Task.detached(priority: .userInitiated) {
                let apps = catalog.installedApps()
                let known = catalog.knownBundleIDs().union(running).union(labels)
                let checker = SystemAppChecker()
                let leftovers = catalog.leftovers(rules: rules, knownIDs: known, policy: policy,
                                                  isInstalled: { checker.isInstalled(bundleID: $0) })
                return (apps, leftovers)
            }.value
            self.apps = apps
            self.leftovers = leftovers
            leftoverSelection = []
            if let chosen, !apps.contains(chosen) { self.chosen = nil; chosenFiles = nil }
            phase = .loaded
            await refreshLaunchItems()
            measureSizes()
        }
    }

    /// Mesure la taille de chaque appli, sans bloquer l'interface.
    private func measureSizes() {
        sizeTask?.cancel()
        let pending = apps.filter { sizes[$0.path] == nil }
        sizeTask = Task {
            for app in pending {
                if Task.isCancelled { return }
                let bytes = await Task.detached(priority: .utility) {
                    (try? SizeCalculator().measure(app.path).allocatedBytes) ?? 0
                }.value
                sizes[app.path] = bytes
            }
        }
    }

    // MARK: Désinstallation

    func isRunning(_ app: InstalledApp) -> Bool {
        _ = runningRevision
        return !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Raison pour laquelle une appli ne peut pas être désinstallée d'ici.
    func blockReason(_ app: InstalledApp) -> String? {
        if app.bundleID == Cleaner.ownBundleID { return "C'est Cleanmac" }
        if app.identity.problem != nil { return "Nom ou identifiant inhabituel : passez par le Finder" }
        // Paquet appartenant au système (installeur, App Store) : la Corbeille demanderait un mot de passe,
        // et ses réglages partiraient sans elle.
        let parent = (app.path as NSString).deletingLastPathComponent
        if !FileManager.default.isWritableFile(atPath: app.path) || !FileManager.default.isWritableFile(atPath: parent) {
            return "Cette appli appartient au système (installée par un installeur ou l'App Store) : désinstallez-la depuis le Finder, qui demandera votre mot de passe."
        }
        return nil
    }

    func choose(_ app: InstalledApp?) {
        guard !isCleaning else { return }
        chosen = app
        chosenFiles = nil
        fileSelection = []
        guard let app, blockReason(app) == nil else { return }
        let rules = rules()
        let policy = makePolicy()
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                AppCatalog().files(of: app, rules: rules, policy: policy)
            }.value
            guard chosen == app else { return }
            chosenFiles = files
            fileSelection = Set(files.filter(\.isSelectedByDefault).map(\.path))
        }
    }

    func toggleFile(_ file: AppFile) {
        guard !isCleaning else { return }
        if fileSelection.contains(file.path) { fileSelection.remove(file.path) } else { fileSelection.insert(file.path) }
    }

    var selectedAppFiles: [AppFile] { (chosenFiles ?? []).filter { fileSelection.contains($0.path) } }

    func uninstallSelection() {
        guard let app = chosen, let cleaner = makeCleaner(), !isCleaning else { return }
        let requests = selectedAppFiles.map {
            CleanRequest(path: $0.path, ruleID: $0.ruleID, bytes: $0.allocatedBytes, app: app.identity)
        }
        run(requests, cleaner: cleaner) { [weak self] removed in
            guard let self else { return }
            if removed.contains(app.path) {
                apps.removeAll { $0.path == app.path }
                chosen = nil
                chosenFiles = nil
            } else {
                chosenFiles = chosenFiles?.filter { !removed.contains($0.path) }
            }
            fileSelection.subtract(removed)
        }
    }

    // MARK: Restes

    func toggleLeftover(_ leftover: Leftover) {
        guard !isCleaning else { return }
        let paths = Set(leftover.files.map(\.path))
        if paths.isSubset(of: leftoverSelection) { leftoverSelection.subtract(paths) } else { leftoverSelection.formUnion(paths) }
    }

    func isSelected(_ leftover: Leftover) -> GlassCheckbox.State {
        let paths = Set(leftover.files.map(\.path))
        if paths.isSubset(of: leftoverSelection) { return .on }
        return paths.isDisjoint(with: leftoverSelection) ? .off : .mixed
    }

    var selectedLeftovers: [(leftover: Leftover, file: AppFile)] {
        leftovers.flatMap { leftover in
            leftover.files.filter { leftoverSelection.contains($0.path) }.map { (leftover: leftover, file: $0) }
        }
    }

    func trashLeftovers() {
        guard let cleaner = makeCleaner(), !isCleaning else { return }
        let requests = selectedLeftovers.map {
            CleanRequest(path: $0.file.path, ruleID: $0.file.ruleID, bytes: $0.file.allocatedBytes, app: $0.leftover.identity)
        }
        run(requests, cleaner: cleaner) { [weak self] removed in
            guard let self else { return }
            leftovers = leftovers.compactMap { leftover in
                let files = leftover.files.filter { !removed.contains($0.path) }
                return files.isEmpty ? nil : Leftover(bundleID: leftover.bundleID, files: files)
            }
            leftoverSelection.subtract(removed)
        }
    }

    private func run(_ requests: [CleanRequest], cleaner: Cleaner, apply: @escaping (Set<String>) -> Void) {
        guard !requests.isEmpty else { return }
        cleanState = .cleaning(done: 0, total: requests.count)
        Task {
            do {
                let entry = try await cleaner.clean(requests) { done, total in
                    Task { @MainActor in
                        guard self.isCleaning else { return }
                        self.cleanState = .cleaning(done: done, total: total)
                    }
                }
                apply(Set(entry.items.filter(\.succeeded).map(\.path)))
                onCleaned()
                cleanState = .finished(entry)
            } catch {
                cleanState = .failed(error.localizedDescription)
            }
        }
    }

    func dismissCleanResult() { cleanState = .idle }

    // MARK: Démarrage

    func refreshLaunchItems() async {
        launchItems = await LaunchItems().list()
    }

    func setEnabled(_ enabled: Bool, _ item: LaunchItem) {
        guard launchBusy == nil else { return }
        launchBusy = item.id
        Task {
            do {
                try await LaunchItems().setEnabled(enabled, item)
                launchMessage = (enabled ? "Activé : " : "Désactivé : ") + item.label
            } catch {
                launchMessage = error.localizedDescription
            }
            await refreshLaunchItems()
            launchBusy = nil
        }
    }

    // MARK: Mises à jour

    func checkUpdates() {
        guard updatesPhase != .checking else { return }
        updatesPhase = .checking
        brewMessage = nil
        let apps = apps
        Task {
            var found = await UpdateChecker().sparkleUpdates(for: apps)
            if UpdateChecker.brewPath != nil {
                do {
                    found += try await UpdateChecker().homebrewUpdates()
                } catch {
                    brewMessage = "Homebrew : \(error.localizedDescription)"
                }
            }
            updates = found
            updatesPhase = .done
        }
    }
}
