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
        static let sidebarWidth: CGFloat = 264
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

/// Couleurs nommées hors modules (jauges), toutes ici.
enum ThemeColors {
    /// Jauge du disque : début, fin normale, fin quand le disque est presque plein.
    static let diskStart = Color(hex: 0x5EEAD4)
    static let diskEnd = Color(hex: 0x38BDF8)
    static let diskAlert = Color(hex: 0xF97316)
    /// Mémoire : applis, système (câblée), compressée, fichiers en cache.
    static let memoryApps = Color(hex: 0xFDE68A)
    static let memoryWired = Color(hex: 0xF97316)
    static let memoryCompressed = Color(hex: 0xA3E635)
    static let memoryCached = Color.white.opacity(0.3)
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
    case doublons
    case purgeable
    case applications
    case maintenance
    case historique

    var id: String { rawValue }

    static let cleaning: [Module] = [.analyse, .systeme, .developpeur, .mail, .corbeilles, .icloud]
    static let spaceAndApps: [Module] = [.carte, .doublons, .purgeable, .applications]
    static let care: [Module] = [.maintenance, .historique]

    var title: String {
        switch self {
        case .analyse: "Analyse complète"
        case .systeme: "Fichiers système"
        case .developpeur: "Développeur"
        case .mail: "Mail"
        case .corbeilles: "Vider les Corbeilles"
        case .icloud: "iCloud Drive"
        case .carte: "Carte du disque"
        case .doublons: "Doublons"
        case .purgeable: "Espace purgeable"
        case .applications: "Applications"
        case .maintenance: "Entretien"
        case .historique: "Historique"
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
        case .doublons: "doc.on.doc"
        case .purgeable: "externaldrive.badge.timemachine"
        case .applications: "square.grid.2x2"
        case .maintenance: "wrench.and.screwdriver"
        case .historique: "clock.arrow.circlepath"
        }
    }

    var palette: ModulePalette {
        switch self {
        case .analyse:
            // Magenta-rose propre à Cleanmac (voisin de l'esprit CleanMyMac, sans reprendre ses couleurs).
            ModulePalette(deep: Color(hex: 0x2E0723), mid: Color(hex: 0xD0237A), light: Color(hex: 0xFBA5D0), accent: Color(hex: 0x9D4EDD))
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
        case .doublons:
            ModulePalette(deep: Color(hex: 0x1B0B33), mid: Color(hex: 0x7E22CE), light: Color(hex: 0xD8B4FE), accent: Color(hex: 0x2DD4BF))
        case .purgeable:
            ModulePalette(deep: Color(hex: 0x05202A), mid: Color(hex: 0x0E7490), light: Color(hex: 0x67E8F9), accent: Color(hex: 0x34D399))
        case .applications:
            ModulePalette(deep: Color(hex: 0x022C22), mid: Color(hex: 0x059669), light: Color(hex: 0x6EE7B7), accent: Color(hex: 0x22D3EE))
        case .maintenance:
            ModulePalette(deep: Color(hex: 0x1C1405), mid: Color(hex: 0xA16207), light: Color(hex: 0xFDE68A), accent: Color(hex: 0x84CC16))
        case .historique:
            ModulePalette(deep: Color(hex: 0x111827), mid: Color(hex: 0x475569), light: Color(hex: 0xCBD5E1), accent: Color(hex: 0x818CF8))
        }
    }

    var summary: String {
        switch self {
        case .analyse:
            "Parcourt toutes les règles d'un coup : fichiers système, développement, Mail et Corbeilles, y compris les éléments « à vérifier ». Rien ne part sans votre vérification."
        case .systeme:
            "Caches des applications, journaux, rapports de plantage et états de fenêtres enregistrés."
        case .developpeur:
            "Xcode, simulateurs, Gradle, Flutter, npm, Homebrew… Les modèles d'IA sont montrés mais jamais cochés d'office."
        case .mail:
            "Pièces jointes téléchargées par Mail et caches de Thunderbird."
        case .corbeilles:
            "La Corbeille du Mac et celles des disques externes, réunies au même endroit. Vider est définitif : rien n'est coché d'office. Photos garde ses photos supprimées dans son propre album : Cleanmac ouvre Photos pour que vous le vidiez."
        case .icloud:
            "Libère les fichiers d'iCloud Drive téléchargés sur le Mac, sans les supprimer d'iCloud."
        case .doublons:
            "Retrouve les fichiers au contenu identique dans votre dossier personnel, suggère l'exemplaire à garder et met à la Corbeille les copies que vous cochez."
        case .carte:
            "Voyez ce qui prend la place, dossier par dossier : cliquez sur un anneau pour descendre, au centre pour remonter."
        case .purgeable:
            "L'espace que macOS garde en réserve : instantanés Time Machine locaux et fichiers qu'il peut libérer seul. Voyez ce qu'il représente et purgez les instantanés."
        case .applications:
            "Désinstallez une appli avec tous ses fichiers, retrouvez les restes d'applis supprimées, gérez le démarrage et voyez les mises à jour."
        case .maintenance:
            "Petits soins du système : cache DNS, index Spotlight, services de lancement, mémoire vive. Et les applis qui en consomment le plus."
        case .historique:
            "Tout ce que Cleanmac a nettoyé, quand, et combien de place a été libérée ou mise à la Corbeille."
        }
    }

    var features: [ModuleFeature] {
        switch self {
        case .analyse:
            [.init(title: "Fichiers système, Mail et Corbeilles", symbol: "doc.text"),
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
             .init(title: "Les plus gros fichiers, avec filtres", symbol: "doc.badge.clock"),
             .init(title: "Lecture seule : rien n'est supprimé", symbol: "lock")]
        case .doublons:
            [.init(title: "Comparaison du contenu, pas du nom", symbol: "number"),
             .init(title: "Vous choisissez l'exemplaire à garder", symbol: "checkmark.shield"),
             .init(title: "Copies à la Corbeille, revérifiées avant", symbol: "trash")]
        case .purgeable:
            [.init(title: "Instantanés Time Machine locaux", symbol: "clock.arrow.circlepath"),
             .init(title: "Espace libre réel et purgeable", symbol: "internaldrive"),
             .init(title: "Purge via l'outil d'aide", symbol: "lock.shield")]
        case .applications:
            [.init(title: "Désinstallation complète", symbol: "xmark.app"),
             .init(title: "Restes d'applis supprimées", symbol: "magnifyingglass"),
             .init(title: "Démarrage et mises à jour", symbol: "power")]
        case .maintenance:
            [.init(title: "Cache DNS et Spotlight", symbol: "network"),
             .init(title: "Services de lancement", symbol: "arrow.triangle.2.circlepath"),
             .init(title: "Mémoire vive", symbol: "memorychip")]
        case .historique:
            [.init(title: "Chaque nettoyage, en détail", symbol: "list.bullet"),
             .init(title: "Total libéré", symbol: "sum"),
             .init(title: "Retrouver un élément dans la Corbeille", symbol: "trash")]
        }
    }

    var hero: HeroKind {
        switch self {
        case .analyse: .orb
        case .developpeur: .code
        case .corbeilles: .trash
        case .carte, .purgeable: .diskRing
        case .maintenance: .orb
        default: .block
        }
    }

    /// Règles parcourues par le bouton d'analyse (modules à règles uniquement).
    var scope: ScanScope? {
        switch self {
        case .analyse: .all
        case .systeme: .categories([.systemJunk])
        case .developpeur: .categories([.developer])
        case .mail: .categories([.mail])
        case .corbeilles: .categories([.trash])
        default: nil
        }
    }

    /// Le module a-t-il le gros bouton rond d'analyse ? (Maintenance et Historique s'affichent directement.)
    var hasScanButton: Bool { self != .maintenance && self != .historique }

    /// Petite ligne sous l'objet en verre.
    var caption: String {
        switch self {
        case .analyse: "Toutes les règles, en une seule analyse"
        case .systeme, .developpeur, .mail: "Les éléments « sûrs » sont cochés d'office"
        case .corbeilles: "Rien n'est coché d'office : vider est définitif"
        case .icloud: "Fichiers de plus de 1 Mo, déjà envoyés dans iCloud"
        case .carte: "Taille en direct pendant l'analyse"
        case .doublons: "Fichiers de plus de 1 Mo, hors Bibliothèque"
        case .purgeable: "Disque de démarrage"
        case .applications: "/Applications et ~/Applications"
        case .maintenance, .historique: ""
        }
    }
}
