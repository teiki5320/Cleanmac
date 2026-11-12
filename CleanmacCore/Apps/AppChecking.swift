import AppKit
import Foundation

/// État des applis du Mac, interrogé par le nettoyeur juste avant de supprimer
/// (remplaçable dans les tests).
public protocol AppChecking: Sendable {
    /// Une appli portant cet identifiant est-elle ouverte ?
    func isRunning(bundleID: String) -> Bool
    /// Une appli portant cet identifiant est-elle installée (hors Corbeille) ?
    func isInstalled(bundleID: String) -> Bool
}

/// Interroge le système (LaunchServices et applis ouvertes).
public struct SystemAppChecker: AppChecking {
    public init() {}

    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func isInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).contains { url in
            let path = url.path
            return !path.contains("/.Trash/") && !path.contains("/.Trashes/")
                && FileManager.default.fileExists(atPath: path)
        }
    }
}
