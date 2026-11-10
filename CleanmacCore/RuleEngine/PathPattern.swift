import Darwin
import Foundation

/// Motifs de chemins des règles : expansion de `~` et des jokers, correspondance.
public struct PathPattern: Sendable {
    /// Dossier personnel utilisé pour `~` (injectable pour les tests).
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = Self.trimmed(home)
    }

    /// Retire les « / » finaux sans jamais réécrire le chemin
    /// (contrairement à `standardizingPath`, qui supprime par exemple « /private »).
    public static func trimmed(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func hasGlob(_ component: String) -> Bool {
        component.contains { $0 == "*" || $0 == "?" || $0 == "[" }
    }

    /// Raison pour laquelle un motif est refusé, ou `nil` s'il est acceptable.
    static func problem(with pattern: String) -> String? {
        let body: String
        if pattern.hasPrefix("~/") {
            body = String(pattern.dropFirst(2))
        } else if pattern.hasPrefix("/") {
            body = String(pattern.dropFirst())
        } else {
            return "doit commencer par « ~/ » ou « / »"
        }
        let components = body.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if components.contains(where: { $0.isEmpty }) { return "composant vide" }
        if components.contains(where: { $0 == ".." || $0 == "." }) { return "« . » et « .. » interdits" }
        if components.contains("**") { return "« ** » interdit" }
        // Au moins un composant fixe avant tout joker : jamais « ~/* » ni « /* ».
        guard let first = components.first, !hasGlob(first) else {
            return "le premier composant ne peut pas être un joker"
        }
        if pattern.hasPrefix("/") && components.count < 2 { return "trop proche de la racine" }
        return nil
    }

    /// Chemin absolu du motif (`~` remplacé par le dossier personnel).
    public func absolute(_ pattern: String) -> String {
        if pattern.hasPrefix("~/") {
            return home + "/" + pattern.dropFirst(2)
        }
        return pattern
    }

    /// Le chemin correspond-il au motif ? (`*` ne traverse pas les « / »)
    public func matches(_ path: String, pattern: String) -> Bool {
        fnmatch(absolute(pattern), path, FNM_PATHNAME) == 0
    }

    /// Le chemin correspond-il à l'un des chemins de la règle, hors exclusions ?
    public func matches(_ path: String, rule: Rule) -> Bool {
        rule.paths.contains { matches(path, pattern: $0) }
            && !rule.excludes.contains { matches(path, pattern: $0) }
    }

    /// Liste les éléments existants qui correspondent aux chemins de la règle.
    /// Les liens symboliques ne sont jamais suivis par les jokers.
    public func expand(rule: Rule) -> [String] {
        var result = Set<String>()
        for pattern in rule.paths {
            for path in expand(pattern) where !rule.excludes.contains(where: { matches(path, pattern: $0) }) {
                result.insert(path)
            }
        }
        return result.sorted()
    }

    public func expand(_ pattern: String) -> [String] {
        let absolute = absolute(pattern)
        let components = absolute.split(separator: "/").map(String.init)
        var current: [String] = [""]
        for (index, component) in components.enumerated() {
            let isLast = index == components.count - 1
            var next: [String] = []
            for base in current {
                let dir = base.isEmpty ? "/" : base
                if Self.hasGlob(component) {
                    // Les jokers ne descendent que dans de vrais dossiers.
                    if base.isEmpty == false && !Self.isRealDirectory(base) { continue }
                    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                    for name in names.sorted() where fnmatch(component, name, FNM_PATHNAME) == 0 {
                        next.append(base + "/" + name)
                    }
                } else {
                    let candidate = base + "/" + component
                    if isLast ? Self.exists(candidate) : Self.isDirectoryFollowingLinks(candidate) {
                        next.append(candidate)
                    }
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current.filter { !$0.isEmpty }
    }

    static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    static func isRealDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    static func isDirectoryFollowingLinks(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
