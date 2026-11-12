import AppKit
import CleanmacCore
import ServiceManagement
import SwiftUI

/// Fenêtre des réglages (⌘,) : nettoyage, alertes et programmation, exclusions, accès et outil d'aide.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Nettoyage", systemImage: "trash") }
            ComfortSettings()
                .tabItem { Label("Alertes", systemImage: "bell") }
            ExclusionSettings()
                .tabItem { Label("Exclusions", systemImage: "hand.raised") }
            AccessSettings()
                .tabItem { Label("Accès", systemImage: "lock.shield") }
            AboutSettings()
                .tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 720, height: 560)
        .controlSize(.large)
    }
}

/// Une section de réglages : titre, contenu, explication.
private struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            content
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatusLabel: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.title3)
            .foregroundStyle(ok ? .green : .orange)
    }
}

// MARK: Nettoyage

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 16) {
                SettingsSection(
                    title: "Corbeille ou suppression définitive",
                    footer: "Désactivé : tout va à la Corbeille. Activé : seuls les caches que les applis recréent seules sont supprimés tout de suite (l'espace est libéré immédiatement), ainsi que les systèmes de simulateurs, retéléchargeables depuis Xcode. Le reste va toujours à la Corbeille. Vider une Corbeille (module Corbeilles) est toujours définitif, après vérification."
                ) {
                    Toggle("Supprimer définitivement les caches régénérables", isOn: $model.allowPermanentDeletion)
                        .toggleStyle(.switch)
                        .font(.title3)
                }
                SettingsSection(title: "Toujours vrai",
                                footer: nil) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Seuls les éléments « sûrs » sont cochés d'office.", systemImage: "checkmark.square")
                        Label("Un écran de vérification, avec la taille totale, précède chaque nettoyage.", systemImage: "list.bullet.rectangle")
                        Label("Bureau, Documents, Images, Messages, trousseaux, photothèque et dossiers git sont protégés d'office.", systemImage: "lock")
                        Label("Chaque nettoyage est noté dans l'Historique.", systemImage: "clock.arrow.circlepath")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }
}

// MARK: Alertes et programmation

private struct ComfortSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ComfortKeys.menuBar) private var showMenuBar = true
    @AppStorage(ComfortKeys.lowSpaceAlert) private var lowSpaceAlert = true
    @AppStorage(ComfortKeys.thresholdGB) private var threshold = 15
    @AppStorage(ComfortKeys.scheduled) private var scheduled = false

    var body: some View {
        let comfort = model.comfort
        ScrollView {
            VStack(spacing: 16) {
                SettingsSection(title: "Barre des menus",
                                footer: "Espace libre, mémoire vive et accès rapide à Cleanmac, en haut de l'écran.") {
                    Toggle("Afficher Cleanmac dans la barre des menus", isOn: $showMenuBar)
                        .toggleStyle(.switch)
                }
                SettingsSection(title: "Alerte d'espace disque",
                                footer: "Une notification, au plus une fois par jour, quand l'espace disponible passe sous le seuil.") {
                    Toggle("M'avertir quand le disque est presque plein", isOn: $lowSpaceAlert)
                        .toggleStyle(.switch)
                        .onChange(of: lowSpaceAlert) { _, on in if on { comfort.requestNotifications() } }
                    Stepper(value: $threshold, in: 5...100, step: 5) {
                        Text("Seuil : \(threshold) Go").monospacedDigit()
                    }
                    .disabled(!lowSpaceAlert)
                }
                SettingsSection(title: "Nettoyage programmé",
                                footer: "Chaque mois, Cleanmac analyse les seuls éléments « sûrs » et vous envoie une notification. Il ne supprime jamais rien seul : vous ouvrez Cleanmac, vérifiez, puis nettoyez. Cleanmac doit être ouvert (ou lancé à la connexion).") {
                    Toggle("Analyser chaque mois et me prévenir", isOn: $scheduled)
                        .toggleStyle(.switch)
                        .onChange(of: scheduled) { _, on in if on { comfort.requestNotifications() } }
                    if let last = comfort.lastScheduledDate {
                        Text("Dernière analyse : \(last.formatted(date: .long, time: .shortened)) — \(Bytes.text(comfort.lastScheduledBytes)) trouvés")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Toggle("Ouvrir Cleanmac à la connexion", isOn: Binding(
                            get: { comfort.launchAtLogin },
                            set: { comfort.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch)
                        Spacer()
                        Button("Analyser maintenant") {
                            Task { await comfort.runScheduledScan() }
                        }
                    }
                    if let message = comfort.loginMessage {
                        Text(message).foregroundStyle(.orange)
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: Exclusions

private struct ExclusionSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dossiers et fichiers exclus")
                .font(.title3.weight(.semibold))
            Text("Cleanmac ne propose ni ne supprime jamais rien dans ces emplacements, en plus des protections d'office (Bureau, Documents, Images, Messages, trousseaux, photothèque, iCloud Drive, dossiers git).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                if model.exclusions.isEmpty {
                    Text("Aucune exclusion.").foregroundStyle(.secondary)
                }
                ForEach(model.exclusions, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                        Text(DisplayPath.short(path)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Retirer") { model.removeExclusion(path) }
                    }
                    .font(.title3)
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 260)
            HStack {
                Spacer()
                Button("Ajouter un dossier ou un fichier…") { add() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .padding(20)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        panel.prompt = "Exclure"
        if panel.runModal() == .OK {
            for url in panel.urls { model.addExclusion(url.path) }
        }
    }
}

// MARK: Accès et outil d'aide

private struct AccessSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let helper = model.helper
        ScrollView {
            VStack(spacing: 16) {
                SettingsSection(title: "Accès complet au disque",
                                footer: "Nécessaire pour voir les caches, Mail, la Corbeille et les conteneurs des applis.") {
                    HStack {
                        StatusLabel(ok: model.fullDiskAccess == .granted,
                                    text: model.fullDiskAccess == .granted ? "Accordé" : "Non accordé")
                        Spacer()
                        if model.fullDiskAccess != .granted {
                            Button("Ouvrir les réglages") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                        }
                        Button("Vérifier") { model.refreshFullDiskAccess() }
                    }
                }
                SettingsSection(title: "Outil d'aide (droits administrateur)",
                                footer: "Sert uniquement à : " + HelperCommand.allCases.map(\.label).joined(separator: ", ") + ". Liste fermée, sans aucun paramètre venant de l'appli.") {
                    HStack {
                        StatusLabel(ok: helper.status == .enabled, text: helper.statusLabel)
                        if let version = helper.installedVersion {
                            Text("version \(version)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        switch helper.status {
                        case .enabled:
                            Button("Tester la connexion") { Task { await helper.ping() } }
                            Button("Désinstaller") { Task { await helper.uninstall() } }
                        case .requiresApproval:
                            Button("Ouvrir les réglages") { helper.openApprovalSettings() }
                            Button("Désinstaller") { Task { await helper.uninstall() } }
                        default:
                            Button("Installer") { helper.install() }
                        }
                    }
                    .disabled(helper.isBusy)
                    if let message = helper.message {
                        Text(message).foregroundStyle(.secondary)
                    }
                    if helper.status == .requiresApproval {
                        Text("Autorisez « Cleanmac » dans Réglages système › Général › Ouverture et extensions, puis revenez ici et cliquez sur « Tester la connexion ».")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: À propos

private struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 40))
                VStack(alignment: .leading) {
                    Text("Cleanmac").font(.largeTitle.bold())
                    Text("Version \(Self.version) — usage personnel").foregroundStyle(.secondary)
                }
            }
            if let rules = model.rules {
                SettingsSection(title: "Base de règles : \(rules.rules.count) règles") {
                    ForEach(RuleCategory.allCases, id: \.self) { category in
                        let count = rules.rules(in: category).count
                        if count > 0 {
                            Text("\(category.title) : \(count)").foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                StatusLabel(ok: false, text: model.rulesError ?? "Règles non chargées")
            }
            Text("Langue : français (seule langue de Cleanmac).")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
