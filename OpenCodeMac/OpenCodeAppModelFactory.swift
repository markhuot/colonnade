import AppKit

enum OpenCodeAppModelFactory {
    @MainActor
    static let localServerPreferencesController = LocalServerPreferencesController()
    static let workspaceEventNotifier = NativeWorkspaceEventNotifier.shared
    static let liveStoreRegistry = WorkspaceLiveStoreRegistry(notifier: workspaceEventNotifier)
    static let workspaceSyncRegistry = WorkspaceSyncRegistry(storeRegistry: liveStoreRegistry)

    private static func resolvedLocalServerExecutablePath() -> String {
        NSString(string: LocalServerPreferencesController.loadOpencodeExecutablePath()).expandingTildeInPath
    }

    @MainActor
    static func makeRootAppModel(
        build: @MainActor () -> OpenCodeAppModel = {
            OpenCodeAppModel(
                syncRegistry: workspaceSyncRegistry,
                restoresLastSelectedDirectory: false,
                localServerExecutablePathProvider: {
                    resolvedLocalServerExecutablePath()
                }
            )
        },
        directoryChooserFactory: @escaping @MainActor (OpenCodeAppModel) -> (@MainActor () -> Void) = makeDirectoryChooser(for:)
    ) -> OpenCodeAppModel {
        let appState = build()
        appState.setDirectoryChooser(directoryChooserFactory(appState))
        return appState
    }

    @MainActor
    static func makeSessionWindowAppModel(
        context: SessionWindowContext,
        directoryChooserFactory: @escaping @MainActor (OpenCodeAppModel) -> (@MainActor () -> Void) = makeDirectoryChooser(for:)
    ) -> OpenCodeAppModel {
        let appState = OpenCodeAppModel(
            syncRegistry: workspaceSyncRegistry,
            persistsWorkspacePaneState: false,
            initialServerURL: context.connection.serverURL,
            initialDirectory: context.connection.directory,
            initialOpenSessionIDs: [context.sessionID]
        )
        appState.setDirectoryChooser(directoryChooserFactory(appState))
        return appState
    }

    @MainActor
    static func makePreferencesAppModel(connection: WorkspaceConnection? = WorkspaceCommandCenter.shared.currentConnection) -> OpenCodeAppModel {
        OpenCodeAppModel(
            syncRegistry: workspaceSyncRegistry,
            restoresLastSelectedDirectory: connection == nil,
            initialServerURL: connection?.serverURL ?? OpenCodeAppModel.defaultServerURL,
            initialDirectory: connection?.directory,
            localServerExecutablePathProvider: {
                resolvedLocalServerExecutablePath()
            },
            directoryChooser: {}
        )
    }

    @MainActor
    static func makeDirectoryChooser(for appState: OpenCodeAppModel) -> @MainActor () -> Void {
        {
            let panel = NSOpenPanel()
            panel.message = "Choose a project folder for opencode sessions"
            panel.prompt = "Open Project"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false

            guard panel.runModal() == .OK, let url = panel.url else { return }
            Task {
                await appState.load(directory: url.path)
            }
        }
    }
}
