import SwiftUI

struct IOSWorkspaceRootContainer: View {
    @EnvironmentObject private var modelPreferencesController: ModelPreferencesController
    @Environment(\.openCodeTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
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
            .onChange(of: scenePhase) { _, newValue in
                switch newValue {
                case .active:
                    appState.noteAppDidBecomeActive()
                case .background:
                    appState.noteAppDidEnterBackground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .background(theme.windowBackground.ignoresSafeArea())
    }
}
