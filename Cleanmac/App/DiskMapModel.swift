import CleanmacCore
import Foundation
import Observation

/// État du module « Carte du disque » (lecture seule : rien n'est supprimé ici).
@MainActor
@Observable
final class DiskMapModel {
    /// Ce que la carte parcourt.
    enum Root: String, CaseIterable, Identifiable {
        case home
        case disk

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Dossier personnel"
            case .disk: "Tout le Mac"
            }
        }

        var symbol: String {
            switch self {
            case .home: "house"
            case .disk: "internaldrive"
            }
        }

        /// Chemin lu. Pour tout le Mac, le volume de données (le système est scellé et
        /// les dossiers comme /Users y renvoient : on évite ainsi de compter deux fois).
        var path: String {
            switch self {
            case .home:
                return NSHomeDirectory()
            case .disk:
                let data = "/System/Volumes/Data"
                return FileManager.default.fileExists(atPath: data + "/Users") ? data : "/"
            }
        }

        var displayName: String {
            switch self {
            case .home: "Dossier personnel"
            case .disk: "Macintosh HD"
            }
        }
    }

    enum State {
        case idle
        case scanning(DiskMapProgress?)
        case finished(DiskMap)
        case cancelled
        case failed(String)
    }

    var root: Root = .home
    private(set) var state: State = .idle
    /// Dossiers ouverts, de la racine au dossier affiché.
    private(set) var trail: [DiskNode] = []
    private var task: Task<Void, Never>?

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    var map: DiskMap? {
        if case let .finished(map) = state { return map }
        return nil
    }

    var progress: DiskMapProgress? {
        if case let .scanning(progress) = state { return progress }
        return nil
    }

    /// Dossier affiché au centre des anneaux.
    var focus: DiskNode? { trail.last }

    /// Avancement estimé (seulement pour tout le Mac, comparé à l'espace utilisé du disque).
    /// Espace occupé (hors purgeable), mesuré une fois au lancement de la carte « Tout le Mac ».
    private var usedAtStart: Int64?

    var estimatedFraction: Double? {
        guard root == .disk, isScanning, let used = usedAtStart, used > 0 else { return nil }
        return min(Double(progress?.bytesFound ?? 0) / Double(used), 0.99)
    }

    func start() {
        guard !isScanning else { return }
        usedAtStart = VolumeSpace.current().map { $0.total - $0.free }
        let root = root
        let path = root.path
        state = .scanning(nil)
        trail = []
        task = Task {
            do {
                let map = try await DiskMapper().map(path, name: root.displayName) { progress in
                    Task { @MainActor in
                        guard self.isScanning else { return }
                        self.state = .scanning(progress)
                    }
                }
                trail = [map.root]
                state = .finished(map)
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

    /// Change ce que la carte parcourt et relance l'analyse si une carte était affichée.
    func select(_ newRoot: Root) {
        guard newRoot != root, !isScanning else { return }
        let hadMap = map != nil
        root = newRoot
        state = .idle
        trail = []
        if hadMap { start() }
    }

    func open(_ node: DiskNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        trail.append(node)
    }

    func goUp() {
        guard trail.count > 1 else { return }
        trail.removeLast()
    }

    func goTo(index: Int) {
        guard trail.indices.contains(index) else { return }
        trail.removeSubrange((index + 1)...)
    }
}
