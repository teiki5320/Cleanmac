import SwiftUI

@main
struct CleanmacApp: App {
    @State private var model = AppModel()
    @AppStorage(ComfortKeys.menuBar) private var showMenuBar = true

    var body: some Scene {
        // Une seule fenêtre : « Ouvrir Cleanmac » (barre des menus) la ramène au lieu d'en créer une autre.
        Window("Cleanmac", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: "sparkles")
                .accessibilityLabel("Cleanmac")
        }
        .menuBarExtraStyle(.window)
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
