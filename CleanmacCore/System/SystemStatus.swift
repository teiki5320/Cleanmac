import Darwin
import Foundation

/// Instantanés APFS locaux du disque de démarrage et espace « purgeable ».
public struct LocalSnapshots: Sendable {
    public struct Snapshot: Sendable, Identifiable, Hashable {
        public var id: String { name }
        public let name: String
        /// Date de l'instantané Time Machine, si le nom en contient une.
        public let date: Date?
        /// Instantané Time Machine (purgeable) ; sinon instantané du système (mise à jour).
        public var isTimeMachine: Bool { name.hasPrefix("com.apple.TimeMachine.") }
    }

    public init() {}

    /// Analyse la sortie de `tmutil listlocalsnapshots /`.
    public static func parse(_ text: String) -> [Snapshot] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
            .map { name in
                var date: Date?
                if name.hasPrefix("com.apple.TimeMachine.") {
                    let stamp = name.dropFirst("com.apple.TimeMachine.".count).replacingOccurrences(of: ".local", with: "")
                    date = formatter.date(from: stamp)
                }
                return Snapshot(name: name, date: date)
            }
    }

    public func list() async throws -> [Snapshot] {
        let data = try await ToolRunner.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        return Self.parse(String(decoding: data, as: UTF8.self))
    }
}

/// Espace du disque de démarrage, y compris ce que macOS peut libérer seul (« purgeable »).
public struct VolumeSpace: Sendable, Equatable {
    public let total: Int64
    /// Libre au sens strict.
    public let free: Int64
    /// Disponible pour un usage important (libre + purgeable).
    public let available: Int64

    /// Espace que macOS libère de lui-même au besoin (instantanés, caches du système, iCloud optimisé).
    public var purgeable: Int64 { max(0, available - free) }

    /// Nom affiché du disque de démarrage (« Macintosh HD » par défaut).
    public static var startupVolumeName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName ?? "Macintosh HD"
    }

    public static func current(path: String = "/") -> VolumeSpace? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return VolumeSpace(total: Int64(total), free: Int64(free), available: available)
    }
}

/// État de la mémoire vive.
public struct MemoryStatus: Sendable, Equatable {
    public enum Pressure: Int, Sendable {
        case normal = 1
        case warning = 2
        case critical = 4

        public var label: String {
            switch self {
            case .normal: "Normale"
            case .warning: "Tendue"
            case .critical: "Critique"
            }
        }
    }

    public let total: Int64
    /// Mémoire des applis (actives et inactives non purgeables).
    public let app: Int64
    public let wired: Int64
    public let compressed: Int64
    /// Fichiers en cache (récupérables tout de suite).
    public let cached: Int64
    public let free: Int64
    public let pressure: Pressure

    public var used: Int64 { app + wired + compressed }

    public static func current() -> MemoryStatus? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Int64(getpagesize())
        var total: Int64 = 0
        var length = MemoryLayout<Int64>.size
        sysctlbyname("hw.memsize", &total, &length, nil, 0)
        var level: Int32 = 1
        var levelLength = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelLength, nil, 0)
        let internalPages = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        return MemoryStatus(
            total: total,
            app: max(0, internalPages) * page,
            wired: Int64(stats.wire_count) * page,
            compressed: Int64(stats.compressor_page_count) * page,
            cached: (Int64(stats.external_page_count) + Int64(stats.purgeable_count)) * page,
            free: Int64(stats.free_count) * page,
            pressure: Pressure(rawValue: Int(level)) ?? .normal)
    }
}

/// Un processus et la mémoire qu'il occupe.
public struct ProcessMemory: Sendable, Identifiable, Hashable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    /// Empreinte mémoire (comme le Moniteur d'activité).
    public let footprint: Int64
}

public enum ProcessList {
    /// Processus de l'utilisateur les plus gourmands en mémoire.
    public static func topMemory(limit: Int = 12) -> [ProcessMemory] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard filled > 0 else { return [] }
        let uid = getuid()
        var result: [ProcessMemory] = []
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var info = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize, info.pbi_uid == uid else { continue }
            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) == 0
                }
            }
            guard ok else { continue }
            var nameBuffer = [CChar](repeating: 0, count: 1024)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            result.append(ProcessMemory(pid: pid, name: name.isEmpty ? "Processus \(pid)" : name,
                                        footprint: Int64(usage.ri_phys_footprint)))
        }
        return Array(result.sorted { $0.footprint > $1.footprint }.prefix(limit))
    }
}

/// Tâches de maintenance qui ne demandent pas les droits administrateur.
public enum UserMaintenance {
    public static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Reconstruit la base des services de lancement (« Ouvrir avec », icônes, applis par défaut).
    public static func rebuildLaunchServices() async throws {
        _ = try await ToolRunner.run(lsregister, ["-r", "-domain", "local", "-domain", "system", "-domain", "user"],
                                 timeout: 900)
    }
}
