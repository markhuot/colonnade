import AppKit
@preconcurrency import UserNotifications

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

final class NativeWorkspaceEventNotifier: NSObject, WorkspaceEventNotifying, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NativeWorkspaceEventNotifier()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func notify(_ event: WorkspaceEventNotification) {
        Task {
            await deliver(event)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func deliver(_ event: WorkspaceEventNotification) async {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else { return }
            } catch {
                return
            }
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return
        @unknown default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title(for: event)
        content.body = body(for: event)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await add(request)
    }

    private func title(for event: WorkspaceEventNotification) -> String {
        switch event {
        case .sessionStopped:
            return "Session Stopped"
        case .permissionRequested:
            return "Permission Required"
        case .questionAsked:
            return "Question Asked"
        }
    }

    private func body(for event: WorkspaceEventNotification) -> String {
        switch event {
        case let .sessionStopped(_, sessionTitle):
            return "\(sessionTitle) is no longer running."
        case let .permissionRequested(_, sessionTitle, permission):
            return "\(sessionTitle) needs permission: \(permission)."
        case let .questionAsked(_, sessionTitle, question):
            return "\(sessionTitle) asks: \(question)"
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
