import Darwin
import Foundation

/// Détection de l'« Accès complet au disque » accordé à l'appli.
public enum FullDiskAccess {
    public enum Status: Sendable, Equatable {
        case granted
        case denied
        case unknown
    }

    /// Adresse du volet Réglages système › Confidentialité › Accès complet au disque.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Teste la lecture de fichiers protégés par TCC.
    public static func status(home: String = NSHomeDirectory()) -> Status {
        let probes = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/Bookmarks.plist",
            home + "/Library/Containers/com.apple.stocks",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        var sawDenied = false
        for path in probes {
            switch probe(path) {
            case .granted: return .granted
            case .denied: sawDenied = true
            case .unknown: continue
            }
        }
        return sawDenied ? .denied : .unknown
    }

    static func probe(_ path: String) -> Status {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return .unknown }
        if isDir.boolValue {
            let dir = opendir(path)
            if let dir {
                closedir(dir)
                return .granted
            }
        } else {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return .granted
            }
        }
        return (errno == EPERM || errno == EACCES) ? .denied : .unknown
    }
}
