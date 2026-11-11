import CleanmacCore
import Foundation
import Observation

/// État du module « Doublons » (lecture seule pour l'instant : rien n'est supprimé ici).
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

    private(set) var state: State = .idle
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

    func start() {
        guard !isScanning else { return }
        state = .scanning(nil)
        task = Task {
            do {
                let scan = try await DuplicateFinder().find(in: Self.roots, excluding: Self.excluded) { progress in
                    Task { @MainActor in
                        guard self.isScanning else { return }
                        self.state = .scanning(progress)
                    }
                }
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
}
