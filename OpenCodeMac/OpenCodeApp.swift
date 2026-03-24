import AppKit
import Combine
import SwiftUI

@main
struct OpenCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var themeController = ThemeController(supportsTheme: { $0.isSupported })
    @StateObject private var modelPreferencesController = ModelPreferencesController()
    @StateObject private var localServerPreferencesController = OpenCodeAppModelFactory.localServerPreferencesController

    var body: some Scene {
        WindowGroup("Colonnade", id: "workspace-root") {
            WorkspaceRootContainer()
                .environmentObject(themeController)
                .environmentObject(modelPreferencesController)
                .environmentObject(localServerPreferencesController)
                .environment(\.openCodeTheme, themeController.selectedTheme)
                .preferredColorScheme(themeController.selectedTheme.preferredColorScheme)
        }
        .defaultSize(width: 1440, height: 920)

        WindowGroup("Session", id: "session-window", for: SessionWindowContext.self) { $context in
            if let context {
                SessionWindowContainer(context: context)
                    .environmentObject(themeController)
                    .environmentObject(modelPreferencesController)
                    .environmentObject(localServerPreferencesController)
                    .environment(\.openCodeTheme, themeController.selectedTheme)
                    .preferredColorScheme(themeController.selectedTheme.preferredColorScheme)
            } else {
                InvalidSessionWindowView()
            }
        }
        .defaultSize(width: 760, height: 920)

        Settings {
            PreferencesView()
                .environmentObject(themeController)
                .environmentObject(modelPreferencesController)
                .environmentObject(localServerPreferencesController)
                .environment(\.openCodeTheme, themeController.selectedTheme)
                .preferredColorScheme(themeController.selectedTheme.preferredColorScheme)
        }
    }

    var commands: some Commands {
        WorkspaceCommands()
    }
}
