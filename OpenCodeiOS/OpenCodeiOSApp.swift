import SwiftUI

@main
struct OpenCodeiOSApp: App {
    @StateObject private var themeController = ThemeController(supportsTheme: { $0.isSupported })
    @StateObject private var modelPreferencesController = ModelPreferencesController()

    var body: some Scene {
        WindowGroup {
            IOSWorkspaceRootContainer()
                .environmentObject(themeController)
                .environmentObject(modelPreferencesController)
                .environment(\.openCodeTheme, themeController.selectedTheme)
                .preferredColorScheme(themeController.selectedTheme.preferredColorScheme)
        }
    }
}
