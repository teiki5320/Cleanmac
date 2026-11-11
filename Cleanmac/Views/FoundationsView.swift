import AppKit
import CleanmacCore
import SwiftUI

/// Écran provisoire de la Phase 0 : état des fondations et scan en lecture seule.
/// Sera remplacé par la fenêtre principale à la Phase 1 (design).
struct FoundationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                accessCard
                helperCard
                rulesCard
                settingsCard
                scanCard
                journalCard
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cleanmac")
                .font(.largeTitle.bold())
            Text("Version \(appVersion). Écran provisoire, en attendant le design de la Phase 1. Rien n'est supprimé sans passer par l'écran de vérification.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Accès complet au disque

    private var accessCard: some View {
        Card(title: "Accès complet au disque", symbol: "lock.shield") {
            HStack {
                StatusBadge(ok: model.fullDiskAccess == .granted,
                            text: model.fullDiskAccess == .granted ? "Accordé" : "Non accordé")
                Spacer()
                if model.fullDiskAccess != .granted {
                    Button("Ouvrir les réglages") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                }
                Button("Vérifier") { model.refreshFullDiskAccess() }
            }
        }
    }

    // MARK: Outil d'aide

    private var helperCard: some View {
        let helper = model.helper
        return Card(title: "Outil d'aide (droits administrateur)", symbol: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatusBadge(ok: helper.status == .enabled, text: helper.statusLabel)
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
                Text("Commandes autorisées : " + HelperCommand.allCases.map(\.label).joined(separator: ", ") + ".")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Règles

    private var rulesCard: some View {
        Card(title: "Base de règles", symbol: "list.bullet.rectangle") {
            if let rules = model.rules {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(rules.rules.count) règles chargées")
                        .font(.title3.weight(.semibold))
                    ForEach(RuleCategory.allCases, id: \.self) { category in
                        let list = rules.rules(in: category)
                        if !list.isEmpty {
                            Text("\(category.title) : \(list.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                StatusBadge(ok: false, text: model.rulesError ?? "Règles non chargées")
            }
        }
    }

    // MARK: Scan

    private var scanCard: some View {
        Card(title: "Analyse et nettoyage", symbol: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if model.isScanning {
                        Button("Annuler", role: .cancel) { model.cancelScan() }
                    } else {
                        Button(model.scanResult == nil ? "Lancer l'analyse" : "Relancer l'analyse") { model.startScan() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.rules == nil)
                    }
                    Spacer()
                }
                scanStatus
            }
        }
    }

    @ViewBuilder
    private var scanStatus: some View {
        switch model.scanState {
        case .idle:
            Text("Aucun scan lancé.").foregroundStyle(.secondary)
        case let .scanning(progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress?.fractionCompleted ?? 0)
                if let progress {
                    Text("\(progress.currentRuleName) — \(progress.filesVisited.formatted()) fichiers, \(Bytes.text(progress.bytesFound))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        case .cancelled:
            Text("Scan annulé.").foregroundStyle(.orange)
        case let .failed(message):
            Text("Erreur : \(message)").foregroundStyle(.red)
        case let .finished(result):
            ResultsView(result: result)
        }
    }

    // MARK: Réglages

    private var settingsCard: some View {
        @Bindable var model = model
        return Card(title: "Réglages", symbol: "gearshape") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $model.allowPermanentDeletion) {
                    Text("Supprimer définitivement les caches régénérables").font(.title3)
                }
                .toggleStyle(.switch)
                Text("Désactivé : tout va à la Corbeille. Activé : les caches que les applis recréent seules sont supprimés tout de suite (l'espace est libéré immédiatement), ainsi que les systèmes de simulateurs, retéléchargeables depuis Xcode. Le reste va toujours à la Corbeille.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Journal

    private var journalCard: some View {
        Card(title: "Journal des nettoyages", symbol: "clock.arrow.circlepath") {
            if model.journalEntries.isEmpty {
                Text("Aucun nettoyage pour l'instant.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total libéré : \(Bytes.text(model.journalEntries.reduce(0) { $0 + $1.freedBytes }))")
                        .font(.title3.weight(.semibold))
                    ForEach(model.journalEntries.reversed().prefix(10)) { entry in
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text("\(entry.items.filter(\.succeeded).count) éléments")
                                .foregroundStyle(.secondary)
                            Text(Bytes.text(entry.freedBytes)).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

// MARK: Petits composants provisoires

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.title2.weight(.semibold))
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .controlSize(.large)
    }
}

struct StatusBadge: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.title3)
            .foregroundStyle(ok ? .green : .orange)
    }
}

enum Bytes {
    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
