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
                scanCard
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cleanmac — fondations")
                .font(.largeTitle.bold())
            Text("Version \(appVersion). Écran de contrôle provisoire : le scan est en lecture seule, rien n'est supprimé.")
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
        Card(title: "Scan (lecture seule)", symbol: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if model.isScanning {
                        Button("Annuler", role: .cancel) { model.cancelScan() }
                    } else {
                        Button("Lancer le scan") { model.startScan() }
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
            ScanResultList(result: result, rules: model.rules)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

/// Résultats regroupés par règle (aperçu, sans nettoyage).
struct ScanResultList: View {
    let result: ScanResult
    let rules: RuleBook?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(Bytes.text(result.totalBytes)) trouvés, dont \(Bytes.text(result.selectedByDefaultBytes)) cochés par défaut")
                .font(.title2.bold())
            Text("\(result.items.count) éléments, \(result.skipped.count) protégés, \(result.unreadableCount) illisibles — \(result.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))")
                .foregroundStyle(.secondary)

            ForEach(rules?.rules ?? []) { rule in
                let items = result.items(forRule: rule.id)
                if !items.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(items.sorted { $0.allocatedBytes > $1.allocatedBytes }.prefix(50)) { item in
                                HStack {
                                    Image(systemName: item.isSelectedByDefault ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(item.isSelectedByDefault ? Color.accentColor : .secondary)
                                    Text(item.name).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(Bytes.text(item.allocatedBytes)).monospacedDigit()
                                }
                                .help(item.path)
                            }
                            if items.count > 50 {
                                Text("… et \(items.count - 50) autres").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    } label: {
                        HStack {
                            Text(rule.name).font(.title3)
                            Text(rule.risk.label)
                                .font(.callout)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(rule.risk == .safe ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
                            Spacer()
                            Text(Bytes.text(items.reduce(0) { $0 + $1.allocatedBytes }))
                                .font(.title3.monospacedDigit())
                        }
                    }
                }
            }
        }
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
