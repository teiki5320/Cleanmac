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

    var fullDiskAccess: FullDiskAccess.Status = .unknown
    var rules: RuleBook?
    var rulesError: String?
    var scanState: ScanState = .idle
    let helper = HelperManager()

    private var scanTask: Task<Void, Never>?

    init() {
        refreshFullDiskAccess()
        loadRules()
    }

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

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    /// Lance un scan en lecture seule de toutes les règles.
    func startScan() {
        guard let rules, !isScanning else { return }
        let policy = ProtectionPolicy(userExclusions: ExclusionStore().load())
        scanState = .scanning(nil)
        scanTask = Task {
            do {
                let result = try await Scanner(policy: policy).scan(rules: rules.rules) { progress in
                    Task { @MainActor in
                        guard self.isScanning else { return }
                        self.scanState = .scanning(progress)
                    }
                }
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
}
