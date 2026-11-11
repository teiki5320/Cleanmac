import AppKit
import CleanmacCore
import SwiftUI

/// Écran de la carte du disque, une fois l'analyse terminée.
/// Lecture seule : on peut explorer et ouvrir dans le Finder, jamais supprimer d'ici.
struct DiskMapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let map: DiskMap
    @State private var tab: Tab = .content
    @State private var hovered: DiskNode?

    enum Tab: String, CaseIterable, Identifiable {
        case content = "Contenu"
        case large = "Gros fichiers"
        var id: String { rawValue }
    }

    private var diskMap: DiskMapModel { model.diskMap }

    var body: some View {
        let focus = diskMap.focus ?? map.root
        VStack(alignment: .leading, spacing: 18) {
            header
            Breadcrumb(trail: diskMap.trail) { index in
                navigate { diskMap.goTo(index: index) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    sunburst(focus).frame(minWidth: 360, maxWidth: 560)
                    sidePanel(focus).frame(minWidth: 360, maxWidth: 520)
                }
                VStack(spacing: 20) {
                    sunburst(focus).frame(maxWidth: 420)
                    sidePanel(focus).frame(minHeight: 320)
                }
            }
            Label("Lecture seule : rien n'est supprimé ici. Pour faire de la place, passez par les modules de nettoyage, ou ouvrez l'élément dans le Finder.",
                  systemImage: "lock")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(.top, 44)
        .padding(.horizontal, 32)
        .padding(.bottom, 150)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            GlassIcon(symbol: "chart.pie")
            VStack(alignment: .leading, spacing: 2) {
                Text("Carte du disque").font(.system(size: 34, weight: .semibold))
                Text("\(Bytes.text(map.root.allocatedBytes)) — \(map.root.fileCount.formatted()) fichiers, lus en \(map.duration.formatted(.units(allowed: [.seconds], width: .abbreviated)))"
                     + (map.unreadableCount > 0 ? ", \(map.unreadableCount.formatted()) illisibles" : ""))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
            Spacer(minLength: 16)
            DiskRootPicker(compact: true)
        }
    }

    private func sunburst(_ focus: DiskNode) -> some View {
        Sunburst(
            focus: focus,
            hovered: $hovered,
            canGoUp: diskMap.trail.count > 1,
            open: { node in navigate { diskMap.open(node) } },
            goUp: { navigate { diskMap.goUp() } })
            .aspectRatio(1, contentMode: .fit)
    }

    private func sidePanel(_ focus: DiskNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Affichage", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            switch tab {
            case .content:
                DiskContentList(focus: focus, hovered: $hovered) { node in navigate { diskMap.open(node) } }
            case .large:
                LargeFilesList(files: map.largestFiles.filter { isInside($0.path, focus.path) })
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Size.panelCorner, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private func navigate(_ change: () -> Void) {
        hovered = nil
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { change() }
    }

    private func isInside(_ path: String, _ folder: String) -> Bool {
        path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }
}

// MARK: Choix de la racine

/// Dossier personnel ou tout le Mac.
struct DiskRootPicker: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        let diskMap = model.diskMap
        HStack(spacing: 10) {
            ForEach(DiskMapModel.Root.allCases) { root in
                let selected = diskMap.root == root
                Button {
                    diskMap.select(root)
                } label: {
                    Label(root.title, systemImage: root.symbol)
                        .font(.system(size: compact ? 15 : 17, weight: .semibold))
                        .padding(.horizontal, compact ? 14 : 18)
                        .padding(.vertical, compact ? 9 : 12)
                        .background(.white.opacity(selected ? 0.24 : 0.08),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(selected ? 0.45 : 0.16), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.8))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .disabled(diskMap.isScanning)
    }
}

// MARK: Fil d'Ariane

private struct Breadcrumb: View {
    let trail: [DiskNode]
    let goTo: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(trail.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    let isLast = index == trail.count - 1
                    Button { goTo(index) } label: {
                        Text(node.name)
                            .font(.system(size: 17, weight: isLast ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(isLast ? 0.16 : 0), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLast)
                }
            }
        }
    }
}

// MARK: Anneaux

/// Vue en anneaux : le dossier affiché au centre, son contenu sur trois anneaux.
private struct Sunburst: View {
    let focus: DiskNode
    @Binding var hovered: DiskNode?
    let canGoUp: Bool
    let open: (DiskNode) -> Void
    let goUp: () -> Void

    static let levels = 3
    static let hole = 0.40

    var body: some View {
        let segments = SunburstLayout.segments(for: focus, levels: Self.levels)
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(segments) { segment in
                    let shape = RingSegment(start: segment.start, end: segment.end,
                                            inner: Self.inner(segment.depth), outer: Self.outer(segment.depth))
                    let lit = hovered.map { isSameOrInside(segment.node.path, $0.path) } ?? true
                    shape
                        .fill(color(segment))
                        .overlay(shape.stroke(.black.opacity(0.28), lineWidth: 1))
                        .opacity(lit ? 1 : 0.45)
                        .contentShape(shape)
                        .onHover { inside in
                            if inside { hovered = segment.node } else if hovered?.id == segment.id { hovered = nil }
                        }
                        .onTapGesture { open(segment.node) }
                        .accessibilityElement()
                        .accessibilityLabel("\(segment.node.name), \(Bytes.text(segment.node.allocatedBytes))")
                        .accessibilityAddTraits(segment.node.isDirectory ? .isButton : [])
                        .transition(.opacity)
                }
                center(size: size)
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func center(size: CGFloat) -> some View {
        let shown = hovered ?? focus
        // Le trou fait `hole` fois le rayon : son diamètre vaut donc `hole` fois la taille.
        let diameter = size * Self.hole - 12
        return Button { if canGoUp { goUp() } } label: {
            VStack(spacing: 4) {
                Image(systemName: shown.isDirectory ? "folder.fill" : (shown.kind == .file ? "doc.fill" : "ellipsis.circle.fill"))
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                Text(shown.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(Bytes.text(shown.allocatedBytes))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                if canGoUp, hovered == nil {
                    Label("Remonter", systemImage: "arrow.up")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(12)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(RadialGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                             center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: diameter * 0.6)))
            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(canGoUp ? "Remonter d'un dossier" : "\(focus.name), \(Bytes.text(focus.allocatedBytes))")
    }

    private func color(_ segment: SunburstSegment) -> Color {
        if case .others = segment.node.kind { return DiskMapColors.others }
        return DiskMapColors.color(segment.colorIndex, depth: segment.depth)
    }

    private func isSameOrInside(_ path: String, _ other: String) -> Bool {
        path == other || path.hasPrefix(other + "/")
    }

    private static var ringWidth: Double { (1 - hole) / Double(levels) }
    private static func inner(_ depth: Int) -> Double { hole + Double(depth - 1) * ringWidth + 0.006 }
    private static func outer(_ depth: Int) -> Double { hole + Double(depth) * ringWidth }
}

/// Secteur d'anneau (angles en fraction du tour, rayons en fraction du rayon disponible).
private struct RingSegment: Shape {
    var start: Double
    var end: Double
    var inner: Double
    var outer: Double

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { AnimatablePair(AnimatablePair(start, end), AnimatablePair(inner, outer)) }
        set {
            start = newValue.first.first
            end = newValue.first.second
            inner = newValue.second.first
            outer = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let span = min(end - start, 0.9999)
        let from = Angle.degrees(start * 360 - 90)
        let to = Angle.degrees((start + span) * 360 - 90)
        var path = Path()
        path.addArc(center: center, radius: radius * outer, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: center, radius: radius * inner, startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: Listes

/// Contenu du dossier affiché, du plus gros au plus petit.
private struct DiskContentList: View {
    let focus: DiskNode
    @Binding var hovered: DiskNode?
    let open: (DiskNode) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(focus.children.enumerated()), id: \.element.id) { index, node in
                    row(node, index: index)
                }
            }
        }
    }

    private func row(_ node: DiskNode, index: Int) -> some View {
        let share = focus.allocatedBytes > 0 ? Double(node.allocatedBytes) / Double(focus.allocatedBytes) : 0
        let canOpen = node.isDirectory && !node.children.isEmpty
        let color: Color = if case .others = node.kind { DiskMapColors.others } else { DiskMapColors.color(index, depth: 1) }
        return HStack(spacing: 8) {
            Button { open(node) } label: {
                HStack(spacing: 12) {
                    Circle().fill(color).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: symbol(node))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(node.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Bytes.text(node.allocatedBytes)).monospacedDigit()
                        }
                        .font(.system(size: 17, weight: .medium))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.1))
                                Capsule().fill(color).frame(width: max(3, geo.size.width * share))
                            }
                        }
                        .frame(height: 5)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(canOpen ? 0.6 : 0))
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .background(.white.opacity(hovered?.id == node.id ? 0.12 : 0),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
            .onHover { inside in
                if inside { hovered = node } else if hovered?.id == node.id { hovered = nil }
            }
            if case .others = node.kind {
                Color.clear.frame(width: 40, height: 40)
            } else {
                FinderButton(path: node.path)
            }
        }
    }

    private func symbol(_ node: DiskNode) -> String {
        switch node.kind {
        case .directory: "folder"
        case .file: "doc"
        case .others: "ellipsis.circle"
        }
    }
}

/// Les plus gros fichiers du dossier affiché.
private struct LargeFilesList: View {
    let files: [LargeFile]

    var body: some View {
        if files.isEmpty {
            Text("Aucun fichier de plus de 50 Mo dans ce dossier.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 8)
            Spacer(minLength: 0)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(files) { file in row(file) }
                }
            }
        }
    }

    private func row(_ file: LargeFile) -> some View {
        let old = file.modified < Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        return HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text(DisplayPath.short((file.path as NSString).deletingLastPathComponent))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Text("·")
                    Text("modifié \(file.modified.formatted(.relative(presentation: .named)))")
                        .lineLimit(1)
                    if old {
                        Text("ancien")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.35)))
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
            Text(Bytes.text(file.allocatedBytes))
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
            FinderButton(path: file.path)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .help(file.path)
    }
}

/// Bouton « Afficher dans le Finder ».
private struct FinderButton: View {
    let path: String

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Afficher dans le Finder")
        .accessibilityLabel("Afficher dans le Finder")
    }
}

/// Chemins raccourcis pour l'affichage.
enum DisplayPath {
    static func short(_ path: String) -> String {
        var result = path
        let data = "/System/Volumes/Data"
        if result.hasPrefix(data + "/") { result.removeFirst(data.count) }
        let home = NSHomeDirectory()
        if result == home { return "~" }
        if result.hasPrefix(home + "/") { result = "~" + result.dropFirst(home.count) }
        return result
    }
}
