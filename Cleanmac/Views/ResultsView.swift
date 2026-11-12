import AppKit
import CleanmacCore
import SwiftUI

/// Résultats du scan, regroupés par catégorie puis par règle, avec cases à cocher.
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let result: ScanResult
    let palette: ModulePalette
    @State private var showReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Bytes.text(result.totalBytes)) trouvés")
                    .font(.system(size: 30, weight: .bold))
                Spacer()
            }
            Text("\(plural(result.items.count, "élément")), \(plural(result.skipped.count, "protégé")), \(plural(result.unreadableCount, "illisible")) — \(result.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
            ForEach(result.sourceErrors, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if result.items.isEmpty {
                Label("Rien à nettoyer ici.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.vertical, 12)
            }

            ForEach(RuleCategory.allCases, id: \.self) { category in
                let rules = (model.rules?.rules(in: category) ?? []).filter { !result.items(forRule: $0.id).isEmpty }
                if !rules.isEmpty {
                    let bytes = rules.flatMap { result.items(forRule: $0.id) }.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                    HStack {
                        Text(category.title).font(.system(size: 22, weight: .semibold))
                        Spacer()
                        Text(Bytes.text(bytes)).font(.system(size: 22).monospacedDigit())
                    }
                    .padding(.top, 8)
                    ForEach(rules) { rule in
                        RuleGroup(rule: rule, items: result.items(forRule: rule.id), palette: palette)
                    }
                }
            }

            selectionBar
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showReview, onDismiss: { model.unfreezeSettings() }) {
            review.onAppear { model.freezeSettingsForReview() }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text(plural(model.selectedItems.count, "élément coché", "éléments cochés"))
                    .font(.title3)
                Text(Bytes.text(model.selectedBytes))
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
            }
            Spacer()
            PrimaryActionButton(title: "Vérifier et nettoyer…", symbol: "checkmark.shield", tint: palette.mid,
                                enabled: !model.selectedItems.isEmpty && !model.isCleaning) { showReview = true }
        }
        .padding(18)
        .background(palette.light.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 8)
    }

    private var review: some View {
        let items = model.selectedItems
        let trash = items.filter { model.method(for: $0) == .trash }
        let permanent = items.filter { model.method(for: $0) == .permanent }
        let emptiesTrash = permanent.contains { model.rule(for: $0)?.inTrash == true }
        func lines(_ list: [ScanItem]) -> [ReviewLine] {
            list.sorted { $0.allocatedBytes > $1.allocatedBytes }.map {
                ReviewLine(id: $0.path, name: $0.name,
                           detail: $0.isExternal ? model.rule(for: $0)?.name : DisplayPath.short($0.path),
                           bytes: $0.allocatedBytes, symbol: $0.isExternal ? "tag" : "folder")
            }
        }
        var notes: [String] = []
        if !trash.isEmpty {
            notes.append("L'espace des éléments mis à la Corbeille n'est libéré qu'une fois la Corbeille vidée.")
        }
        return CleanReviewSheet(
            palette: palette,
            totalBytes: model.selectedBytes,
            sections: [ReviewSection(title: "Mis à la Corbeille", symbol: "trash", lines: lines(trash)),
                       ReviewSection(title: "Supprimés définitivement", symbol: "xmark.bin", lines: lines(permanent))],
            notes: notes,
            warning: emptiesTrash ? "Vider une Corbeille est définitif : ces éléments ne seront plus récupérables."
                : permanent.isEmpty ? nil : "Les éléments « supprimés définitivement » ne passent pas par la Corbeille.",
            confirmTitle: (emptiesTrash ? "Vider définitivement " : "Nettoyer ") + Bytes.text(model.selectedBytes),
            phase: model.cleanState,
            onConfirm: { model.cleanSelection() },
            onClose: { model.dismissCleanResult() })
    }
}

/// Une règle et ses éléments.
struct RuleGroup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rule: Rule
    let items: [ScanItem]
    let palette: ModulePalette
    @State private var expanded = false

    private var sorted: [ScanItem] { items.sorted { $0.allocatedBytes > $1.allocatedBytes } }
    private var cleanable: [ScanItem] { items.filter(model.canClean) }
    private var selectedCount: Int { items.filter(model.isSelected).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GlassCheckbox(state: checkboxState, tint: palette.light, label: "Tout cocher pour \(rule.name)") {
                    model.setSelected(items, selectedCount < cleanable.count)
                }
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(rule.name).font(.system(size: 18, weight: .medium))
                        RiskBadge(risk: rule.risk)
                        if rule.inTrash { Pill(text: "définitif", color: .orange) }
                        Spacer()
                        Text(plural(items.count, "élément")).font(.system(size: 15)).foregroundStyle(.white.opacity(0.6))
                        Text(Bytes.text(items.reduce(0) { $0 + $1.allocatedBytes }))
                            .font(.system(size: 18).monospacedDigit())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Masquer les éléments" : "Afficher les éléments")
            }

            if expanded {
                Text(rule.explanation)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 52)
                if cleanable.isEmpty {
                    Label("Ces éléments ne peuvent pas aller à la Corbeille : activez la suppression définitive dans les réglages pour pouvoir les supprimer.",
                          systemImage: "info.circle")
                        .foregroundStyle(.orange)
                        .padding(.leading, 52)
                }
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sorted) { item in
                        ItemRow(item: item, palette: palette)
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var checkboxState: GlassCheckbox.State {
        if cleanable.isEmpty { return .locked }
        if selectedCount == 0 { return .off }
        return selectedCount == cleanable.count ? .on : .mixed
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: ScanItem
    let palette: ModulePalette

    var body: some View {
        HStack(spacing: 8) {
            GlassCheckbox(state: !model.canClean(item) ? .locked : model.isSelected(item) ? .on : .off,
                          tint: palette.light, label: item.name) { model.toggle(item) }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 16)).lineLimit(1).truncationMode(.middle)
                if let detail = item.detail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                if !item.isExternal {
                    Text(DisplayPath.short(item.path)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1).truncationMode(.head)
                }
            }
            Spacer()
            Text(Bytes.text(item.allocatedBytes)).font(.system(size: 15).monospacedDigit())
            if !item.isExternal {
                FinderButton(path: item.path)
            }
        }
        .help(item.isExternal ? item.name : item.path)
    }
}

struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Pill(text: risk.label, color: risk == .safe ? .green : .orange)
    }
}
