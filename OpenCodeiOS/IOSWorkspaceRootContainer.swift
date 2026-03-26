import SwiftUI

struct IOSWorkspaceRootContainer: View {
    @EnvironmentObject private var modelPreferencesController: ModelPreferencesController
    @Environment(\.openCodeTheme) private var theme
    @StateObject private var appState: OpenCodeAppModel

    init() {
        _appState = StateObject(wrappedValue: OpenCodeAppModelFactory.makeRootAppModel())
    }

    var body: some View {
        IOSRootView()
            .environmentObject(appState)
            .task {
                appState.configurePreferredDefaultModelPersistence(
                    provider: { modelPreferencesController.preferredDefaultModelReference },
                    setter: { modelPreferencesController.setPreferredDefaultModelReference($0) }
                )
                await appState.bootstrapIfNeeded()
            }
            .background(theme.windowBackground.ignoresSafeArea())
    }
}
