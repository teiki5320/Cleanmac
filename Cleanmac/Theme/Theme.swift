import CleanmacCore
import SwiftUI

// Fichier de thème unique : couleurs, dégradés par module, typographie, espacements.
// Style « verre » validé sur la maquette (novembre 2026).

extension Color {
    /// Couleur à partir d'un code hexadécimal (0xRRGGBB).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}

/// Les quatre teintes d'un module, de la plus sombre à l'accent.
struct ModulePalette: Sendable {
    /// Fond sombre de la fenêtre.
    let deep: Color
    /// Teinte principale (milieu du dégradé, corps des objets en verre).
    let mid: Color
    /// Teinte claire (reflets, icônes actives, anneaux).
    let light: Color
    /// Seconde lueur du fond.
    let accent: Color

    /// Dégradé du fond de la fenêtre.
    var background: LinearGradient {
        LinearGradient(colors: [deep, mid, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Dégradé du corps d'un objet en verre.
    var glass: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.65), location: 0),
                .init(color: light, location: 0.22),
                .init(color: mid, location: 0.70),
                .init(color: .black.opacity(0.35), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}

enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
    }

    enum Size {
        static let sidebarWidth: CGFloat = 250
        static let heroSize: CGFloat = 250
        static let scanButton: CGFloat = 104
        static let rowCorner: CGFloat = 12
        static let panelCorner: CGFloat = 20
    }

    /// Typographie : grande et lisible, même pilotée depuis l'iPad.
    enum Typo {
        static var title: Font { Font.system(size: 46, weight: .semibold) }
        static var body: Font { Font.system(size: 19) }
        static var feature: Font { Font.system(size: 19, weight: .semibold) }
        static var sidebar: Font { Font.system(size: 17, weight: .medium) }
        static var caption: Font { Font.system(size: 16) }
        static var button: Font { Font.system(size: 20, weight: .semibold) }
    }

    /// Durée des transitions entre modules.
    static var moduleTransition: Animation { .smooth(duration: 0.5) }
}

/// Couleurs des secteurs de la carte du disque : une par élément du premier anneau,
/// reprise plus pâle sur les anneaux extérieurs.
enum DiskMapColors {
    static let palette: [Color] = [
        0xF472B6, 0xA78BFA, 0x60A5FA, 0x22D3EE, 0x34D399,
        0xFBBF24, 0xFB923C, 0xF87171, 0xA3E635, 0xE879F9,
    ].map { Color(hex: $0) }

    static func color(_ index: Int, depth: Int) -> Color {
        palette[index % palette.count].opacity(depth <= 1 ? 1 : depth == 2 ? 0.72 : 0.5)
    }

    /// Petits éléments regroupés.
    static let others = Color.white.opacity(0.22)
}

/// Ce que l'analyse d'un module parcourt.
enum ScanScope: Equatable, Sendable {
    /// Toutes les règles.
    case all
    /// Les seules règles de ces catégories.
    case categories(Set<RuleCategory>)

    var categories: Set<RuleCategory>? {
        switch self {
        case .all: nil
        case let .categories(set): set
        }
    }
}

/// Objet en verre affiché au centre de l'écran d'un module.
enum HeroKind: Sendable {
    case orb
    case block
    case code
    case trash
    case diskRing
}

struct ModuleFeature: Sendable, Identifiable {
    let title: String
    let symbol: String
    var id: String { title }
}

/// Les modules de la barre latérale, chacun avec sa couleur et son objet.
enum Module: String, CaseIterable, Identifiable, Sendable {
    case analyse
    case systeme
    case developpeur
    case mail
    case corbeilles
    case icloud
    case carte
    case applications

    var id: String { rawValue }

    static let cleaning: [Module] = [.analyse, .systeme, .developpeur, .mail, .corbeilles, .icloud]
    static let spaceAndApps: [Module] = [.carte, .applications]

    var title: String {
        switch self {
        case .analyse: "Analyse complète"
        case .systeme: "Fichiers système"
        case .developpeur: "Développeur"
        case .mail: "Mail"
        case .corbeilles: "Corbeilles"
        case .icloud: "iCloud Drive"
        case .carte: "Carte du disque"
        case .applications: "Applications"
        }
    }

    /// Icône SF Symbols.
    var symbol: String {
        switch self {
        case .analyse: "sparkles"
        case .systeme: "doc.text.magnifyingglass"
        case .developpeur: "chevron.left.forwardslash.chevron.right"
        case .mail: "envelope"
        case .corbeilles: "trash"
        case .icloud: "icloud"
        case .carte: "chart.pie"
        case .applications: "square.grid.2x2"
        }
    }

    var palette: ModulePalette {
        switch self {
        case .analyse:
            ModulePalette(deep: Color(hex: 0x03211F), mid: Color(hex: 0x0F766E), light: Color(hex: 0x5EEAD4), accent: Color(hex: 0x22D3EE))
        case .systeme:
            ModulePalette(deep: Color(hex: 0x0E1E08), mid: Color(hex: 0x4D7C0F), light: Color(hex: 0xBEF264), accent: Color(hex: 0x22C55E))
        case .developpeur:
            ModulePalette(deep: Color(hex: 0x120A36), mid: Color(hex: 0x4338CA), light: Color(hex: 0xA5B4FC), accent: Color(hex: 0x8B5CF6))
        case .mail:
            ModulePalette(deep: Color(hex: 0x261803), mid: Color(hex: 0xB45309), light: Color(hex: 0xFCD34D), accent: Color(hex: 0xF97316))
        case .corbeilles:
            ModulePalette(deep: Color(hex: 0x2A0904), mid: Color(hex: 0xC2410C), light: Color(hex: 0xFDBA74), accent: Color(hex: 0xF43F5E))
        case .icloud:
            ModulePalette(deep: Color(hex: 0x06263A), mid: Color(hex: 0x0EA5E9), light: Color(hex: 0xBAE6FD), accent: Color(hex: 0xA5B4FC))
        case .carte:
            ModulePalette(deep: Color(hex: 0x03132E), mid: Color(hex: 0x1D4ED8), light: Color(hex: 0x7DD3FC), accent: Color(hex: 0x6366F1))
        case .applications:
            ModulePalette(deep: Color(hex: 0x2D0A1E), mid: Color(hex: 0xBE185D), light: Color(hex: 0xF9A8D4), accent: Color(hex: 0xA855F7))
        }
    }

    var summary: String {
        switch self {
        case .analyse:
            "Parcourt toutes les règles d'un coup : fichiers système et outils de développement, y compris les éléments « à vérifier ». Rien ne part sans votre vérification."
        case .systeme:
            "Caches des applications, journaux, rapports de plantage et états de fenêtres enregistrés."
        case .developpeur:
            "Xcode, simulateurs, Gradle, Flutter, npm, Homebrew… Les modèles d'IA sont montrés mais jamais cochés d'office."
        case .mail:
            "Pièces jointes téléchargées par Mail et caches de Thunderbird."
        case .corbeilles:
            "La Corbeille du Mac, celles des disques externes et celle de Photos, réunies au même endroit."
        case .icloud:
            "Libère les fichiers d'iCloud Drive téléchargés sur le Mac, sans les supprimer d'iCloud."
        case .carte:
            "Voyez ce qui prend la place, dossier par dossier : cliquez sur un anneau pour descendre, au centre pour remonter."
        case .applications:
            "Désinstallez une appli avec tous ses fichiers, retrouvez les restes et gérez le démarrage."
        }
    }

    var features: [ModuleFeature] {
        switch self {
        case .analyse:
            [.init(title: "Tous les fichiers système", symbol: "doc.text"),
             .init(title: "Tout le développement", symbol: "hammer"),
             .init(title: "Vérification avant nettoyage", symbol: "checkmark.shield")]
        case .systeme:
            [.init(title: "Caches des applications", symbol: "internaldrive"),
             .init(title: "Journaux et plantages", symbol: "list.bullet.rectangle"),
             .init(title: "États des fenêtres", symbol: "macwindow")]
        case .developpeur:
            [.init(title: "Xcode et simulateurs", symbol: "hammer"),
             .init(title: "Gradle, Android et Flutter", symbol: "shippingbox"),
             .init(title: "npm, pip et Homebrew", symbol: "cube")]
        case .mail:
            [.init(title: "Pièces jointes de Mail", symbol: "paperclip"),
             .init(title: "Caches de Thunderbird", symbol: "tray.full"),
             .init(title: "Jamais vos messages", symbol: "lock")]
        case .corbeilles:
            [.init(title: "Corbeille du Mac", symbol: "trash"),
             .init(title: "Disques externes", symbol: "externaldrive"),
             .init(title: "Photos : supprimées récemment", symbol: "photo")]
        case .icloud:
            [.init(title: "Fichiers téléchargés en local", symbol: "arrow.down.circle"),
             .init(title: "Libérer sans supprimer", symbol: "icloud.and.arrow.up"),
             .init(title: "Toujours dans iCloud", symbol: "checkmark.icloud")]
        case .carte:
            [.init(title: "Vue en anneaux, dossier par dossier", symbol: "chart.pie"),
             .init(title: "Gros et anciens fichiers", symbol: "doc.badge.clock"),
             .init(title: "Lecture seule : rien n'est supprimé", symbol: "lock")]
        case .applications:
            [.init(title: "Désinstallation complète", symbol: "xmark.app"),
             .init(title: "Restes d'applis supprimées", symbol: "magnifyingglass"),
             .init(title: "Éléments de démarrage", symbol: "power")]
        }
    }

    var hero: HeroKind {
        switch self {
        case .analyse: .orb
        case .developpeur: .code
        case .corbeilles: .trash
        case .carte: .diskRing
        default: .block
        }
    }

    /// Ce que le bouton d'analyse parcourt, ou `nil` si le module n'existe pas encore.
    var scope: ScanScope? {
        switch self {
        case .analyse: .all
        case .systeme: .categories([.systemJunk])
        case .developpeur: .categories([.developer])
        default: nil
        }
    }

    /// Module utilisable (la carte du disque n'a pas de règles : elle ne nettoie rien).
    var isAvailable: Bool { scope != nil || self == .carte }

    /// Petite ligne sous l'objet en verre.
    var caption: String {
        switch self {
        case .analyse: "Toutes les règles, en une seule analyse"
        case .systeme, .developpeur: "Les éléments « sûrs » sont cochés d'office"
        case .mail, .corbeilles, .icloud: "Module à venir"
        case .carte: "Taille en direct pendant l'analyse"
        case .applications: "Module à venir"
        }
    }
}
