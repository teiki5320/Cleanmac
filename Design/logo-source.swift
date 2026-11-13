// Source du logo de Cleanmac (sphère de verre, variante « magenta » retenue : v1).
// Hors projet : se lance avec « swiftc -swift-version 6 logo-source.swift -o logo && ./logo <dossier> ».

import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Fond d'icône macOS : carré arrondi continu (824 px dans 1024), dégradé, liseré, ombre.
struct IconBase<Content: View>: View {
    let colors: [Color]
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RadialGradient(colors: [.white.opacity(0.28), .clear], center: UnitPoint(x: 0.3, y: 0.15), startRadius: 0, endRadius: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 186, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 4))
            content
        }
        .frame(width: 824, height: 824)
        .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        .frame(width: 1024, height: 1024)
    }
}

/// Sphère de verre.
struct GlassOrb: View {
    let light: Color, mid: Color, size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [.white.opacity(0.9), light, mid, .black.opacity(0.35)],
                                         center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.62))
            Circle().strokeBorder(.white.opacity(0.55), lineWidth: size * 0.012)
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.55, height: size * 0.3).offset(x: -size * 0.08, y: -size * 0.27)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.06, y: size * 0.05)
    }
}

struct Sparkle: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "sparkle").font(.system(size: size, weight: .regular)).foregroundStyle(.white)
            .shadow(color: .white.opacity(0.8), radius: size * 0.12)
    }
}

// A — Sphère étincelante, sarcelle (couleur de « Analyse complète »)
let a = IconBase(colors: [Color(hex: 0x0F766E), Color(hex: 0x03211F)]) {
    ZStack {
        Ellipse().stroke(.white.opacity(0.45), lineWidth: 6).frame(width: 640, height: 210).rotationEffect(.degrees(-18))
        GlassOrb(light: Color(hex: 0x5EEAD4), mid: Color(hex: 0x0D9488), size: 430)
        Sparkle(size: 190).offset(x: 20, y: 10)
        Sparkle(size: 80).offset(x: -95, y: -95)
        Circle().fill(.white).frame(width: 30, height: 30).offset(x: 300, y: -95).shadow(color: .white, radius: 10)
        Circle().fill(Color(hex: 0x22D3EE)).frame(width: 22, height: 22).offset(x: -300, y: 105).shadow(color: .cyan, radius: 8)
    }
}

// B — Anneau « C » de verre qui s'ouvre sur une étincelle, du violet au sarcelle
let b = IconBase(colors: [Color(hex: 0x4C1D95), Color(hex: 0x0F766E)]) {
    ZStack {
        Circle().trim(from: 0.12, to: 0.88)
            .stroke(LinearGradient(colors: [.white.opacity(0.95), Color(hex: 0x99F6E4), Color(hex: 0xA78BFA)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 120, lineCap: .round))
            .frame(width: 460, height: 460)
            .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
        Circle().trim(from: 0.12, to: 0.88)
            .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 18, lineCap: .round))
            .frame(width: 420, height: 420).offset(x: -6, y: -10).blur(radius: 2)
        Sparkle(size: 210).offset(x: 175, y: 0)
    }
}

// C — Disque en anneaux, balayé par un reflet propre, bleu (couleur de « Carte du disque »)
let c = IconBase(colors: [Color(hex: 0x1D4ED8), Color(hex: 0x03132E)]) {
    ZStack {
        ForEach(0..<3) { i in
            Circle().stroke(Color.white.opacity(0.18 + Double(i) * 0.1), lineWidth: 46)
                .frame(width: CGFloat(560 - i * 150), height: CGFloat(560 - i * 150))
        }
        Circle().trim(from: 0, to: 0.62)
            .stroke(AngularGradient(colors: [.clear, Color(hex: 0x7DD3FC), .white], center: .center),
                    style: StrokeStyle(lineWidth: 46, lineCap: .round))
            .frame(width: 560, height: 560).rotationEffect(.degrees(-90))
        GlassOrb(light: Color(hex: 0x7DD3FC), mid: Color(hex: 0x2563EB), size: 190)
        Sparkle(size: 120).offset(x: 215, y: -215)
    }
}


func orbIcon(_ bg: [UInt32], _ light: UInt32, _ mid: UInt32, _ glow: UInt32) -> some View {
    IconBase(colors: bg.map { Color(hex: $0) }) {
        ZStack {
            Ellipse().stroke(.white.opacity(0.45), lineWidth: 6).frame(width: 640, height: 210).rotationEffect(.degrees(-18))
            GlassOrb(light: Color(hex: light), mid: Color(hex: mid), size: 430)
            Sparkle(size: 190).offset(x: 20, y: 10)
            Sparkle(size: 80).offset(x: -95, y: -95)
            Circle().fill(.white).frame(width: 30, height: 30).offset(x: 300, y: -95).shadow(color: .white, radius: 10)
            Circle().fill(Color(hex: glow)).frame(width: 22, height: 22).offset(x: -300, y: 105).shadow(color: Color(hex: glow), radius: 8)
        }
    }
}
// 1 — magenta-rose (assorti au nouvel écran principal)
let v1 = orbIcon([0xD0237A, 0x2E0723], 0xFBA5D0, 0xDB2777, 0xC084FC)
// 2 — coucher de soleil (rose vers orange)
let v2 = orbIcon([0xE8457C, 0x5B1338], 0xFDBA74, 0xF43F5E, 0xFDE68A)
// 3 — violet nuit vers magenta
let v3 = orbIcon([0x7C3AED, 0x1E0B3A], 0xF0ABFC, 0xC026D3, 0x67E8F9)

@MainActor func save(_ view: some View, _ name: String) {
    let r = ImageRenderer(content: view); r.scale = 1
    if let t = r.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/\(name).png"))
    }
}
await MainActor.run {
    save(v1, "sphere-1-magenta")
    save(v2, "sphere-2-coucher")
    save(v3, "sphere-3-violet")
    save(HStack(spacing: 40) { v1.scaleEffect(0.3).frame(width: 310, height: 310); v2.scaleEffect(0.3).frame(width: 310, height: 310); v3.scaleEffect(0.3).frame(width: 310, height: 310) }
        .padding(30).background(Color(white: 0.92)), "spheres")
}
