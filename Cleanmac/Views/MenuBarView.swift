import AppKit
import CleanmacCore
import SwiftUI

/// Fenêtre de la barre des menus : espace libre, mémoire, accès rapide.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var space = VolumeSpace.current()
    @State private var memory = MemoryStatus.current()
    @AppStorage(ComfortKeys.thresholdGB) private var threshold = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles")
                Text("Cleanmac").font(.headline)
                Spacer()
            }
            if let space, space.total > 0 {
                let low = space.available < Int64(threshold) * 1_000_000_000
                gauge(title: "Macintosh HD",
                      value: "\(Bytes.text(space.available)) disponibles",
                      fraction: 1 - Double(space.available) / Double(space.total),
                      color: low ? .orange : .teal)
                if space.purgeable > 0 {
                    Text("dont \(Bytes.text(space.purgeable)) purgeables par macOS")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if low {
                    Label("Moins de \(threshold) Go disponibles", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if let memory, memory.total > 0 {
                gauge(title: "Mémoire vive",
                      value: "\(Bytes.text(memory.used)) sur \(Bytes.text(memory.total)) — \(memory.pressure.label.lowercased())",
                      fraction: Double(memory.used) / Double(memory.total),
                      color: memory.pressure == .normal ? .green : memory.pressure == .warning ? .yellow : .red)
            }
            if model.totalFreed > 0 {
                Text("Libéré avec Cleanmac : \(Bytes.text(model.totalFreed))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Button {
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Label("Ouvrir Cleanmac", systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsLink {
                Label("Réglages…", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quitter Cleanmac", systemImage: "power").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 15))
        .padding(16)
        .frame(width: 320)
        .task {
            while !Task.isCancelled {
                space = VolumeSpace.current()
                memory = MemoryStatus.current()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func gauge(title: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(value).font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(color)
        }
        .accessibilityElement(children: .combine)
    }
}
