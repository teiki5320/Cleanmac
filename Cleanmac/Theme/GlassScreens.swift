import AppKit
import CleanmacCore
import SwiftUI

// Composants communs des écrans de résultats en style « verre » : en-tête, panneaux,
// cases à cocher larges (pilotage depuis l'iPad), écran de vérification et écran « terminé ».

enum Bytes {
    private static let french = Locale(identifier: "fr_FR")

    /// Taille lisible, toujours en unités françaises (« 1,2 Go », « 4 ko »).
    static func text(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 octet" }
        return bytes.formatted(.byteCount(style: .file).locale(french))
    }
}

/// Avancement d'un nettoyage, commun à tous les modules.
enum CleanPhase {
    case idle
    case cleaning(done: Int, total: Int)
    case finished(JournalEntry)
    case failed(String)

    var isRunning: Bool {
        if case .cleaning = self { return true }
        return false
    }
}

/// « 1 élément », « 3 éléments ».
func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
    count == 1 ? "1 \(singular)" : "\(count.formatted()) \(pluralForm ?? singular + "s")"
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// En-tête d'un écran de module : pastille, titre, sous-titre.
struct ScreenHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    init(symbol: String, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            GlassIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 34, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.72))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .foregroundStyle(.white)
    }
}

/// Panneau en verre (matériau translucide, liseré clair).
struct GlassPanelModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1))
    }
}

extension View {
    func glassPanel(padding: CGFloat = 18) -> some View {
        modifier(GlassPanelModifier(padding: padding))
    }

    /// Mise en page commune des écrans de résultats (place laissée au bouton rond en bas).
    func moduleScreenPadding() -> some View {
        self
            .foregroundStyle(.white)
            .padding(.top, 44)
            .padding(.horizontal, 32)
            .padding(.bottom, 150)
    }
}

/// Case à cocher large (44 pt), lisible et facile à toucher depuis l'iPad.
struct GlassCheckbox: View {
    enum State { case off, on, mixed, locked }
    let state: State
    var tint: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(state == .on || state == .mixed ? tint : .white.opacity(state == .locked ? 0.4 : 0.8))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .locked)
        .accessibilityLabel(label)
        .accessibilityValue(state == .on ? "coché" : state == .mixed ? "en partie coché" : "non coché")
    }

    private var symbol: String {
        switch state {
        case .off: "square"
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        case .locked: "lock.fill"
        }
    }
}

/// Petite étiquette colorée.
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.35)))
    }
}

/// Bouton principal d'un écran (large, coloré).
struct PrimaryActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 6)
        }
        .controlSize(.extraLarge)
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(!enabled)
    }
}

/// Message d'état vide (« Rien à nettoyer »).
struct EmptyStatePanel: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 26, weight: .semibold))
            Text(detail)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(padding: 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: Écran de vérification et écran « terminé »

struct ReviewLine: Identifiable {
    let id: String
    let name: String
    var detail: String?
    var bytes: Int64?
    var symbol: String?
}

struct ReviewSection: Identifiable {
    var id: String { title }
    let title: String
    let symbol: String
    let lines: [ReviewLine]
    var bytes: Int64 { lines.reduce(0) { $0 + ($1.bytes ?? 0) } }
}

/// Écran de vérification obligatoire avant tout nettoyage, au style verre du module.
/// Puis avancement, puis écran « terminé » avec l'espace libéré.
struct CleanReviewSheet: View {
    let palette: ModulePalette
    var title = "Vérification avant nettoyage"
    let totalBytes: Int64
    let sections: [ReviewSection]
    var notes: [String] = []
    /// Avertissement mis en avant (suppression définitive…).
    var warning: String?
    let confirmTitle: String
    let phase: CleanPhase
    var cleaningTitle = "Nettoyage en cours…"
    let onConfirm: () -> Void
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch phase {
            case let .cleaning(done, total):
                Text(cleaningTitle).font(.system(size: 28, weight: .bold))
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(palette.light)
                Text("\(done) sur \(total)").monospacedDigit().foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            case let .finished(entry):
                CleanFinishedView(entry: entry, palette: palette) { close() }
            case let .failed(message):
                Label("L'opération a échoué", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.orange)
                Text(message).font(.title3)
                Spacer(minLength: 0)
                HStack { Spacer(); Button("Fermer") { close() }.keyboardShortcut(.defaultAction) }
            case .idle:
                review
            }
        }
        .padding(30)
        .frame(width: 740)
        .frame(minHeight: 460)
        .foregroundStyle(.white)
        .background {
            ZStack {
                palette.background
                Color.black.opacity(0.25)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .tint(palette.light)
        .controlSize(.large)
        .interactiveDismissDisabled(phase.isRunning)
    }

    private func close() {
        onClose()
        dismiss()
    }

    private var count: Int { sections.reduce(0) { $0 + $1.lines.count } }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 28, weight: .bold))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Bytes.text(totalBytes))
                    .font(.system(size: 46, weight: .bold).monospacedDigit())
                Text(plural(count, "élément"))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections.filter { !$0.lines.isEmpty }) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Label("\(section.title) — \(plural(section.lines.count, "élément")), \(Bytes.text(section.bytes))",
                                  systemImage: section.symbol)
                                .font(.system(size: 17, weight: .semibold))
                            ForEach(section.lines.prefix(60)) { line in
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(line.name).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        if let bytes = line.bytes {
                                            Text(Bytes.text(bytes)).monospacedDigit().foregroundStyle(.white.opacity(0.65))
                                        }
                                    }
                                    if let detail = line.detail {
                                        Label(detail, systemImage: line.symbol ?? "info.circle")
                                            .font(.system(size: 13))
                                            .lineLimit(1).truncationMode(.head)
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                                .font(.system(size: 15))
                            }
                            if section.lines.count > 60 {
                                Text("… et \(section.lines.count - 60) autres").foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .padding(14)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.extraLarge)
                    .buttonStyle(.borderedProminent)
                    .disabled(count == 0)
            }
        }
    }
}

/// Écran « terminé » : coche animée, espace libéré, échecs éventuels.
struct CleanFinishedView: View {
    let entry: JournalEntry
    let palette: ModulePalette
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let done = entry.items.filter(\.succeeded)
        let failures = entry.items.filter { !$0.succeeded }
        let trashed = done.filter { $0.method == .trash }
        let evicted = done.filter { $0.method == .evicted }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.5), done.isEmpty ? .orange : palette.mid, palette.deep],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 50))
                        .frame(width: 84, height: 84)
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                    Image(systemName: done.isEmpty ? "exclamationmark" : "checkmark")
                        .font(.system(size: 38, weight: .bold))
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(done.isEmpty ? "Rien n'a été supprimé" : "C'est fait")
                        .font(.system(size: 28, weight: .bold))
                    Text(Bytes.text(entry.freedBytes) + (evicted.count == done.count && !done.isEmpty ? " libérés du Mac" : " traités"))
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.4).delay(0.1)) { appeared = true }
            }
            if !trashed.isEmpty {
                Text((trashed.count == 1 ? "1 élément est" : "\(trashed.count) éléments sont")
                     + " dans la Corbeille. Videz-la pour libérer l'espace (module Corbeilles).")
                    .font(.title3)
            }
            if !evicted.isEmpty {
                Text((evicted.count == 1 ? "1 fichier reste" : "\(evicted.count) fichiers restent")
                     + " dans iCloud et se retéléchargera à l'ouverture.")
                    .font(.title3)
            }
            if !failures.isEmpty {
                Text(failures.count == 1 ? "1 élément n'a pas été traité :" : "\(failures.count) éléments n'ont pas été traités :")
                    .font(.title3.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(failures, id: \.path) { item in
                            Text("\((item.path as NSString).lastPathComponent) — \(item.message ?? "erreur")")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            Spacer(minLength: 0)
            HStack {
                if !trashed.isEmpty {
                    Button("Ouvrir la Corbeille") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
                    }
                }
                Spacer()
                Button("Fermer", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
