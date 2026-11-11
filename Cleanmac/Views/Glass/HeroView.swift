import SwiftUI

/// Gros objet en verre animé au centre de l'écran d'un module.
struct HeroView: View {
    let module: Module
    /// Accélère les animations pendant l'analyse.
    var isScanning = false
    /// Avancement de l'analyse (0…1), affiché en anneau autour de l'objet.
    var progress: Double?

    private var palette: ModulePalette { module.palette }

    var body: some View {
        AnimationClock { clock in
            let time = isScanning ? clock * 2.2 : clock
            let float = sin(time * 2 * .pi / 5)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [palette.light.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 190))
                    .frame(width: 380, height: 380)
                    .opacity(0.75 + 0.25 * sin(time * 2 * .pi / 3))
                Ellipse()
                    .fill(.black.opacity(0.45 - 0.12 * float))
                    .frame(width: 220 * (1 - 0.1 * float), height: 26)
                    .blur(radius: 10)
                    .offset(y: 180)
                if let progress {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 8)
                        .frame(width: 350, height: 350)
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(palette.light, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 350, height: 350)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: palette.light, radius: 10)
                }
                content(time)
                    .offset(y: -9 - 9 * float)
                    .rotationEffect(.degrees(2 * sin(time * 2 * .pi / 5 + 1)))
            }
            .frame(width: 400, height: 420)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(_ time: Double) -> some View {
        switch module.hero {
        case .orb: OrbHero(palette: palette, symbol: module.symbol, time: time)
        case .block: BlockHero(palette: palette, symbol: module.symbol, time: time)
        case .code: CodeHero(palette: palette, symbol: module.symbol, time: time)
        case .trash: TrashHero(palette: palette, time: time)
        case .diskRing: DiskRingHero(palette: palette, time: time)
        }
    }
}

/// Icône blanche posée sur un objet en verre.
private struct HeroSymbol: View {
    let symbol: String
    var size: CGFloat = 104

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .light))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
    }
}

/// Bloc arrondi en verre avec l'icône du module.
private struct BlockHero: View {
    let palette: ModulePalette
    let symbol: String
    let time: Double

    var body: some View {
        ZStack {
            GlassBody(shape: RoundedRectangle(cornerRadius: 68, style: .continuous), palette: palette, time: time)
            HeroSymbol(symbol: symbol, size: 96)
        }
        .frame(width: Theme.Size.heroSize, height: Theme.Size.heroSize)
    }
}

/// Sphère en verre avec deux lumières en orbite inclinée.
private struct OrbHero: View {
    let palette: ModulePalette
    let symbol: String
    let time: Double

    var body: some View {
        let angle = time * 2 * .pi / 7
        ZStack {
            orbit(front: false, angle: angle)
            ZStack {
                GlassBody(shape: Circle(), palette: palette, time: time)
                HeroSymbol(symbol: symbol, size: 92)
            }
            .frame(width: 240, height: 240)
            orbit(front: true, angle: angle)
        }
        .frame(width: 400, height: 300)
    }

    /// Moitié arrière (derrière la sphère) ou avant de l'orbite.
    private func orbit(front: Bool, angle: Double) -> some View {
        ZStack {
            Ellipse()
                .trim(from: front ? 0 : 0.5, to: front ? 0.5 : 1)
                .stroke(.white.opacity(0.35), lineWidth: 2)
                .frame(width: 380, height: 110)
            ForEach(0..<2, id: \.self) { index in
                let a = angle + Double(index) * .pi
                if (sin(a) >= 0) == front {
                    Circle()
                        .fill(index == 0 ? Color.white : palette.accent)
                        .frame(width: index == 0 ? 18 : 12, height: index == 0 ? 18 : 12)
                        .shadow(color: palette.light, radius: 12)
                        .offset(x: 190 * cos(a), y: 55 * sin(a))
                }
            }
        }
        .rotationEffect(.degrees(-14))
    }
}

/// Bloc « code » avec des étiquettes de dossiers qui flottent autour.
private struct CodeHero: View {
    let palette: ModulePalette
    let symbol: String
    let time: Double

    private let chips: [(String, CGFloat, CGFloat)] = [
        ("DerivedData", -150, -105),
        (".gradle", 150, -70),
        (".pub-cache", -140, 95),
        ("node_modules", 150, 60),
    ]

    var body: some View {
        ZStack {
            BlockHero(palette: palette, symbol: symbol, time: time)
            ForEach(chips.indices, id: \.self) { index in
                let chip = chips[index]
                let phase = time * 2 * .pi / 6 + Double(index) * 1.6
                Text(chip.0)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.16)))
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
                    .offset(x: chip.1 + 12 * sin(phase), y: chip.2 + 12 * cos(phase))
            }
        }
        .frame(width: 400, height: 320)
    }
}

/// Poubelle en verre : des fichiers tombent dedans, le couvercle s'ouvre, elle tremble un peu.
private struct TrashHero: View {
    let palette: ModulePalette
    let time: Double

    var body: some View {
        let cycle = fract(time / 2.8)
        let lid = cycle > 0.8 ? sin((cycle - 0.8) / 0.2 * .pi) * -18 : 0
        let wobble = cycle > 0.85 ? sin((cycle - 0.85) / 0.15 * 2 * .pi) * 4 : 0
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let phase = fract(time / 2.8 + Double(index) / 3)
                let start: [CGFloat] = [-60, 30, -10]
                let drift: [CGFloat] = [40, -30, 10]
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.88))
                    .frame(width: 22, height: 28)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                    .scaleEffect(1 - 0.6 * phase)
                    .rotationEffect(.degrees(phase * 220))
                    .offset(x: start[index] + drift[index] * phase, y: -170 + 210 * phase)
                    .opacity(phase < 0.15 ? phase / 0.15 : (phase > 0.8 ? (1 - phase) / 0.2 : 1))
            }
            VStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.85), palette.light], startPoint: .top, endPoint: .bottom))
                    .frame(width: 224, height: 30)
                    .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 6)
                    .rotationEffect(.degrees(lid), anchor: .bottomLeading)
                ZStack {
                    GlassBody(shape: RoundedRectangle(cornerRadius: 40, style: .continuous), palette: palette, time: time)
                    HStack(spacing: 30) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(.white.opacity(0.35)).frame(width: 10, height: 140)
                        }
                    }
                }
                .frame(width: 200, height: 210)
            }
            .rotationEffect(.degrees(wobble), anchor: .bottom)
            .offset(y: 30)
        }
        .frame(width: 300, height: 360)
    }
}

/// Double anneau coloré qui tourne lentement autour d'un disque en verre.
private struct DiskRingHero: View {
    let palette: ModulePalette
    let time: Double

    private let inner: [(Color, Double, Double)] = [
        (Color(hex: 0x7DD3FC), 0.00, 0.19), (Color(hex: 0xA5B4FC), 0.21, 0.41),
        (Color(hex: 0xF9A8D4), 0.43, 0.55), (Color(hex: 0xFDE68A), 0.57, 0.69),
        (Color(hex: 0x86EFAC), 0.71, 0.92),
    ]
    private let outer: [(Color, Double, Double)] = [
        (Color(hex: 0x7DD3FC), 0.03, 0.11), (Color(hex: 0xA5B4FC), 0.25, 0.33),
        (Color(hex: 0xF9A8D4), 0.44, 0.48), (Color(hex: 0xFDE68A), 0.60, 0.65),
        (Color(hex: 0x86EFAC), 0.75, 0.86),
    ]

    /// Lu une seule fois à l'affichage, pas à chaque image de l'animation.
    @State private var space = DiskSpace.current()

    var body: some View {
        ZStack {
            ZStack {
                ForEach(outer.indices, id: \.self) { index in
                    Circle()
                        .trim(from: outer[index].1, to: outer[index].2)
                        .stroke(outer[index].0.opacity(0.55), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .frame(width: 300, height: 300)
                }
                ForEach(inner.indices, id: \.self) { index in
                    Circle()
                        .trim(from: inner[index].1, to: inner[index].2)
                        .stroke(inner[index].0, style: StrokeStyle(lineWidth: 30, lineCap: .butt))
                        .frame(width: 222, height: 222)
                        .opacity(0.75 + 0.25 * sin(time * 2 * .pi / 2.4 + Double(index)))
                }
            }
            .rotationEffect(.degrees(time * 12))
            ZStack {
                GlassBody(shape: Circle(), palette: palette, time: time)
                VStack(spacing: 2) {
                    Text(space.map { Bytes.text($0.total) } ?? "Disque")
                        .font(.system(size: 30, weight: .bold))
                    if let space {
                        Text("\(Bytes.text(space.free)) libres")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(width: 170, height: 170)
        }
        .frame(width: 330, height: 330)
    }
}
