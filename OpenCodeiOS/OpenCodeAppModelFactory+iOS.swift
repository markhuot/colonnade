import SwiftUI

enum OpenCodeAppModelFactory {
    static let workspaceEventNotifier = NativeWorkspaceEventNotifier.shared
    static let liveStoreRegistry = WorkspaceLiveStoreRegistry(notifier: workspaceEventNotifier)
    static let workspaceSyncRegistry = WorkspaceSyncRegistry(storeRegistry: liveStoreRegistry)

    @MainActor
    static func makeRootAppModel(
        build: @MainActor () -> OpenCodeAppModel = {
            OpenCodeAppModel(
                syncRegistry: workspaceSyncRegistry,
                restoresLastSelectedDirectory: true,
                supportsLocalServer: false
            )
        },
        directoryChooserFactory: @escaping @MainActor (OpenCodeAppModel) -> (@MainActor () -> Void) = makeDirectoryChooser(for:)
    ) -> OpenCodeAppModel {
        let appState = build()
        appState.setDirectoryChooser(directoryChooserFactory(appState))
        workspaceEventNotifier.setNotificationTargetHandler { target in
            if appState.workspaceConnection != target.connection {
                await appState.updatePreferencesConnection(target.connection)
            }

            appState.openSession(target.sessionID)
            appState.requestSessionCenter(for: target.sessionID)
        }
        return appState
    }

    @MainActor
    static func makeDirectoryChooser(for appState: OpenCodeAppModel) -> @MainActor () -> Void {
        {
            appState.errorMessage = "Local projects aren't available on iOS. Connect to a remote opencode server instead."
        }
    }
}
