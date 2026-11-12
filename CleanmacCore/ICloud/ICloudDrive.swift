import Darwin
import Foundation

/// Un fichier (ou paquet) d'iCloud Drive présent sur le Mac.
public struct ICloudFile: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    /// Espace occupé sur le Mac (blocs alloués).
    public let allocatedBytes: Int64
    public let modified: Date
    /// Dernière ouverture connue (date d'accès), si disponible.
    public let lastOpened: Date?
    /// Dossier d'iCloud Drive (« iCloud Drive », ou le nom de l'appli qui range ses fichiers).
    public let container: String
    /// Le fichier est entièrement envoyé dans iCloud : on peut le libérer sans risque.
    public let isUploaded: Bool

    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, allocatedBytes: Int64, modified: Date, lastOpened: Date?, container: String, isUploaded: Bool) {
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.modified = modified
        self.lastOpened = lastOpened
        self.container = container
        self.isUploaded = isUploaded
    }
}

/// Avancement de l'inventaire d'iCloud Drive.
public struct ICloudProgress: Sendable, Equatable {
    public var filesSeen: Int
    public var bytesFound: Int64
    public var currentPath: String
}

/// Inventaire d'iCloud Drive.
public struct ICloudScan: Sendable {
    public let files: [ICloudFile]
    /// Fichiers non téléchargés (déjà libérés), ignorés.
    public let cloudOnlyCount: Int
    public let duration: Duration

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.allocatedBytes } }
    public var evictableBytes: Int64 { files.filter(\.isUploaded).reduce(0) { $0 + $1.allocatedBytes } }

    public init(files: [ICloudFile], cloudOnlyCount: Int, duration: Duration) {
        self.files = files
        self.cloudOnlyCount = cloudOnlyCount
        self.duration = duration
    }

    public func removing(_ paths: Set<String>) -> ICloudScan {
        ICloudScan(files: files.filter { !paths.contains($0.path) }, cloudOnlyCount: cloudOnlyCount + paths.count, duration: duration)
    }
}

/// Paquets traités comme un seul fichier (on ne descend pas dedans).
enum PackageExtensions {
    static let all: Set<String> = [
        "app", "pages", "numbers", "key", "rtfd", "band", "logicx", "fcpbundle", "imovielibrary",
        "photoslibrary", "musiclibrary", "tvlibrary", "sparsebundle", "bundle", "playground",
        "xcodeproj", "xcworkspace", "scriv", "graffle", "sketch", "dtBase2", "pxd",
    ]

    static func isPackage(_ name: String) -> Bool {
        all.contains((name as NSString).pathExtension.lowercased()) || all.contains((name as NSString).pathExtension)
    }
}

/// Inventaire des fichiers d'iCloud Drive téléchargés sur le Mac (lecture seule).
public struct ICloudScanner: Sendable {
    /// Dossier d'iCloud Drive (`~/Library/Mobile Documents`).
    public let root: String
    /// Taille minimale d'un fichier listé.
    public let minimumBytes: Int64

    public init(home: String = NSHomeDirectory(), minimumBytes: Int64 = 1_000_000) {
        self.root = PathPattern.trimmed(home) + "/Library/Mobile Documents"
        self.minimumBytes = minimumBytes
    }

    public init(root: String, minimumBytes: Int64) {
        self.root = PathPattern.trimmed(root)
        self.minimumBytes = minimumBytes
    }

    /// Nom lisible d'un dossier de premier niveau de `Mobile Documents`.
    public static func containerName(_ folder: String) -> String {
        if folder == "com~apple~CloudDocs" { return "iCloud Drive" }
        let last = folder.split(separator: "~").last.map(String.init) ?? folder
        return last.isEmpty ? folder : last
    }

    @concurrent
    public func scan(progress: (@Sendable (ICloudProgress) -> Void)? = nil) async throws -> ICloudScan {
        let clock = ContinuousClock()
        let start = clock.now
        var files: [ICloudFile] = []
        var cloudOnly = 0
        var state = ICloudProgress(filesSeen: 0, bytesFound: 0, currentPath: root)
        let containers = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()

        for folder in containers {
            let base = root + "/" + folder
            guard PathPattern.isRealDirectory(base) else { continue }
            let container = Self.containerName(folder)
            var stack = [base]
            while let dir = stack.popLast() {
                try Task.checkCancellation()
                state.currentPath = dir
                progress?(state)
                guard let handle = opendir(dir) else { continue }
                defer { closedir(handle) }
                while let entry = readdir(handle) {
                    let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                        String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
                    }
                    if name == "." || name == ".." || name.hasPrefix(".") { continue }
                    let path = dir + "/" + name
                    var st = stat()
                    guard lstat(path, &st) == 0 else { continue }
                    let type = st.st_mode & S_IFMT
                    let dataless = st.st_flags & UInt32(SF_DATALESS) != 0
                    if type == S_IFDIR && !PackageExtensions.isPackage(name) {
                        if !dataless { stack.append(path) } else { cloudOnly += 1 }
                        continue
                    }
                    guard type == S_IFREG || type == S_IFDIR else { continue }
                    state.filesSeen += 1
                    if dataless { cloudOnly += 1; continue }
                    let bytes = type == S_IFDIR ? Self.packageBytes(path) : Int64(st.st_blocks) * 512
                    guard bytes >= minimumBytes else { continue }
                    let url = URL(fileURLWithPath: path)
                    let values = try? url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemDownloadingStatusKey, .contentAccessDateKey])
                    if values?.ubiquitousItemDownloadingStatus == .notDownloaded { cloudOnly += 1; continue }
                    files.append(ICloudFile(
                        path: path,
                        allocatedBytes: bytes,
                        modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)),
                        lastOpened: values?.contentAccessDate,
                        container: container,
                        isUploaded: values?.ubiquitousItemIsUploaded ?? false))
                    state.bytesFound += bytes
                }
            }
        }
        progress?(state)
        return ICloudScan(files: files.sorted { $0.allocatedBytes > $1.allocatedBytes },
                          cloudOnlyCount: cloudOnly, duration: clock.now - start)
    }

    /// Taille d'un paquet (fichiers non « dataless » seulement).
    static func packageBytes(_ path: String) -> Int64 {
        (try? SizeCalculator().measure(path).allocatedBytes) ?? 0
    }
}

/// Raisons pour lesquelles un fichier n'est pas libéré.
public enum EvictRefusal: Error, Equatable, CustomStringConvertible {
    case outsideICloud
    case missing
    case notUploaded
    case alreadyEvicted
    case failed(String)

    public var description: String {
        switch self {
        case .outsideICloud: "Hors d'iCloud Drive"
        case .missing: "Fichier introuvable"
        case .notUploaded: "Pas encore entièrement envoyé dans iCloud : gardé sur le Mac"
        case .alreadyEvicted: "Déjà libéré"
        case let .failed(message): message
        }
    }
}

/// Opération réelle de libération (remplaçable dans les tests).
public protocol ICloudEvicting: Sendable {
    /// Le fichier est-il entièrement envoyé dans iCloud ?
    func isUploaded(_ path: String) -> Bool
    /// Retire la copie locale ; le fichier reste dans iCloud.
    func evict(_ path: String) async throws
}

/// Libération via `FileManager` (puis `brctl evict` en secours).
public struct SystemICloudEvictor: ICloudEvicting {
    public init() {}

    public func isUploaded(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.ubiquitousItemIsUploadedKey])
        return values?.ubiquitousItemIsUploaded == true
    }

    public func evict(_ path: String) async throws {
        do {
            try FileManager.default.evictUbiquitousItem(at: URL(fileURLWithPath: path))
        } catch {
            _ = try await ToolRunner.run("/usr/bin/brctl", ["evict", path])
        }
    }
}

/// Libère des fichiers d'iCloud Drive : ils restent dans iCloud et se retéléchargent à l'ouverture.
/// Rien n'est supprimé. Chaque fichier est revérifié juste avant (dans iCloud Drive, présent,
/// entièrement envoyé), et chaque opération est notée dans le journal.
public struct ICloudEvictionService: Sendable {
    public static let journalRuleID = "icloud.liberer"
    public let root: String
    public let evictor: any ICloudEvicting
    public let journal: CleanJournal

    public init(home: String = NSHomeDirectory(), evictor: any ICloudEvicting = SystemICloudEvictor(), journal: CleanJournal = CleanJournal()) {
        self.root = PathPattern.trimmed(home) + "/Library/Mobile Documents"
        self.evictor = evictor
        self.journal = journal
    }

    /// Vérifie qu'un fichier peut être libéré.
    public func validate(_ path: String) throws(EvictRefusal) {
        guard path.hasPrefix(root + "/"), ProtectionPolicy.pathProblem(path, home: "/nonexistent-home") == nil else {
            throw .outsideICloud
        }
        // Aucun lien symbolique entre la racine d'iCloud Drive et le fichier.
        var current = (path as NSString).deletingLastPathComponent
        while current.count > root.count {
            guard PathPattern.isRealDirectory(current) else { throw .outsideICloud }
            current = (current as NSString).deletingLastPathComponent
        }
        var st = stat()
        guard lstat(path, &st) == 0 else { throw .missing }
        let type = st.st_mode & S_IFMT
        guard type == S_IFREG || type == S_IFDIR else { throw .outsideICloud }
        guard st.st_flags & UInt32(SF_DATALESS) == 0 else { throw .alreadyEvicted }
        guard evictor.isUploaded(path) else { throw .notUploaded }
    }

    @concurrent
    public func evict(_ files: [(path: String, bytes: Int64)], progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> JournalEntry {
        var lines: [JournalItem] = []
        for (index, file) in files.enumerated() {
            if Task.isCancelled { break }
            progress?(index, files.count)
            do {
                try validate(file.path)
                try await evictor.evict(file.path)
                lines.append(JournalItem(path: file.path, ruleID: Self.journalRuleID, bytes: file.bytes,
                                         method: .evicted, succeeded: true, message: nil, trashedPath: nil))
            } catch {
                let message = (error as? EvictRefusal)?.description ?? error.localizedDescription
                lines.append(JournalItem(path: file.path, ruleID: Self.journalRuleID, bytes: file.bytes,
                                         method: .evicted, succeeded: false, message: message, trashedPath: nil))
            }
        }
        progress?(files.count, files.count)
        let entry = JournalEntry(items: lines)
        if !lines.isEmpty { try journal.append(entry) }
        return entry
    }
}
