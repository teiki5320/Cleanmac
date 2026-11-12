import CleanmacCore
import Foundation
import Observation

/// État du module « iCloud Drive » : inventaire, fichiers cochés, libération (jamais de suppression).
@MainActor
@Observable
final class ICloudModel {
    enum State {
        case idle
        case scanning(ICloudProgress?)
        case finished(ICloudScan)
        case cancelled
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var cleanState: CleanPhase = .idle
    private(set) var selection: Set<String> = []
    /// Appelé après une libération, pour rafraîchir le journal.
    var onCleaned: () -> Void = {}
    private var task: Task<Void, Never>?

    var isScanning: Bool { if case .scanning = state { return true }; return false }
    var isCleaning: Bool { cleanState.isRunning }
    var scan: ICloudScan? { if case let .finished(scan) = state { return scan }; return nil }
    var progress: ICloudProgress? { if case let .scanning(progress) = state { return progress }; return nil }

    func start() {
        guard !isScanning, !isCleaning else { return }
        state = .scanning(nil)
        task = Task {
            do {
                let scan = try await ICloudScanner().scan { progress in
                    Task { @MainActor in
                        guard self.isScanning else { return }
                        self.state = .scanning(progress)
                    }
                }
                selection = []
                state = .finished(scan)
            } catch is CancellationError {
                state = .cancelled
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() { task?.cancel() }

    func isSelected(_ file: ICloudFile) -> Bool { selection.contains(file.path) && file.isUploaded }

    func toggle(_ file: ICloudFile) {
        guard file.isUploaded, !isCleaning else { return }
        if selection.contains(file.path) { selection.remove(file.path) } else { selection.insert(file.path) }
    }

    func select(_ files: [ICloudFile]) {
        for file in files where file.isUploaded { selection.insert(file.path) }
    }

    func deselect(_ files: [ICloudFile]) {
        for file in files { selection.remove(file.path) }
    }

    /// Fichiers non ouverts depuis `days` jours (ou jamais ouverts selon le Mac).
    func notOpened(since days: Int, in files: [ICloudFile]) -> [ICloudFile] {
        let limit = Date().addingTimeInterval(-Double(days) * 86_400)
        return files.filter { $0.isUploaded && ($0.lastOpened ?? $0.modified) < limit }
    }

    var selectedFiles: [ICloudFile] { (scan?.files ?? []).filter(isSelected) }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.allocatedBytes } }

    /// Libère les fichiers cochés (après l'écran de vérification).
    func evictSelection() {
        guard !isCleaning else { return }
        let files = selectedFiles.map { (path: $0.path, bytes: $0.allocatedBytes) }
        guard !files.isEmpty else { return }
        cleanState = .cleaning(done: 0, total: files.count)
        Task {
            do {
                let entry = try await ICloudEvictionService().evict(files) { done, total in
                    Task { @MainActor in
                        guard self.isCleaning else { return }
                        self.cleanState = .cleaning(done: done, total: total)
                    }
                }
                let done = Set(entry.items.filter(\.succeeded).map(\.path))
                if let scan { state = .finished(scan.removing(done)) }
                selection.subtract(done)
                onCleaned()
                cleanState = .finished(entry)
            } catch {
                cleanState = .failed(error.localizedDescription)
            }
        }
    }

    func dismissCleanResult() { cleanState = .idle }
}
