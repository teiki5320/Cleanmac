import AppKit
import CleanmacCore
import SwiftUI

/// Historique des nettoyages : chaque opération, le total libéré, et les éléments en détail.
struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<UUID> = []

    var body: some View {
        let entries = Array(model.journalEntries.reversed())
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(
                symbol: "clock.arrow.circlepath",
                title: "Historique",
                subtitle: entries.isEmpty ? "Aucun nettoyage pour l'instant"
                    : "\(plural(entries.count, "nettoyage")) — \(Bytes.text(model.totalReleased)) libérés tout de suite, \(Bytes.text(model.totalTrashed)) mis à la Corbeille")
            if let message = model.restoreMessage {
                Label(message, systemImage: "arrow.uturn.backward.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
            }
            if entries.isEmpty {
                EmptyStatePanel(symbol: "tray", title: "Rien encore",
                                detail: "Chaque nettoyage, désinstallation ou libération iCloud apparaîtra ici, avec la date, les éléments et la place libérée.")
            } else {
                summary(entries)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(entries) { entry in
                            EntryCard(entry: entry, rules: model.rules, expanded: expanded.contains(entry.id)) {
                                if expanded.contains(entry.id) { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .moduleScreenPadding()
        .padding(.bottom, -110)
    }

    private func summary(_ entries: [JournalEntry]) -> some View {
        let items = entries.flatMap(\.items).filter(\.succeeded)
        let trashed = entries.reduce(Int64(0)) { $0 + $1.trashedBytes }
        let permanent = items.filter { $0.method == .permanent }.reduce(Int64(0)) { $0 + $1.bytes }
        let evicted = items.filter { $0.method == .evicted }.reduce(Int64(0)) { $0 + $1.bytes }
        return HStack(spacing: 14) {
            stat("Mis à la Corbeille", trashed, "trash")
            stat("Supprimé définitivement", permanent, "xmark.bin")
            stat("Libéré d'iCloud", evicted, "icloud.and.arrow.up")
        }
    }

    private func stat(_ title: String, _ bytes: Int64, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.75))
            Text(Bytes.text(bytes))
                .font(.system(size: 26, weight: .bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(padding: 14)
    }
}

private struct EntryCard: View {
    let entry: JournalEntry
    let rules: RuleBook?
    let expanded: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let done = entry.items.filter(\.succeeded)
        let failed = entry.items.count - done.count
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date.formatted(date: .complete, time: .shortened).capitalizedFirst)
                            .font(.system(size: 18, weight: .semibold))
                        Text(summaryLine(done: done, failed: failed))
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Text(Bytes.text(entry.freedBytes))
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Masquer le détail" : "Afficher le détail")

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                        ItemLine(item: item, ruleName: rules?.rule(id: item.ruleID)?.name)
                    }
                }
                .padding(.leading, 32)
            }
        }
        .glassPanel(padding: 16)
    }

    private func summaryLine(done: [JournalItem], failed: Int) -> String {
        var parts = [plural(done.count, "élément")]
        let methods = Set(done.map(\.method))
        if methods.count == 1, let method = methods.first { parts.append(method.label.lowercased()) }
        if failed > 0 { parts.append("\(failed) non traité\(failed > 1 ? "s" : "")") }
        return parts.joined(separator: " — ")
    }
}

private struct ItemLine: View {
    @Environment(AppModel.self) private var model
    let item: JournalItem
    let ruleName: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.succeeded ? symbol : "xmark.circle")
                .foregroundStyle(item.succeeded ? .white.opacity(0.8) : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(DisplayPath.short(item.path))
                    .font(.system(size: 15))
                    .lineLimit(1).truncationMode(.head)
                Text(([ruleName, item.succeeded ? item.method.label : item.message].compactMap { $0 }).joined(separator: " — "))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer()
            Text(Bytes.text(item.bytes)).font(.system(size: 14).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            if let trashed = item.trashedPath, FileManager.default.fileExists(atPath: trashed) {
                if model.canRestore(item) {
                    Button("Remettre en place") { model.restore(item) }
                        .controlSize(.large)
                        .accessibilityLabel("Remettre en place \(DisplayPath.short(item.path))")
                }
                FinderButton(path: trashed, title: "Afficher dans la Corbeille")
            }
        }
        .help(item.path)
    }

    private var symbol: String {
        switch item.method {
        case .trash: "trash"
        case .permanent: "xmark.bin"
        case .evicted: "icloud.and.arrow.up"
        case .restored: "arrow.uturn.backward"
        }
    }
}
