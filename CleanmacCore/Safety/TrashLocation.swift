import Darwin
import Foundation

/// Corbeilles du Mac : celle du dossier personnel et celles des disques externes.
public enum TrashLocation {
    /// Corbeilles existantes : `~/.Trash`, puis `/Volumes/<disque>/.Trashes/<uid>` pour chaque
    /// disque monté (sans suivre de lien : le disque de démarrage, lien vers « / », est ignoré).
    public static func folders(home: String = NSHomeDirectory(), uid: UInt32 = getuid()) -> [String] {
        var result = [PathPattern.trimmed(home) + "/.Trash"]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
        for name in names.sorted() where !name.hasPrefix(".") {
            let volume = "/Volumes/" + name
            guard PathPattern.isRealDirectory(volume) else { continue }
            let trash = volume + "/.Trashes/\(uid)"
            if PathPattern.isRealDirectory(trash) { result.append(trash) }
        }
        return result.filter { PathPattern.isRealDirectory($0) }
    }

    /// L'élément est-il directement dans une vraie Corbeille (aucun lien symbolique sur le chemin) ?
    public static func isDirectlyInTrash(_ path: String, home: String = NSHomeDirectory(), uid: UInt32 = getuid()) -> Bool {
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !path.hasSuffix("/") else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        guard PathPattern.isRealDirectory(parent), let realParent = realPath(parent) else { return false }

        let homeTrash = PathPattern.trimmed(home) + "/.Trash"
        if parent == homeTrash {
            // Le dossier personnel peut passer par un lien (dossiers temporaires) : on compare les chemins réels.
            guard let realHome = realPath(PathPattern.trimmed(home)) else { return false }
            return realParent == realHome + "/.Trash"
        }
        let parts = parent.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[1] == "Volumes", !parts[2].isEmpty,
              !parts[2].hasPrefix("."), parts[3] == ".Trashes", parts[4] == Substring(String(uid))
        else { return false }
        return realParent == parent
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
