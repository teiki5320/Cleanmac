import CleanmacCore
import Foundation
import Observation
import ServiceManagement
@preconcurrency import UserNotifications

/// Clés des réglages de confort (UserDefaults / @AppStorage).
enum ComfortKeys {
    static let menuBar = "barreDesMenus"
    static let lowSpaceAlert = "alerteEspace"
    static let thresholdGB = "seuilAlerteGo"
    static let scheduled = "nettoyageProgramme"
    static let lastScheduled = "derniereAnalyseProgrammee"
    static let lastScheduledBytes = "derniereAnalyseProgrammeeOctets"
    static let lastLowSpaceAlert = "derniereAlerteEspace"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [menuBar: true, lowSpaceAlert: true, thresholdGB: 15, scheduled: false])
    }
}

/// Alerte d'espace disque et analyse programmée (chaque mois, éléments « sûrs » seulement).
/// Ne nettoie jamais rien tout seul : une notification invite à ouvrir Cleanmac pour vérifier.
@MainActor
@Observable
final class ComfortService {
    var rules: () -> RuleBook? = { nil }
    var exclusions: () -> [String] = { [] }
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginMessage: String?
    private var loop: Task<Void, Never>?
    private let notificationDelegate = NotificationDelegate()
    private var defaults: UserDefaults { .standard }

    static let scheduleInterval: TimeInterval = 30 * 86_400

    /// Les notifications exigent un vrai paquet d'appli (pas un exécutable isolé).
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        guard loop == nil, canNotify else { return }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        loop = Task {
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await check()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    var lastScheduledDate: Date? {
        let value = defaults.double(forKey: ComfortKeys.lastScheduled)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    var lastScheduledBytes: Int64 { Int64(defaults.double(forKey: ComfortKeys.lastScheduledBytes)) }

    var nextScheduledDate: Date? {
        guard defaults.bool(forKey: ComfortKeys.scheduled) else { return nil }
        return (lastScheduledDate ?? Date()).addingTimeInterval(lastScheduledDate == nil ? 0 : Self.scheduleInterval)
    }

    func check() async {
        checkLowSpace()
        if defaults.bool(forKey: ComfortKeys.scheduled) {
            let last = lastScheduledDate ?? .distantPast
            if Date().timeIntervalSince(last) >= Self.scheduleInterval { await runScheduledScan() }
        }
    }

    /// Notification si l'espace libre passe sous le seuil (au plus une fois par jour).
    func checkLowSpace() {
        guard defaults.bool(forKey: ComfortKeys.lowSpaceAlert), let space = VolumeSpace.current() else { return }
        let threshold = Int64(max(1, defaults.integer(forKey: ComfortKeys.thresholdGB))) * 1_000_000_000
        guard space.available < threshold else { return }
        let last = defaults.double(forKey: ComfortKeys.lastLowSpaceAlert)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: ComfortKeys.lastLowSpaceAlert)
        notify(id: "espace", title: "Disque presque plein",
               body: "Il ne reste que \(Bytes.text(space.available)) sur Macintosh HD. Ouvrez Cleanmac pour faire de la place.")
    }

    /// Analyse des seules règles « sûres », sans rien supprimer.
    func runScheduledScan() async {
        guard let rules = rules() else { return }
        let safe = rules.rules.filter { $0.risk == .safe && $0.check == nil && $0.source == nil && !$0.inTrash }
        let policy = ProtectionPolicy(userExclusions: exclusions())
        guard let result = try? await Scanner(policy: policy).scan(rules: safe) else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: ComfortKeys.lastScheduled)
        defaults.set(Double(result.totalBytes), forKey: ComfortKeys.lastScheduledBytes)
        guard result.totalBytes > 100_000_000 else { return }
        notify(id: "programme", title: "Nettoyage du mois",
               body: "\(Bytes.text(result.totalBytes)) d'éléments sûrs peuvent être nettoyés. Ouvrez Cleanmac pour vérifier avant de nettoyer.")
    }

    func requestNotifications() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(id: String, title: String, body: String) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: Ouverture à la connexion

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
        } catch {
            loginMessage = "Impossible : \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Affiche les notifications même quand Cleanmac est au premier plan.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
