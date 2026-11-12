import CleanmacCore
import Foundation
import Observation

/// État du module « Doublons » : recherche, choix de l'exemplaire à garder, copies cochées,
/// puis mise à la Corbeille via la règle `doublons.copies` (jamais de suppression définitive).
@MainActor
@Observable
final class DuplicatesModel {
    enum State {
        case idle
        case scanning(DuplicateProgress?)
        case finished(DuplicateScan)
        case cancelled
        case failed(String)
    }

    enum CleanState {
        case idle
        case cleaning(done: Int, total: Int)
        case finished(JournalEntry)
        case failed(String)
    }

    /// Règle qui autorise la mise à la Corbeille des copies.
    static let ruleID = "doublons.copies"

    private(set) var state: State = .idle
    private(set) var cleanState: CleanState = .idle
    /// Exemplaire gardé de chaque groupe (identifiant du groupe → chemin). Par défaut : la suggestion.
    private(set) var keepers: [String: String] = [:]
    /// Copies cochées pour la Corbeille. Rien n'est coché d'office (règle « à vérifier »).
    private(set) var selection: Set<String> = []
    /// Copies qu'aucune règle n'autorise à supprimer d'ici (chemin → raison lisible).
    private(set) var blocked: [String: String] = [:]

    /// Nettoyeur configuré avec les réglages actuels (fourni par `AppModel`).
    var makeCleaner: () -> Cleaner? = { nil }
    /// Appelé après un nettoyage, pour rafraîchir le journal.
    var onCleaned: () -> Void = {}

    private var task: Task<Void, Never>?

    /// Où l'on cherche : le dossier personnel, sans la Bibliothèque (fichiers gérés par les applis).
    static var roots: [String] { [NSHomeDirectory()] }
    static var excluded: [String] { [NSHomeDirectory() + "/Library"] }

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    var scan: DuplicateScan? {
        if case let .finished(scan) = state { return scan }
        return nil
    }

    var progress: DuplicateProgress? {
        if case let .scanning(progress) = state { return progress }
        return nil
    }

    var isCleaning: Bool {
        if case .cleaning = cleanState { return true }
        return false
    }

    func start() {
        guard !isScanning, !isCleaning else { return }
        state = .scanning(nil)
        task = Task {
            do {
                let scan = try await DuplicateFinder().find(in: Self.roots, excluding: Self.excluded) { progress in
                    Task { @MainActor in
                        guard self.isScanning else { return }
                        self.state = .scanning(progress)
                    }
                }
                keepers = Dictionary(uniqueKeysWithValues: scan.groups.compactMap { group in
                    group.suggestedKeep.map { (group.id, $0.path) }
                })
                selection = []
                blocked = computeBlocked(scan)
                state = .finished(scan)
            } catch is CancellationError {
                state = .cancelled
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: Choix

    func keeper(of group: DuplicateGroup) -> String? {
        keepers[group.id] ?? group.suggestedKeep?.path
    }

    func isKeeper(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        keeper(of: group) == file.path
    }

    /// La copie peut-elle être cochée ? (ni l'exemplaire gardé, ni hors règle)
    func canTrash(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        !isKeeper(file, in: group) && blocked[file.path] == nil
    }

    func isSelected(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        selection.contains(file.path) && canTrash(file, in: group)
    }

    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        guard canTrash(file, in: group), !isCleaning else { return }
        if selection.contains(file.path) { selection.remove(file.path) } else { selection.insert(file.path) }
    }

    /// Choisit l'exemplaire à garder : il est retiré des copies cochées.
    func keep(_ file: DuplicateFile, in group: DuplicateGroup) {
        guard !isCleaning else { return }
        keepers[group.id] = file.path
        selection.remove(file.path)
    }

    /// Coche toutes les copies autorisées, en gardant l'exemplaire choisi de chaque groupe.
    func selectAllCopies(in groups: [DuplicateGroup]) {
        for group in groups {
            for file in group.files where canTrash(file, in: group) { selection.insert(file.path) }
        }
    }

    func deselect(in groups: [DuplicateGroup]) {
        for file in groups.flatMap(\.files) { selection.remove(file.path) }
    }

    /// Copies cochées, avec leur groupe.
    var selectedCopies: [(file: DuplicateFile, group: DuplicateGroup)] {
        (scan?.groups ?? []).flatMap { group in
            group.files.filter { isSelected($0, in: group) }.map { (file: $0, group: group) }
        }
    }

    /// Espace libéré une fois la Corbeille vidée (les copies APFS ne libèrent presque rien).
    var selectedBytes: Int64 {
        selectedCopies.reduce(0) { $0 + ($1.file.mayShareBlocks ? 0 : $1.file.allocatedBytes) }
    }

    /// Nombre de copies qu'on peut mettre à la Corbeille d'ici.
    func trashableCount(in groups: [DuplicateGroup]) -> Int {
        groups.reduce(0) { total, group in total + group.files.filter { canTrash($0, in: group) }.count }
    }

    // MARK: Nettoyage

    /// Met les copies cochées à la Corbeille (après l'écran de vérification).
    /// Le nettoyeur revérifie chaque copie : règle, protections, exemplaire gardé présent et identique.
    func trashSelection() {
        guard !isCleaning, let cleaner = makeCleaner() else { return }
        let requests = selectedCopies.map { copy in
            CleanRequest(path: copy.file.path, ruleID: Self.ruleID,
                         bytes: copy.file.mayShareBlocks ? 0 : copy.file.allocatedBytes,
                         keeperPath: keeper(of: copy.group))
        }
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
                let removed = Set(entry.items.filter(\.succeeded).map(\.path))
                if let scan { state = .finished(Self.removing(removed, from: scan)) }
                selection.subtract(removed)
                onCleaned()
                cleanState = .finished(entry)
            } catch {
                cleanState = .failed(error.localizedDescription)
            }
        }
    }

    func dismissCleanResult() {
        cleanState = .idle
    }

    /// Retire les fichiers supprimés ; un groupe réduit à un seul fichier disparaît.
    static func removing(_ removed: Set<String>, from scan: DuplicateScan) -> DuplicateScan {
        let groups = scan.groups.compactMap { group -> DuplicateGroup? in
            let files = group.files.filter { !removed.contains($0.path) }
            return files.count > 1 ? DuplicateGroup(id: group.id, size: group.size, files: files) : nil
        }
        return DuplicateScan(groups: groups, filesExamined: scan.filesExamined,
                             unreadableCount: scan.unreadableCount, duration: scan.duration)
    }

    /// Copies qu'on ne peut pas supprimer d'ici, avec la raison (hors règle, protégé…).
    private func computeBlocked(_ scan: DuplicateScan) -> [String: String] {
        guard let cleaner = makeCleaner() else {
            return Dictionary(uniqueKeysWithValues: scan.groups.flatMap(\.files).map { ($0.path, "Règles indisponibles") })
        }
        var result: [String: String] = [:]
        for group in scan.groups {
            for file in group.files {
                let other = group.files.first { $0.path != file.path }?.path
                do {
                    _ = try cleaner.validate(CleanRequest(path: file.path, ruleID: Self.ruleID,
                                                          bytes: file.allocatedBytes, keeperPath: other))
                } catch {
                    result[file.path] = Self.reason(error)
                }
            }
        }
        return result
    }

    private static func reason(_ refusal: CleanRefusal) -> String {
        switch refusal {
        case .notMatchingRule: "Hors des dossiers autorisés"
        case let .protected(reason):
            switch reason {
            case let .protectedLocation(path), let .containsProtectedLocation(path):
                "Protégé : \(DisplayPath.short(path))"
            case .gitRepository: "Dossier de code (git)"
            case .userExclusion: "Exclu par vous"
            case .photoLibrary: "Photothèque"
            case .unsafePath: "Chemin refusé"
            }
        default: refusal.description
        }
    }
}
