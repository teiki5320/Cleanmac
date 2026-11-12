import AppKit
import CleanmacCore
import SwiftUI

/// Écran d'accueil du premier lancement, en style verre : explique et demande l'accès complet au disque.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onContinue: () -> Void

    private var granted: Bool { model.fullDiskAccess == .granted }
    private let palette = Module.analyse.palette

    var body: some View {
        HStack(spacing: 48) {
            HeroView(module: .analyse)
                .scaleEffect(0.8)
                .frame(width: 330, height: 360)
            VStack(alignment: .leading, spacing: 22) {
                Text("Bienvenue dans Cleanmac")
                    .font(Theme.Typo.title)
                    .minimumScaleFactor(0.7)
                Text("Pour trouver les caches, journaux et fichiers inutiles dans tout votre Mac, Cleanmac a besoin de l'« Accès complet au disque ».")
                    .font(Theme.Typo.body)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Cliquez sur « Ouvrir les réglages ».")
                    step(2, "Activez « Cleanmac » dans la liste (ajoutez-le avec + s'il n'y est pas).")
                    step(3, "Revenez ici : l'autorisation est détectée toute seule.")
                }
                .glassPanel()
                Label(granted ? "Accès complet au disque accordé" : "Accès complet au disque non accordé",
                      systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(granted ? .green : .orange)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: granted)
                HStack(spacing: 14) {
                    if !granted {
                        Button {
                            NSWorkspace.shared.open(FullDiskAccess.settingsURL)
                        } label: {
                            Text("Ouvrir les réglages").padding(.horizontal, 8)
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                    Button {
                        onContinue()
                    } label: {
                        Text(granted ? "Continuer" : "Plus tard").padding(.horizontal, 8)
                    }
                    .keyboardShortcut(granted ? .defaultAction : .cancelAction)
                    .buttonStyle(granted ? AnyPrimitiveButtonStyle(.borderedProminent) : AnyPrimitiveButtonStyle(.bordered))
                }
                .controlSize(.extraLarge)
                Text("Cleanmac ne supprime rien sans votre accord : un écran de vérification précède chaque nettoyage, et tout passe par la Corbeille par défaut.")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ModuleBackground(palette: palette) }
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.colorScheme, .dark)
        .tint(palette.mid)
        .task {
            // Détection de l'autorisation tant que l'écran est affiché.
            while !Task.isCancelled {
                model.refreshFullDiskAccess()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.18)))
            Text(text).font(.system(size: 18))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Style de bouton choisi à l'exécution.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
