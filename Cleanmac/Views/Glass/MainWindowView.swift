import CleanmacCore
import SwiftUI

/// Fenêtre principale en style « verre » : barre latérale, fond animé du module,
/// objet en verre, panneau d'explication et bouton rond flottant.
struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var module: Module = .analyse
    @State private var showSettings = false

    private var palette: ModulePalette { module.palette }

    /// Le dernier scan concerne-t-il le module affiché ?
    private var scanIsForModule: Bool {
        guard let scope = module.scope else { return false }
        return scope.categories == model.scanCategories
    }

    private var isScanningModule: Bool {
        module == .carte ? model.diskMap.isScanning : scanIsForModule && model.isScanning
    }
    private var resultForModule: ScanResult? { scanIsForModule ? model.scanResult : nil }
    /// Le module affiché a-t-il un résultat à montrer ?
    private var moduleHasResult: Bool {
        module == .carte ? model.diskMap.map != nil : resultForModule != nil
    }
    /// Avancement affiché sur l'objet en verre et le bouton rond.
    private var moduleProgress: Double? {
        guard isScanningModule else { return nil }
        return module == .carte ? model.diskMap.estimatedFraction : scanFraction
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $module) { showSettings = true }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            ModuleBackground(palette: palette)
                .id(module)
                .transition(.opacity)
        }
        .overlay(alignment: .bottom) {
            scanButton
                .padding(.leading, Theme.Size.sidebarWidth)
                .padding(.bottom, 10)
        }
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.colorScheme, .dark)
        .tint(palette.light)
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Fermer") { showSettings = false }
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.large)
                }
                .padding([.top, .horizontal], 16)
                FoundationsView()
            }
            .frame(minWidth: 860, minHeight: 680)
        }
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        if module == .carte, let map = model.diskMap.map {
            DiskMapScreen(map: map)
                .id("carte")
        } else if let result = resultForModule {
            ResultsPanel(module: module, result: result)
                .id("resultats-\(module.id)")
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 40) {
                    hero
                    InfoPanel(module: module, isScanning: isScanningModule) { showSettings = true }
                        .frame(maxWidth: 440)
                }
                VStack(spacing: 8) {
                    hero.scaleEffect(0.72).frame(height: 310)
                    InfoPanel(module: module, isScanning: isScanningModule) { showSettings = true }
                        .frame(maxWidth: 520)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 130)
            .padding(.top, 40)
            .id("intro-\(module.id)")
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            HeroView(module: module, isScanning: isScanningModule, progress: moduleProgress)
            Text(module.caption)
                .font(Theme.Typo.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var scanFraction: Double {
        if case let .scanning(progress) = model.scanState { return progress?.fractionCompleted ?? 0 }
        return 0
    }

    // MARK: Bouton rond

    private var scanButton: some View {
        let busyElsewhere = module != .carte && model.isScanning && !scanIsForModule
        let title: String
        let enabled: Bool
        if !module.isAvailable {
            title = "Bientôt"
            enabled = false
        } else if isScanningModule {
            title = "Arrêter"
            enabled = true
        } else if moduleHasResult {
            title = "Relancer"
            enabled = !model.isCleaning
        } else {
            title = "Analyser"
            enabled = model.rules != nil && !busyElsewhere
        }
        return ScanButton(
            title: title,
            palette: palette,
            progress: moduleProgress,
            enabled: enabled,
            isDefaultAction: !moduleHasResult
        ) {
            if module == .carte {
                if isScanningModule { model.diskMap.cancel() } else { model.diskMap.start() }
            } else if isScanningModule {
                model.cancelScan()
            } else {
                model.startScan(categories: module.scope?.categories)
            }
        }
        .accessibilityLabel(module.isAvailable ? "\(title) — \(module.title)" : "\(module.title) : module à venir")
    }
}

// MARK: Barre latérale

private struct Sidebar: View {
    @Binding var selection: Module
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Nettoyage")
            ForEach(Module.cleaning) { row($0) }
            sectionTitle("Espace et applis").padding(.top, 14)
            ForEach(Module.spaceAndApps) { row($0) }
            Spacer(minLength: 20)
            DiskGauge()
            Button(action: openSettings) {
                Label("Réglages et journal", systemImage: "gearshape")
                    .font(Theme.Typo.sidebar)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.top, 52)
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(width: Theme.Size.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.black.opacity(0.16))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func row(_ module: Module) -> some View {
        let selected = module == selection
        return Button {
            withAnimation(Theme.moduleTransition) { selection = module }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: module.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? module.palette.light : .white.opacity(0.75))
                    .frame(width: 26)
                Text(module.title)
                    .font(Theme.Typo.sidebar)
                    .fontWeight(selected ? .semibold : .medium)
                    .foregroundStyle(selected ? .white : .white.opacity(0.85))
                Spacer(minLength: 4)
                if !module.isAvailable {
                    Text("bientôt")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Size.rowCorner, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Size.rowCorner, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: .white.opacity(0.08), radius: 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Espace libre du disque de démarrage, en bas de la barre latérale.
private struct DiskGauge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Relu quand un scan ou un nettoyage se termine (le modèle change).
        let _ = model.journalEntries.count
        if let space = DiskSpace.current(), space.total > 0 {
            let used = 1 - Double(space.free) / Double(space.total)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Macintosh HD")
                    Spacer()
                    Text("\(Bytes.text(space.free)) libres").monospacedDigit()
                }
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.75))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: 0x5EEAD4), used > 0.9 ? Color(hex: 0xF97316) : Color(hex: 0x38BDF8)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * used)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: Panneau d'explication

private struct InfoPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let module: Module
    let isScanning: Bool
    let openSettings: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(isScanning ? "Analyse en cours…" : module.title)
                .font(Theme.Typo.title)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .modifier(Rise(appeared: appeared, delay: 0.1, reduceMotion: reduceMotion))
            if isScanning {
                scanningDetails
            } else {
                Text(module.summary)
                    .font(Theme.Typo.body)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(Rise(appeared: appeared, delay: 0.2, reduceMotion: reduceMotion))
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(module.features.enumerated()), id: \.element.id) { index, feature in
                        HStack(spacing: 16) {
                            GlassIcon(symbol: feature.symbol)
                            Text(feature.title).font(Theme.Typo.feature)
                        }
                        .modifier(Rise(appeared: appeared, delay: 0.35 + Double(index) * 0.12, reduceMotion: reduceMotion))
                    }
                }
                if module == .carte {
                    VStack(alignment: .leading, spacing: 12) {
                        DiskRootPicker()
                        diskMapStatus
                    }
                    .modifier(Rise(appeared: appeared, delay: 0.8, reduceMotion: reduceMotion))
                } else if module.isAvailable {
                    Button(action: openSettings) {
                        Text("Réglages de l'analyse")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .modifier(Rise(appeared: appeared, delay: 0.8, reduceMotion: reduceMotion))
                } else {
                    Label("Ce module arrive dans une prochaine version.", systemImage: "hammer")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .modifier(Rise(appeared: appeared, delay: 0.8, reduceMotion: reduceMotion))
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { appeared = true }
    }

    /// Message après une carte annulée ou en échec.
    @ViewBuilder
    private var diskMapStatus: some View {
        switch model.diskMap.state {
        case .cancelled:
            Label("Analyse arrêtée.", systemImage: "pause.circle")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.75))
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var scanningDetails: some View {
        if module == .carte {
            let progress = model.diskMap.progress
            VStack(alignment: .leading, spacing: 10) {
                Text(progress.map { DisplayPath.short($0.currentPath) } ?? "Préparation…")
                    .font(Theme.Typo.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Bytes.text(progress?.bytesFound ?? 0))
                    .font(.system(size: 54, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("\((progress?.filesVisited ?? 0).formatted()) fichiers parcourus — \(model.diskMap.root.title)")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
        } else if case let .scanning(progress) = model.scanState {
            VStack(alignment: .leading, spacing: 10) {
                Text(progress?.currentRuleName ?? "Préparation…")
                    .font(Theme.Typo.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(Bytes.text(progress?.bytesFound ?? 0))
                    .font(.system(size: 54, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("\((progress?.filesVisited ?? 0).formatted()) fichiers parcourus")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }
}

/// Apparition en montant, décalée dans le temps.
private struct Rise: ViewModifier {
    let appeared: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 18)
            .animation(reduceMotion ? nil : .smooth(duration: 0.6).delay(delay), value: appeared)
    }
}

// MARK: Résultats

private struct ResultsPanel: View {
    let module: Module
    let result: ScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                GlassIcon(symbol: module.symbol)
                Text(module.title).font(.system(size: 34, weight: .semibold))
            }
            .foregroundStyle(.white)
            ScrollView {
                ResultsView(result: result)
                    .padding(24)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1))
        }
        .padding(.top, 48)
        .padding(.horizontal, 32)
        .padding(.bottom, 150)
    }
}
