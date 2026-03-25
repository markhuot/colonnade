import Foundation
@preconcurrency import UserNotifications

final class NativeWorkspaceEventNotifier: NSObject, WorkspaceEventNotifying, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NativeWorkspaceEventNotifier()

    struct NotificationTarget: Equatable, Sendable {
        let connection: WorkspaceConnection
        let sessionID: String
    }

    private let center = UNUserNotificationCenter.current()
    private let deliveredNotificationCategory = "workspace-event"
    private let notificationTargetKey = "notification-target"
    private var notificationTargetHandler: (@MainActor @Sendable (NotificationTarget) async -> Void)?

    private override init() {
        super.init()
        center.delegate = self
        configureCategories()
    }

    @MainActor
    func setNotificationTargetHandler(_ handler: (@MainActor @Sendable (NotificationTarget) async -> Void)?) {
        notificationTargetHandler = handler
    }

    @MainActor
    func handleNotificationTarget(_ target: NotificationTarget) async {
        guard let handler = notificationTargetHandler else { return }
        await handler(target)
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let target = notificationTarget(from: response.notification.request.content.userInfo) else {
            return
        }

        Task { @MainActor in
            await handleNotificationTarget(target)
        }
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
        content.categoryIdentifier = deliveredNotificationCategory
        content.userInfo = [notificationTargetKey: notificationTargetPayload(for: event)]

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
        case let .sessionStopped(_, _, sessionTitle):
            return "\(sessionTitle) is no longer running."
        case let .permissionRequested(_, _, sessionTitle, permission):
            return "\(sessionTitle) needs permission: \(permission)."
        case let .questionAsked(_, _, sessionTitle, question):
            return "\(sessionTitle) asks: \(question)"
        }
    }

    private func configureCategories() {
        let category = UNNotificationCategory(
            identifier: deliveredNotificationCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func notificationTargetPayload(for event: WorkspaceEventNotification) -> [String: String] {
        [
            "serverURL": event.connection.serverURL.absoluteString,
            "directory": event.connection.directory,
            "sessionID": event.sessionID
        ]
    }

    private func notificationTarget(from userInfo: [AnyHashable: Any]) -> NotificationTarget? {
        guard let payload = userInfo[notificationTargetKey] as? [String: String],
              let serverURLText = payload["serverURL"],
              let serverURL = URL(string: serverURLText),
              let directory = payload["directory"],
              let sessionID = payload["sessionID"] else {
            return nil
        }

        return NotificationTarget(
            connection: WorkspaceConnection(serverURL: serverURL, directory: directory),
            sessionID: sessionID
        )
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
