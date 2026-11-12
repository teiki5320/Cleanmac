import CleanmacCore
import Foundation
import Observation

/// État global de l'appli.
@MainActor
@Observable
final class AppModel {
    enum ScanState {
        case idle
        case scanning(ScanProgress?)
        case finished(ScanResult)
        case cancelled
        case failed(String)
    }

    typealias CleanState = CleanPhase

    var fullDiskAccess: FullDiskAccess.Status = .unknown
    var rules: RuleBook?
    var rulesError: String?
    var scanState: ScanState = .idle
    var cleanState: CleanState = .idle
    /// Éléments cochés (par chemin ou référence externe).
    var selection: Set<String> = []
    var journalEntries: [JournalEntry] = []
    let helper = HelperManager()
    /// Carte du disque (lecture seule).
    let diskMap = DiskMapModel()
    /// Recherche des doublons et mise à la Corbeille des copies.
    let duplicates = DuplicatesModel()
    /// Fichiers d'iCloud Drive à libérer du Mac.
    let icloud = ICloudModel()
    /// Désinstallation, restes, démarrage, mises à jour.
    let apps = AppsModel()
    let purgeable: PurgeableModel
    let maintenance: MaintenanceModel
    /// Alerte d'espace et analyse programmée.
    let comfort = ComfortService()

    /// Réglage : suppression définitive des caches régénérables (désactivée par défaut).
    var allowPermanentDeletion: Bool {
        didSet { UserDefaults.standard.set(allowPermanentDeletion, forKey: Self.permanentKey) }
    }

    private static let permanentKey = "suppressionDefinitiveAutorisee"
    private var scanTask: Task<Void, Never>?
    private let journal = CleanJournal()
    /// Exclusions de l'utilisateur, relues à chaque scan.
    private(set) var exclusions: [String] = ExclusionStore().load()
    /// Fichier d'exclusions illisible : tout nettoyage est bloqué tant qu'il n'est pas réparé.
    private(set) var exclusionsError: String?
    /// Réglage « suppression définitive » figé à l'ouverture de l'écran de vérification :
    /// ce qui est montré est exactement ce qui sera fait.
    private var frozenPermanent: Bool?

    init() {
        ComfortKeys.registerDefaults()
        purgeable = PurgeableModel(helper: helper)
        maintenance = MaintenanceModel(helper: helper)
        allowPermanentDeletion = UserDefaults.standard.bool(forKey: Self.permanentKey)
        refreshFullDiskAccess()
        loadRules()
        journalEntries = journal.entries()
        // Exclusions relues à chaque usage : la recherche de doublons ne passe pas par `startScan`.
        duplicates.makeCleaner = { [unowned self] in
            self.reloadExclusions() ? self.makeCleaner() : nil
        }
        duplicates.onCleaned = { [unowned self] in self.journalEntries = self.journal.entries() }
        icloud.onCleaned = { [unowned self] in self.journalEntries = self.journal.entries() }
        apps.makeCleaner = { [unowned self] in
            self.reloadExclusions() ? self.makeCleaner() : nil
        }
        apps.makePolicy = { [unowned self] in ProtectionPolicy(userExclusions: self.exclusions) }
        apps.rules = { [unowned self] in self.rules?.rules(in: .apps) ?? [] }
        apps.onCleaned = { [unowned self] in self.journalEntries = self.journal.entries() }
        comfort.rules = { [unowned self] in self.rules }
        comfort.exclusions = { ExclusionStore().load() }
        comfort.start()
    }

    // MARK: Exclusions

    /// Relit les exclusions ; un fichier illisible bloque le nettoyage au lieu d'être ignoré.
    @discardableResult
    func reloadExclusions() -> Bool {
        do {
            exclusions = try ExclusionStore().loadStrict()
            exclusionsError = nil
            return true
        } catch {
            exclusionsError = "Fichier d'exclusions illisible (\(ExclusionStore().fileURL.path)) : nettoyage bloqué. \(error.localizedDescription)"
            return false
        }
    }

    func addExclusion(_ path: String) {
        do { try ExclusionStore().add(path) } catch { exclusionsError = "Exclusion non enregistrée : \(error.localizedDescription)" }
        reloadExclusions()
    }

    func removeExclusion(_ path: String) {
        do { try ExclusionStore().remove(path) } catch { exclusionsError = "Exclusion non retirée : \(error.localizedDescription)" }
        reloadExclusions()
    }

    func freezeSettingsForReview() { frozenPermanent = allowPermanentDeletion }
    func unfreezeSettings() { frozenPermanent = nil }
    private var effectivePermanent: Bool { frozenPermanent ?? allowPermanentDeletion }

    /// Place libérée tout de suite depuis le début (définitif et iCloud).
    var totalReleased: Int64 { journalEntries.reduce(0) { $0 + $1.releasedBytes } }
    /// Mis à la Corbeille depuis le début.
    var totalTrashed: Int64 { journalEntries.reduce(0) { $0 + $1.trashedBytes } }

    func refreshFullDiskAccess() {
        fullDiskAccess = FullDiskAccess.status()
    }

    func loadRules() {
        do {
            rules = try RuleBook.bundled()
            rulesError = nil
        } catch {
            rules = nil
            rulesError = error.localizedDescription
        }
    }

    // MARK: Scan

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    var scanResult: ScanResult? {
        if case let .finished(result) = scanState { return result }
        return nil
    }

    /// Catégories du dernier scan lancé (`nil` : toutes les règles).
    private(set) var scanCategories: Set<RuleCategory>?

    /// Lance un scan en lecture seule, de toutes les règles ou des seules catégories demandées.
    func startScan(categories: Set<RuleCategory>? = nil) {
        guard let rules, !isScanning, !isCleaning else { return }
        let selectedRules = categories.map { wanted in rules.rules.filter { wanted.contains($0.category) } } ?? rules.rules
        scanCategories = categories
        guard reloadExclusions() else {
            scanState = .failed(exclusionsError ?? "Exclusions illisibles")
            return
        }
        let policy = ProtectionPolicy(userExclusions: exclusions)
        scanState = .scanning(nil)
        cleanState = .idle
        scanTask = Task {
            do {
                let result = try await Scanner(policy: policy).scan(rules: selectedRules) { progress in
                    Task { @MainActor in
                        guard self.isScanning else { return }
                        self.scanState = .scanning(progress)
                    }
                }
                selection = Set(result.items.filter { $0.isSelectedByDefault && canClean($0) }.map(\.path))
                scanState = .finished(result)
            } catch is CancellationError {
                scanState = .cancelled
            } catch {
                scanState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    // MARK: Sélection

    func rule(for item: ScanItem) -> Rule? {
        rules?.rule(id: item.ruleID)
    }

    /// Nettoyeur configuré avec les réglages actuels (sert aussi aux vérifications d'affichage).
    func makeCleaner() -> Cleaner? {
        guard exclusionsError == nil else { return nil }
        return rules.map {
            Cleaner(
                rules: $0,
                policy: ProtectionPolicy(userExclusions: exclusions),
                journal: journal,
                allowPermanentDeletion: effectivePermanent)
        }
    }

    /// L'élément peut-il être nettoyé avec les réglages actuels ?
    func canClean(_ item: ScanItem) -> Bool {
        guard let rule = rule(for: item) else { return false }
        return Cleaner.canClean(rule, allowPermanentDeletion: effectivePermanent)
    }

    func method(for item: ScanItem) -> RemovalMethod {
        guard let rule = rule(for: item) else { return .trash }
        return Cleaner.method(for: rule, allowPermanentDeletion: effectivePermanent)
    }

    func isSelected(_ item: ScanItem) -> Bool {
        selection.contains(item.path) && canClean(item)
    }

    func toggle(_ item: ScanItem) {
        guard canClean(item) else { return }
        if selection.contains(item.path) { selection.remove(item.path) } else { selection.insert(item.path) }
    }

    func setSelected(_ items: [ScanItem], _ selected: Bool) {
        for item in items where canClean(item) {
            if selected { selection.insert(item.path) } else { selection.remove(item.path) }
        }
    }

    var selectedItems: [ScanItem] {
        scanResult?.items.filter(isSelected) ?? []
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.allocatedBytes }
    }

    // MARK: Nettoyage

    var isCleaning: Bool {
        if case .cleaning = cleanState { return true }
        return false
    }

    /// Nettoie les éléments cochés (après l'écran de vérification).
    func cleanSelection() {
        guard !isCleaning, reloadExclusions(), let cleaner = makeCleaner() else {
            if let exclusionsError { cleanState = .failed(exclusionsError) }
            return
        }
        let requests = selectedItems.map(CleanRequest.init)
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
                let cleaned = Set(entry.items.filter(\.succeeded).map(\.path))
                if let result = scanResult {
                    scanState = .finished(result.removing(cleaned))
                }
                selection.subtract(cleaned)
                journalEntries = journal.entries()
                cleanState = .finished(entry)
            } catch {
                cleanState = .failed(error.localizedDescription)
            }
        }
    }

    func dismissCleanResult() {
        cleanState = .idle
    }
}
