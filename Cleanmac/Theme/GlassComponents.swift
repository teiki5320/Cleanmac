import SwiftUI

/// Partie fractionnaire, toujours entre 0 et 1.
func fract(_ value: Double) -> Double {
    value - value.rounded(.down)
}

/// Horloge des animations continues. Figée (temps 0) si « Réduire les animations » est activé.
struct AnimationClock<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: (Double) -> Content

    init(@ViewBuilder content: @escaping (Double) -> Content) {
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            content(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
    }
}

/// Corps d'un objet en verre : dégradé du module, liseré intérieur, reflet qui passe, ombre portée.
struct GlassBody<S: InsettableShape>: View {
    let shape: S
    let palette: ModulePalette
    let time: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            // Le reflet traverse l'objet pendant la première moitié du cycle, puis se repose.
            let progress = min(fract(time / 3.6) / 0.55, 1)
            ZStack {
                shape.fill(palette.glass)
                LinearGradient(colors: [.clear, .black.opacity(0.30)], startPoint: .center, endPoint: .bottom)
                shape.inset(by: 14)
                    .fill(RadialGradient(colors: [.white.opacity(0.25), .clear],
                                         center: UnitPoint(x: 0.5, y: 0.3),
                                         startRadius: 0, endRadius: width * 0.55))
                shape.inset(by: 14).stroke(.white.opacity(0.35), lineWidth: 1)
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * 0.35, height: height * 1.5)
                    .rotationEffect(.degrees(20))
                    .offset(x: (-1.1 + 2.2 * progress) * width)
            }
            .clipShape(shape)
            .overlay(
                shape.stroke(LinearGradient(colors: [.white.opacity(0.75), .clear], startPoint: .top, endPoint: .center),
                             lineWidth: 2))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 24)
        }
    }
}

/// Fond animé de la fenêtre : dégradé du module, deux lueurs qui dérivent et des poussières qui montent.
struct ModuleBackground: View {
    let palette: ModulePalette

    var body: some View {
        AnimationClock { time in
            GeometryReader { geo in
                let size = geo.size
                let a = time * 2 * .pi
                ZStack {
                    palette.background
                    Circle()
                        .fill(RadialGradient(colors: [palette.light.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 340))
                        .frame(width: 680, height: 680)
                        .position(x: size.width * 0.30 + 200 * sin(a / 16), y: size.height * 0.10 + 110 * sin(a / 16 + 1))
                    Circle()
                        .fill(RadialGradient(colors: [palette.accent.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 320))
                        .frame(width: 640, height: 640)
                        .position(x: size.width * 0.90 - 190 * sin(a / 20), y: size.height * 0.95 - 90 * sin(a / 20 + 2))
                    DustLayer(color: palette.light, time: time)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Petites particules lumineuses qui montent lentement.
struct DustLayer: View {
    let color: Color
    let time: Double

    var body: some View {
        Canvas { context, size in
            for index in 0..<16 {
                let seed = Double(index)
                let x = fract(sin(seed * 12.9898) * 43758.5453) * size.width
                let progress = fract(time / 7 + seed * 0.37)
                let y = size.height * (1.02 - progress * 0.8)
                let alpha = progress < 0.2 ? progress / 0.2 : 1 - progress
                let radius = index.isMultiple(of: 2) ? 2.5 : 1.5
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(color.opacity(alpha * 0.15)))
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha * 0.85)))
            }
        }
    }
}

/// Pastille de verre ronde avec une icône, pour les listes de fonctions.
struct GlassIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(
                Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0.10)],
                                             center: UnitPoint(x: 0.35, y: 0.3),
                                             startRadius: 0, endRadius: 30)))
            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
            .accessibilityHidden(true)
    }
}

/// Gros bouton rond qui flotte en bas de la fenêtre.
struct ScanButton: View {
    let title: String
    let palette: ModulePalette
    /// Avancement (0…1) affiché en anneau pendant l'analyse.
    let progress: Double?
    let enabled: Bool
    let isDefaultAction: Bool
    let action: () -> Void

    var body: some View {
        AnimationClock { time in
            ZStack {
                if enabled, progress == nil {
                    pulse(fract(time / 2.4))
                    pulse(fract(time / 2.4 + 0.5))
                }
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(AngularGradient(colors: [.clear, palette.light, .clear], center: .center),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 118, height: 118)
                    .rotationEffect(.degrees(time * 90))
                if let progress {
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(palette.light, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 128, height: 128)
                        .rotationEffect(.degrees(-90))
                }
                Button(action: action) {
                    Text(title)
                        .font(Theme.Typo.button)
                        .foregroundStyle(.white)
                        .frame(width: Theme.Size.scanButton, height: Theme.Size.scanButton)
                        .background(
                            Circle().fill(RadialGradient(colors: [.white.opacity(0.55), palette.mid, palette.deep],
                                                         center: UnitPoint(x: 0.35, y: 0.28),
                                                         startRadius: 0, endRadius: 75)))
                        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                        .contentShape(Circle())
                        .shadow(color: .black.opacity(0.45), radius: 20, y: 14)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bouton-rond")
                .keyboardShortcut(isDefaultAction ? .defaultAction : KeyboardShortcut("r", modifiers: .command))
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.55)
            }
            .frame(width: 160, height: 160)
        }
    }

    private func pulse(_ phase: Double) -> some View {
        Circle()
            .stroke(palette.light, lineWidth: 2)
            .frame(width: Theme.Size.scanButton, height: Theme.Size.scanButton)
            .scaleEffect(1 + 0.9 * phase)
            .opacity(0.7 * (1 - phase))
            .accessibilityHidden(true)
    }
}

/// Espace du disque de démarrage.
enum DiskSpace {
    static func current() -> (free: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity
        else { return nil }
        return (free, Int64(total))
    }
}
