import SwiftUI

@main
struct CleanmacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Cleanmac") {
            RootView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 600)
        }
        .defaultSize(width: 980, height: 720)
    }
}

/// Écran d'accueil au premier lancement, puis écran principal.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("accueilTermine") private var onboardingDone = false

    var body: some View {
        Group {
            if onboardingDone {
                FoundationsView()
            } else {
                OnboardingView { onboardingDone = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshFullDiskAccess()
            model.helper.refresh()
        }
    }
}
