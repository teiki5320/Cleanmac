import AppKit
import CleanmacCore
import SwiftUI

/// Résultats du scan, regroupés par catégorie puis par règle, avec cases à cocher.
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let result: ScanResult
    @State private var showReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(Bytes.text(result.totalBytes)) trouvés")
                .font(.title.bold())
            Text("\(result.items.count) éléments, \(result.skipped.count) protégés, \(result.unreadableCount) illisibles — \(result.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))")
                .foregroundStyle(.secondary)
            ForEach(result.sourceErrors, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }

            ForEach(RuleCategory.allCases, id: \.self) { category in
                let rules = (model.rules?.rules(in: category) ?? []).filter { !result.items(forRule: $0.id).isEmpty }
                if !rules.isEmpty {
                    let bytes = rules.flatMap { result.items(forRule: $0.id) }.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                    HStack {
                        Text(category.title).font(.title2.weight(.semibold))
                        Spacer()
                        Text(Bytes.text(bytes)).font(.title2.monospacedDigit())
                    }
                    .padding(.top, 8)
                    ForEach(rules) { rule in
                        RuleGroup(rule: rule, items: result.items(forRule: rule.id))
                    }
                }
            }

            selectionBar
        }
        .sheet(isPresented: $showReview) {
            ReviewSheet()
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text("\(model.selectedItems.count) éléments cochés")
                    .font(.title3)
                Text(Bytes.text(model.selectedBytes))
                    .font(.title.bold().monospacedDigit())
            }
            Spacer()
            Button("Vérifier et nettoyer…") { showReview = true }
                .keyboardShortcut(.defaultAction)
                .controlSize(.extraLarge)
                .disabled(model.selectedItems.isEmpty || model.isCleaning)
        }
        .padding(18)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 8)
    }
}

/// Une règle et ses éléments.
struct RuleGroup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rule: Rule
    let items: [ScanItem]
    @State private var expanded = false

    private var sorted: [ScanItem] { items.sorted { $0.allocatedBytes > $1.allocatedBytes } }
    private var cleanable: [ScanItem] { items.filter(model.canClean) }
    private var selectedCount: Int { items.filter(model.isSelected).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    model.setSelected(items, selectedCount < cleanable.count)
                } label: {
                    Image(systemName: checkboxSymbol)
                        .font(.title2)
                        .foregroundStyle(cleanable.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(cleanable.isEmpty)
                .accessibilityLabel("Tout cocher pour \(rule.name)")

                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                        Text(rule.name).font(.title3.weight(.medium))
                        RiskBadge(risk: rule.risk)
                        Spacer()
                        Text("\(items.count)").foregroundStyle(.secondary)
                        Text(Bytes.text(items.reduce(0) { $0 + $1.allocatedBytes }))
                            .font(.title3.monospacedDigit())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if expanded {
                Text(rule.explanation)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
                if cleanable.isEmpty {
                    Label("Ces éléments ne peuvent pas aller à la Corbeille : activez la suppression définitive dans les réglages pour pouvoir les supprimer.",
                          systemImage: "info.circle")
                        .foregroundStyle(.orange)
                        .padding(.leading, 40)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sorted.prefix(100)) { item in
                        ItemRow(item: item)
                    }
                    if items.count > 100 {
                        Text("… et \(items.count - 100) autres").foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var checkboxSymbol: String {
        if selectedCount == 0 { return "square" }
        return selectedCount == cleanable.count ? "checkmark.square.fill" : "minus.square.fill"
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: ScanItem

    var body: some View {
        Button { model.toggle(item) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: model.isSelected(item) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(model.canClean(item) ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if let detail = item.detail {
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(Bytes.text(item.allocatedBytes)).monospacedDigit()
            }
            .font(.body)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canClean(item))
        .help(item.isExternal ? item.name : item.path)
        .contextMenu {
            if !item.isExternal {
                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                }
            }
        }
    }
}

struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Text(risk.label)
            .font(.callout)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(risk == .safe ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
    }
}

/// Écran de vérification obligatoire avant tout nettoyage.
struct ReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch model.cleanState {
            case let .cleaning(done, total):
                Text("Nettoyage en cours…").font(.title.bold())
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("\(done) sur \(total)").monospacedDigit().foregroundStyle(.secondary)
            case let .finished(entry):
                finished(entry)
            case let .failed(message):
                Text("Le nettoyage a échoué").font(.title.bold())
                Text(message).foregroundStyle(.red)
                Button("Fermer") { model.dismissCleanResult(); dismiss() }
            case .idle:
                review
            }
        }
        .padding(28)
        .frame(width: 680)
        .frame(minHeight: 420)
        .controlSize(.large)
    }

    private var trashItems: [ScanItem] { model.selectedItems.filter { model.method(for: $0) == .trash } }
    private var permanentItems: [ScanItem] { model.selectedItems.filter { model.method(for: $0) == .permanent } }

    private var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Vérification avant nettoyage").font(.title.bold())
            Text(Bytes.text(model.selectedBytes))
                .font(.system(size: 44, weight: .bold).monospacedDigit())

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !trashItems.isEmpty {
                        section("Mis à la Corbeille", symbol: "trash", items: trashItems)
                    }
                    if !permanentItems.isEmpty {
                        section("Supprimés définitivement", symbol: "xmark.bin", items: permanentItems)
                    }
                }
            }
            .frame(maxHeight: 320)

            if !trashItems.isEmpty {
                Label("L'espace des éléments mis à la Corbeille n'est libéré qu'une fois la Corbeille vidée.",
                      systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Nettoyer \(Bytes.text(model.selectedBytes))") { model.cleanSelection() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.extraLarge)
            }
        }
    }

    private func section(_ title: String, symbol: String, items: [ScanItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(title) — \(items.count) éléments, \(Bytes.text(items.reduce(0) { $0 + $1.allocatedBytes }))",
                  systemImage: symbol)
                .font(.title3.weight(.semibold))
            ForEach(items.sorted { $0.allocatedBytes > $1.allocatedBytes }.prefix(30)) { item in
                HStack {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(Bytes.text(item.allocatedBytes)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if items.count > 30 {
                Text("… et \(items.count - 30) autres").foregroundStyle(.secondary)
            }
        }
    }

    private func finished(_ entry: JournalEntry) -> some View {
        let failures = entry.items.filter { !$0.succeeded }
        let trashed = entry.items.filter { $0.succeeded && $0.method == .trash }
        return VStack(alignment: .leading, spacing: 16) {
            Label("Nettoyage terminé", systemImage: "checkmark.circle.fill")
                .font(.title.bold())
                .foregroundStyle(.green)
            Text(Bytes.text(entry.freedBytes))
                .font(.system(size: 44, weight: .bold).monospacedDigit())
            if !trashed.isEmpty {
                Text("\(trashed.count) éléments sont dans la Corbeille. Videz-la pour libérer l'espace sur le disque.")
                    .font(.title3)
            }
            if !failures.isEmpty {
                Text("\(failures.count) éléments n'ont pas été supprimés :").font(.title3.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(failures, id: \.path) { item in
                            Text("\((item.path as NSString).lastPathComponent) — \(item.message ?? "erreur")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            HStack {
                if !trashed.isEmpty {
                    Button("Ouvrir la Corbeille") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
                    }
                }
                Spacer()
                Button("Fermer") { model.dismissCleanResult(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
