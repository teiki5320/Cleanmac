import AppKit
import CleanmacCore
import ServiceManagement
import SwiftUI

/// Écran Applications : désinstaller, restes, démarrage, mises à jour.
struct AppsScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.apps
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(symbol: "square.grid.2x2", title: "Applications", subtitle: subtitle(model))
            Picker("Onglet", selection: $model.tab) {
                ForEach(AppsModel.Tab.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.extraLarge)
            .frame(maxWidth: 640)
            switch model.tab {
            case .uninstall: UninstallTab(model: model)
            case .leftovers: LeftoversTab(model: model)
            case .startup: StartupTab(model: model)
            case .updates: UpdatesTab(model: model)
            }
        }
        .moduleScreenPadding()
    }

    private func subtitle(_ model: AppsModel) -> String {
        switch model.tab {
        case .uninstall: "\(plural(model.apps.count, "appli")) dans /Applications et ~/Applications"
        case .leftovers: model.leftovers.isEmpty ? "Aucun reste repéré"
            : "\(plural(model.leftovers.count, "appli supprimée", "applis supprimées")), \(Bytes.text(model.leftovers.reduce(0) { $0 + $1.totalBytes }))"
        case .startup: model.launchItems.count == 1 ? "1 élément lancé par macOS" : "\(model.launchItems.count) éléments lancés par macOS"
        case .updates: model.updatesPhase != .done ? "Sparkle et Homebrew"
            : model.updates.count == 1 ? "1 mise à jour disponible" : "\(model.updates.count) mises à jour disponibles"
        }
    }
}

// MARK: Désinstaller

private struct UninstallTab: View {
    let model: AppsModel
    @State private var search = ""
    @State private var showReview = false

    private var shown: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.apps }
        return model.apps.filter { $0.displayName.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                TextField("Rechercher une appli", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(shown) { app in appRow(app) }
                    }
                    .padding(6)
                }
            }
            .frame(width: 320)
            .glassPanel(padding: 10)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassPanel()
        }
        .sheet(isPresented: $showReview) { review }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let selected = model.chosen == app
        return Button { model.choose(app) } label: {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.displayName).font(.system(size: 16, weight: selected ? .semibold : .regular)).lineLimit(1)
                    Text(app.version.map { "version \($0)" } ?? app.bundleID)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(model.sizes[app.path].map(Bytes.text) ?? "…")
                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(selected ? .white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.chosen {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.displayName).font(.system(size: 24, weight: .semibold))
                        Text([app.version.map { "Version \($0)" }, app.bundleID, app.isAppStore ? "App Store" : nil]
                            .compactMap { $0 }.joined(separator: " — "))
                            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    FinderButton(path: app.path)
                }
                if let reason = model.blockReason(app) {
                    Label(reason, systemImage: "lock.fill").foregroundStyle(.orange)
                } else if model.isRunning(app) {
                    Label("\(app.displayName) est ouverte : quittez-la avant de la désinstaller.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let files = model.chosenFiles {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(files) { file in fileRow(file) }
                        }
                    }
                    let count = model.selectedAppFiles.count
                    let bytes = model.selectedAppFiles.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                    HStack {
                        Text("Les données (« à vérifier ») ne sont pas cochées d'office.")
                            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        PrimaryActionButton(
                            title: count == 0 ? "Rien de coché" : "Désinstaller… \(Bytes.text(bytes))",
                            symbol: "trash", tint: Module.applications.palette.mid,
                            enabled: count > 0 && !model.isRunning(app)
                        ) { showReview = true }
                    }
                } else if model.blockReason(app) == nil {
                    ProgressView("Recherche des fichiers de l'appli…").controlSize(.large)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Choisissez une appli à gauche", systemImage: "hand.point.left")
                    .font(.system(size: 22, weight: .semibold))
                Text("Cleanmac retrouve l'appli et ses fichiers (préférences, caches, données, conteneurs). Vous cochez ce qui part ; tout va à la Corbeille.")
                    .font(.system(size: 16)).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fileRow(_ file: AppFile) -> some View {
        let selected = model.fileSelection.contains(file.path)
        return HStack(spacing: 10) {
            GlassCheckbox(state: selected ? .on : .off, tint: Module.applications.palette.light,
                          label: "\(file.kind) : \(DisplayPath.short(file.path))") { model.toggleFile(file) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.kind).font(.system(size: 15, weight: .semibold))
                    if !file.isSelectedByDefault { Pill(text: "à vérifier", color: .orange) }
                }
                Text(DisplayPath.short(file.path)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(Bytes.text(file.allocatedBytes)).font(.system(size: 14).monospacedDigit())
            FinderButton(path: file.path)
        }
        .help(file.path)
    }

    private var review: some View {
        let files = model.selectedAppFiles
        return CleanReviewSheet(
            palette: Module.applications.palette,
            title: "Désinstaller \(model.chosen?.displayName ?? "")",
            totalBytes: files.reduce(0) { $0 + $1.allocatedBytes },
            sections: [ReviewSection(title: "Mis à la Corbeille", symbol: "trash", lines: files.map {
                ReviewLine(id: $0.path, name: $0.kind + " — " + ($0.path as NSString).lastPathComponent,
                           detail: DisplayPath.short($0.path), bytes: $0.allocatedBytes, symbol: "folder")
            })],
            notes: ["Tout va à la Corbeille : l'appli reste récupérable tant que vous ne la videz pas. Juste avant, Cleanmac revérifie chaque fichier et que l'appli est fermée."],
            confirmTitle: "Désinstaller",
            phase: model.cleanState,
            cleaningTitle: "Désinstallation…",
            onConfirm: { model.uninstallSelection() },
            onClose: { model.dismissCleanResult() })
    }
}

// MARK: Restes

private struct LeftoversTab: View {
    let model: AppsModel
    @State private var showReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.leftovers.isEmpty {
                EmptyStatePanel(symbol: "checkmark.circle.fill", title: "Aucun reste repéré",
                                detail: "Cleanmac cherche dans la Bibliothèque les dossiers nommés d'après une appli qui n'est plus installée. Par prudence, il écarte Apple et tout éditeur dont une appli est encore là.")
            } else {
                let selected = model.selectedLeftovers
                HStack {
                    Text("Repérés par leur identifiant. Rien n'est coché d'office : vérifiez qu'il ne s'agit pas d'un outil que vous utilisez encore.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    PrimaryActionButton(
                        title: selected.isEmpty ? "Rien de coché" : "Vérifier et mettre à la Corbeille (\(Bytes.text(selected.reduce(0) { $0 + $1.file.allocatedBytes })))",
                        symbol: "trash", tint: Module.applications.palette.mid, enabled: !selected.isEmpty
                    ) { showReview = true }
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.leftovers) { leftover in card(leftover) }
                    }
                }
            }
        }
        .sheet(isPresented: $showReview) {
            let selected = model.selectedLeftovers
            CleanReviewSheet(
                palette: Module.applications.palette,
                title: "Restes à mettre à la Corbeille",
                totalBytes: selected.reduce(0) { $0 + $1.file.allocatedBytes },
                sections: [ReviewSection(title: "Mis à la Corbeille", symbol: "trash", lines: selected.map {
                    ReviewLine(id: $0.file.path, name: $0.leftover.bundleID, detail: DisplayPath.short($0.file.path),
                               bytes: $0.file.allocatedBytes, symbol: "folder")
                })],
                notes: ["Juste avant, Cleanmac revérifie qu'aucune appli installée ne porte cet identifiant."],
                confirmTitle: "Mettre à la Corbeille",
                phase: model.cleanState,
                onConfirm: { model.trashLeftovers() },
                onClose: { model.dismissCleanResult() })
        }
    }

    private func card(_ leftover: Leftover) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                GlassCheckbox(state: model.isSelected(leftover), tint: Module.applications.palette.light,
                              label: "Restes de \(leftover.bundleID)") { model.toggleLeftover(leftover) }
                Text(leftover.bundleID).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(Bytes.text(leftover.totalBytes)).font(.system(size: 17, weight: .bold).monospacedDigit())
            }
            ForEach(leftover.files) { file in
                HStack {
                    Text(file.kind).font(.system(size: 14, weight: .medium)).frame(width: 150, alignment: .leading)
                    Text(DisplayPath.short(file.path)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1).truncationMode(.head)
                    Spacer()
                    Text(Bytes.text(file.allocatedBytes)).font(.system(size: 13).monospacedDigit())
                    FinderButton(path: file.path)
                }
                .padding(.leading, 54)
            }
        }
        .glassPanel(padding: 12)
    }
}

// MARK: Démarrage

private struct StartupTab: View {
    let model: AppsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vos agents s'activent et se désactivent ici (réversible). Ceux du système se consultent seulement.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Éléments de connexion de macOS…") { SMAppService.openSystemSettingsLoginItems() }
                    .controlSize(.large)
            }
            if let message = model.launchMessage {
                Label(message, systemImage: "info.circle").foregroundStyle(.white.opacity(0.8))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                        let items = model.launchItems.filter { $0.scope == scope }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(scope.title).font(.system(size: 18, weight: .semibold))
                                ForEach(items) { item in row(item) }
                            }
                            .glassPanel(padding: 14)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: LaunchItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    if item.isDisabled { Pill(text: "désactivé", color: .gray) }
                    else if item.isLoaded { Pill(text: "actif", color: .green) }
                    if item.runAtLoad { Pill(text: "au démarrage", color: .blue) }
                }
                if let program = item.program {
                    Text(DisplayPath.short(program)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1).truncationMode(.head)
                }
            }
            Spacer()
            if item.isEditable {
                if model.launchBusy == item.id {
                    ProgressView().controlSize(.small)
                }
                Toggle("Activé", isOn: Binding(get: { !item.isDisabled }, set: { model.setEnabled($0, item) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(model.launchBusy != nil)
                    .accessibilityLabel("Activer \(item.label)")
            }
            FinderButton(path: item.plistPath)
        }
        .help(item.plistPath)
    }
}

// MARK: Mises à jour

private struct UpdatesTab: View {
    let model: AppsModel
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cleanmac consulte le flux de mise à jour de chaque appli qui en déclare un (Sparkle) et Homebrew. Il ne met rien à jour lui-même.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("App Store…") { NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!) }
                    .controlSize(.large)
                PrimaryActionButton(title: model.updatesPhase == .checking ? "Recherche…" : "Rechercher",
                                    symbol: "arrow.clockwise", tint: Module.applications.palette.mid,
                                    enabled: model.updatesPhase != .checking) { model.checkUpdates() }
            }
            if let message = model.brewMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            switch model.updatesPhase {
            case .idle:
                EmptyStatePanel(symbol: "arrow.down.circle", title: "Pas encore cherché",
                                detail: "Cliquez sur « Rechercher » : la recherche interroge Internet et prend quelques secondes.")
            case .checking:
                ProgressView("Interrogation des flux de mise à jour…").controlSize(.large)
                Spacer()
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            case .done:
                if model.updates.isEmpty {
                    EmptyStatePanel(symbol: "checkmark.circle.fill", title: "Tout est à jour",
                                    detail: "Aucune version plus récente trouvée (hors App Store : voyez le bouton App Store).")
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.updates) { update in row(update) }
                        }
                        .padding(10)
                    }
                    .glassPanel(padding: 6)
                }
            }
        }
    }

    private func row(_ update: AppUpdate) -> some View {
        HStack(spacing: 12) {
            if let path = update.appPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 32, height: 32)
            } else {
                Image(systemName: "shippingbox").font(.system(size: 22)).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(update.name).font(.system(size: 16, weight: .semibold))
                    Pill(text: update.source.title, color: update.source == .homebrew ? .orange : .blue)
                }
                Text("\(update.installed) → \(update.available)").font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            if let path = update.appPath {
                VStack(alignment: .trailing, spacing: 2) {
                    Button("Ouvrir l'appli") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        .accessibilityLabel("Ouvrir \(update.name)")
                    Text("puis menu de l'appli › Rechercher les mises à jour")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
            } else if let token = update.caskToken {
                VStack(alignment: .trailing, spacing: 2) {
                    Button(copied == token ? "Commande copiée" : "Copier la commande") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew upgrade --cask \(token)", forType: .string)
                        copied = token
                    }
                    .accessibilityLabel("Copier la commande de mise à jour de \(update.name)")
                    Text("brew upgrade --cask \(token)")
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                        .textSelection(.enabled)
                }
            }
        }
        .controlSize(.large)
    }
}
