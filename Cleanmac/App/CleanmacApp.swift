import SwiftUI

@main
struct CleanmacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Cleanmac") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
    }
}

/// Écran d'accueil au premier lancement, puis fenêtre principale en style verre.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("accueilTermine") private var onboardingDone = false

    var body: some View {
        Group {
            if onboardingDone {
                MainWindowView()
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
