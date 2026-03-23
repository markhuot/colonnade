import AppKit

@MainActor
enum OpenCodeAppModelFactory {
    static func makeRootAppModel(
        build: @MainActor () -> OpenCodeAppModel = {
            OpenCodeAppModel(restoresLastSelectedDirectory: false)
        },
        directoryChooserFactory: @escaping @MainActor (OpenCodeAppModel) -> (@MainActor () -> Void) = makeDirectoryChooser(for:)
    ) -> OpenCodeAppModel {
        let appState = build()
        appState.setDirectoryChooser(directoryChooserFactory(appState))
        return appState
    }

    static func makeSessionWindowAppModel(
        context: SessionWindowContext,
        directoryChooserFactory: @escaping @MainActor (OpenCodeAppModel) -> (@MainActor () -> Void) = makeDirectoryChooser(for:)
    ) -> OpenCodeAppModel {
        let appState = OpenCodeAppModel(
            persistsWorkspacePaneState: false,
            initialServerURL: context.connection.serverURL,
            initialDirectory: context.connection.directory,
            initialOpenSessionIDs: [context.sessionID]
        )
        appState.setDirectoryChooser(directoryChooserFactory(appState))
        return appState
    }

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
