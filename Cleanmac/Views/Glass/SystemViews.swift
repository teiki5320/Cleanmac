import AppKit
import CleanmacCore
import SwiftUI

// MARK: Espace purgeable

/// Écran « Espace purgeable » : espace libre réel, ce que macOS peut libérer seul, instantanés locaux.
struct PurgeableScreen: View {
    @Environment(AppModel.self) private var app
    @State private var confirm = false

    var body: some View {
        let model = app.purgeable
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(symbol: Module.purgeable.symbol, title: "Espace purgeable",
                         subtitle: "Disque de démarrage — \(plural(model.snapshots.count, "instantané local", "instantanés locaux"))")
            if let space = model.space {
                HStack(spacing: 14) {
                    stat("Libre", space.free, "internaldrive", "Vraiment inoccupé.")
                    stat("Purgeable", space.purgeable, "sparkles", "macOS le libère seul quand la place manque.")
                    stat("Disponible", space.available, "checkmark.circle", "Libre + purgeable : ce que le Finder affiche.")
                }
                bar(space)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Instantanés locaux").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    PrimaryActionButton(title: model.purging ? "Purge en cours…" : "Purger les instantanés Time Machine",
                                        symbol: "trash", tint: Module.purgeable.palette.mid,
                                        enabled: !model.purging && model.timeMachineCount > 0 && app.helper.status == .enabled) { confirm = true }
                }
                if app.helper.status != .enabled {
                    HStack {
                        Label("La purge demande l'outil d'aide (droits administrateur) : \(app.helper.statusLabel.lowercased()).",
                              systemImage: "lock.shield")
                            .font(.system(size: 15))
                        Spacer()
                        if app.helper.status == .requiresApproval {
                            Button("Autoriser dans les réglages…") { app.helper.openApprovalSettings() }
                        } else {
                            Button("Installer l'outil d'aide") { app.helper.install() }
                        }
                    }
                    .controlSize(.large)
                }
                if model.timeMachineCount == 0 {
                    Text("Aucun instantané Time Machine : rien à purger. Ceux des mises à jour de macOS disparaissent seuls.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                }
                if let message = model.message {
                    Label(message, systemImage: "info.circle").foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.snapshots.isEmpty {
                    Text("Aucun instantané local.").foregroundStyle(.white.opacity(0.7))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.snapshots) { snapshot in
                                HStack(spacing: 10) {
                                    Image(systemName: snapshot.isTimeMachine ? "clock.arrow.circlepath" : "gearshape.2")
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(snapshot.isTimeMachine
                                             ? "Time Machine — \(snapshot.date?.formatted(date: .abbreviated, time: .shortened) ?? snapshot.name)"
                                             : "Mise à jour de macOS")
                                            .font(.system(size: 15, weight: .medium))
                                        Text(snapshot.isTimeMachine ? "Purgeable" : "Géré par macOS : supprimé seul après la mise à jour")
                                            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                Text("La taille d'un instantané n'est pas connue à l'avance : il ne garde que ce qui a changé depuis. Le purger ne touche pas à vos sauvegardes Time Machine sur disque externe.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassPanel()
            Spacer(minLength: 0)
        }
        .moduleScreenPadding()
        .confirmationDialog("Purger les instantanés Time Machine locaux ?", isPresented: $confirm) {
            Button("Purger") { model.purge() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les retours en arrière possibles depuis ces instantanés seront perdus. Vos sauvegardes sur disque externe ne sont pas touchées.")
        }
    }

    private func stat(_ title: String, _ bytes: Int64, _ symbol: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 15)).foregroundStyle(.white.opacity(0.8))
            Text(Bytes.text(bytes)).font(.system(size: 30, weight: .bold).monospacedDigit())
            Text(help).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(padding: 14)
    }

    private func bar(_ space: VolumeSpace) -> some View {
        GeometryReader { geo in
            let total = Double(max(space.total, 1))
            let used = Double(space.total - space.available) / total
            let purgeable = Double(space.purgeable) / total
            HStack(spacing: 0) {
                Rectangle().fill(Module.purgeable.palette.light).frame(width: geo.size.width * used)
                Rectangle().fill(Module.purgeable.palette.accent.opacity(0.8)).frame(width: geo.size.width * purgeable)
                Rectangle().fill(.white.opacity(0.15))
            }
            .clipShape(Capsule())
        }
        .frame(height: 14)
        .accessibilityLabel("Occupé \(Bytes.text(space.total - space.available)), purgeable \(Bytes.text(space.purgeable)), libre \(Bytes.text(space.free))")
    }
}

// MARK: Maintenance

/// Écran « Maintenance » : tâches du système et mémoire vive.
struct MaintenanceScreen: View {
    @Environment(AppModel.self) private var app
    @State private var pending: MaintenanceTask?

    var body: some View {
        let model = app.maintenance
        let helper = app.helper
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(symbol: Module.maintenance.symbol, title: Module.maintenance.title,
                             subtitle: "Outil d'aide : \(helper.statusLabel.lowercased())")
                if helper.status != .enabled {
                    HStack {
                        Label("Trois tâches demandent l'outil d'aide (droits administrateur).", systemImage: "lock.shield")
                            .font(.system(size: 15))
                        Spacer()
                        if helper.status == .requiresApproval {
                            Button("Autoriser dans les réglages…") { helper.openApprovalSettings() }
                        } else {
                            Button("Installer l'outil d'aide") { helper.install() }
                        }
                    }
                    .controlSize(.large)
                    .glassPanel(padding: 14)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(MaintenanceTask.allCases) { task in taskCard(task, model: model) }
                }
                memoryPanel(model)
            }
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .padding(.top, 44)
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .task {
            while !Task.isCancelled {
                model.refreshMemory()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Lancer") { if let task = pending { model.run(task) }; pending = nil }
            Button("Annuler", role: .cancel) { pending = nil }
        } message: {
            Text(pending?.detail ?? "")
        }
    }

    private func taskCard(_ task: MaintenanceTask, model: MaintenanceModel) -> some View {
        let state = model.state(task)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                GlassIcon(symbol: task.symbol)
                Text(task.title).font(.system(size: 18, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(task.detail).font(.system(size: 14)).foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                switch state {
                case .idle: EmptyView()
                case .running: ProgressView().controlSize(.small)
                case let .done(message): Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case let .failed(message): Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        .lineLimit(3)
                }
                Spacer()
                Button(state == .running ? "En cours…" : "Lancer") {
                    if task.needsConfirmation { pending = task } else { model.run(task) }
                }
                .accessibilityLabel("Lancer : \(task.title)")
                .controlSize(.large)
                .disabled(state == .running)
            }
            if task.helperCommand != nil {
                Text("Demande l'outil d'aide").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .glassPanel(padding: 16)
    }

    private func memoryPanel(_ model: MaintenanceModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mémoire vive").font(.system(size: 20, weight: .semibold))
                Spacer()
                if let memory = model.memory {
                    Pill(text: "Pression : \(memory.pressure.label.lowercased())",
                         color: memory.pressure == .normal ? .green : memory.pressure == .warning ? .yellow : .red)
                }
            }
            if let memory = model.memory, memory.total > 0 {
                GeometryReader { geo in
                    let total = Double(memory.total)
                    HStack(spacing: 0) {
                        Rectangle().fill(ThemeColors.memoryApps).frame(width: geo.size.width * Double(memory.app) / total)
                        Rectangle().fill(ThemeColors.memoryWired).frame(width: geo.size.width * Double(memory.wired) / total)
                        Rectangle().fill(ThemeColors.memoryCompressed).frame(width: geo.size.width * Double(memory.compressed) / total)
                        Rectangle().fill(ThemeColors.memoryCached).frame(width: geo.size.width * Double(memory.cached) / total)
                        Rectangle().fill(.white.opacity(0.08))
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 14)
                HStack(spacing: 18) {
                    legend("Applis", memory.app, ThemeColors.memoryApps)
                    legend("Système", memory.wired, ThemeColors.memoryWired)
                    legend("Compressée", memory.compressed, ThemeColors.memoryCompressed)
                    legend("Fichiers en cache", memory.cached, ThemeColors.memoryCached)
                    Spacer()
                    Text("\(Bytes.text(memory.used)) utilisés sur \(Bytes.text(memory.total))")
                        .font(.system(size: 14).monospacedDigit())
                }
            }
            Text("Les plus gourmands").font(.system(size: 16, weight: .semibold)).padding(.top, 4)
            ForEach(model.processes) { process in
                HStack(spacing: 10) {
                    if let running = model.runningApp(process), let icon = running.icon {
                        Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "gearshape").frame(width: 26, height: 26)
                    }
                    Text(model.displayName(process)).font(.system(size: 15)).lineLimit(1)
                    Spacer()
                    Text(Bytes.text(process.footprint)).font(.system(size: 15, weight: .semibold).monospacedDigit())
                    if model.runningApp(process) != nil {
                        Button("Quitter") { model.quit(process) }
                            .accessibilityLabel("Quitter \(model.displayName(process))")
                            .help("Demande à l'appli de se fermer (elle peut proposer d'enregistrer)")
                    } else {
                        Color.clear.frame(width: 64, height: 1)
                    }
                }
                .controlSize(.large)
            }
        }
        .glassPanel()
    }

    private func legend(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text("\(title) \(Bytes.text(bytes))").font(.system(size: 13).monospacedDigit())
        }
    }
}
