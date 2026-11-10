import AppKit
import CleanmacCore
import SwiftUI

/// Écran d'accueil du premier lancement : explique et demande l'accès complet au disque.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onContinue: () -> Void

    private var granted: Bool { model.fullDiskAccess == .granted }

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: granted ? "checkmark.shield.fill" : "externaldrive.badge.questionmark")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(granted ? .green : .accentColor)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: granted)

            VStack(spacing: 12) {
                Text("Bienvenue dans Cleanmac")
                    .font(.largeTitle.bold())
                Text("Pour trouver les caches, journaux et fichiers inutiles dans tout votre Mac, Cleanmac a besoin de l'« Accès complet au disque ».")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560)
            }

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Cliquez sur « Ouvrir les réglages ».")
                step(2, "Activez « Cleanmac » dans la liste (ajoutez-le avec + s'il n'y est pas).")
                step(3, "Revenez ici : l'autorisation est détectée toute seule.")
            }
            .font(.title3)
            .padding(20)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

            Label(granted ? "Accès complet au disque accordé" : "Accès complet au disque non accordé",
                  systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(granted ? .green : .orange)

            HStack(spacing: 16) {
                if !granted {
                    Button("Ouvrir les réglages") {
                        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Button(granted ? "Continuer" : "Plus tard", action: onContinue)
                    .keyboardShortcut(granted ? .defaultAction : .cancelAction)
            }
            .controlSize(.extraLarge)

            Text("Cleanmac ne supprime rien sans votre accord : tout passe par la Corbeille, après un écran de vérification.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Détection de l'autorisation tant que l'écran est affiché.
            while !Task.isCancelled {
                model.refreshFullDiskAccess()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.title3.bold().monospacedDigit())
                .frame(width: 30, height: 30)
                .background(Circle().fill(.tint.opacity(0.2)))
            Text(text)
        }
    }
}
