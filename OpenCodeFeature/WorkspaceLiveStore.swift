import Combine
import Foundation
import OSLog

protocol WorkspaceEventNotifying: Sendable {
    func notify(_ event: WorkspaceEventNotification)
}

enum WorkspaceEventNotification: Equatable, Sendable {
    case sessionStopped(sessionID: String, sessionTitle: String)
    case permissionRequested(sessionID: String, sessionTitle: String, permission: String)
    case questionAsked(sessionID: String, sessionTitle: String, question: String)
}

struct NoopWorkspaceEventNotifier: WorkspaceEventNotifying {
    func notify(_ event: WorkspaceEventNotification) {}
}

@MainActor
final class SessionLiveState: ObservableObject, Identifiable, @unchecked Sendable {
    private struct BufferedPartDelta: Sendable {
        let field: MessagePartDeltaField
        let delta: String
    }

    private let logger = Logger(subsystem: "ai.opencode.app", category: "workspace-sync")

    let id: String

    @Published private(set) var session: SessionDisplay?
    @Published private(set) var messages: [MessageEnvelope] = []
    @Published private(set) var todos: [SessionTodo] = []
    @Published private(set) var questions: [QuestionRequest] = []
    @Published private(set) var permissions: [PermissionRequest] = []

    private var sessionModel: OpenCodeSession?
    private var persistedSession: SessionDisplay?
    private var status: SessionStatus?
    private var pendingPartDeltas: [String: [BufferedPartDelta]] = [:]

    var sessionTitle: String {
        sessionModel?.title ?? persistedSession?.title ?? session?.title ?? id
    }

    init(id: String) {
        self.id = id
    }

    func applySessionModel(_ session: OpenCodeSession) {
        sessionModel = session
        persistedSession = nil
    }

    func applyPersistedSession(_ session: SessionDisplay) {
        persistedSession = session
    }

    func applyStatus(_ status: SessionStatus?) {
        self.status = status
    }

    func replaceMessages(_ messages: [MessageEnvelope]) {
        self.messages = messages.sorted { $0.info.time.created < $1.info.time.created }
    }

    func replaceTodos(_ todos: [SessionTodo]) {
        self.todos = todos
    }

    func replaceQuestions(_ questions: [QuestionRequest]) {
        self.questions = questions
    }

    func replacePermissions(_ permissions: [PermissionRequest]) {
        self.permissions = permissions
    }

    func upsertMessageInfo(_ info: MessageInfo) {
        var updatedMessages = messages
        if let messageIndex = updatedMessages.firstIndex(where: { $0.id == info.id }) {
            let existingParts = updatedMessages[messageIndex].parts
            updatedMessages[messageIndex] = MessageEnvelope(info: info, parts: existingParts)
        } else {
            updatedMessages.append(MessageEnvelope(info: info, parts: []))
            updatedMessages.sort { $0.info.time.created < $1.info.time.created }
        }
        messages = updatedMessages
        logger.notice(
            "Published message info sessionID=\(self.id, privacy: .public) messageID=\(info.id, privacy: .public) totalMessages=\(updatedMessages.count, privacy: .public)"
        )
    }

    func applyMessagePart(_ part: MessagePart) -> MessagePart? {
        let resolvedPart = resolvedPartApplyingPendingDeltas(part)

        guard let messageID = resolvedPart.messageID else {
            logger.notice("Direct part apply miss sessionID=\(self.id, privacy: .public) partID=\(part.id, privacy: .public) reason=missing-message-id")
            return nil
        }

        var updatedMessages = messages
        ensureMessageShell(in: &updatedMessages, messageID: messageID, createdAtMS: resolvedPart.time?.start)

        guard let messageIndex = updatedMessages.firstIndex(where: { $0.id == messageID }) else {
            logger.notice(
                "Direct part apply miss sessionID=\(self.id, privacy: .public) messageID=\(messageID, privacy: .public) partID=\(resolvedPart.id, privacy: .public) reason=message-not-loaded loadedMessages=\(updatedMessages.count, privacy: .public)"
            )
            return nil
        }

        var message = updatedMessages[messageIndex]
        if let partIndex = message.parts.firstIndex(where: { $0.id == resolvedPart.id }) {
            message.parts[partIndex] = resolvedPart
        } else {
            message.parts.append(resolvedPart)
            message.parts.sort(by: Self.partSort)
        }
        updatedMessages[messageIndex] = message
        messages = updatedMessages
        logger.notice(
            "Published message part sessionID=\(self.id, privacy: .public) messageID=\(messageID, privacy: .public) partID=\(resolvedPart.id, privacy: .public) partType=\(resolvedPart.type.rawString, privacy: .public) messageParts=\(message.parts.count, privacy: .public)"
        )
        return resolvedPart
    }

    func applyMessagePartDelta(partID: String, field: MessagePartDeltaField, delta: String) -> Bool {
        var updatedMessages = messages

        guard let messageIndex = updatedMessages.firstIndex(where: { message in
            message.parts.contains(where: { $0.id == partID })
        }) else {
            pendingPartDeltas[partID, default: []].append(BufferedPartDelta(field: field, delta: delta))
            logger.notice(
                "Buffered part delta sessionID=\(self.id, privacy: .public) partID=\(partID, privacy: .public) field=\(field.rawString, privacy: .public) deltaBytes=\(delta.utf8.count, privacy: .public) bufferedCount=\(self.pendingPartDeltas[partID]?.count ?? 0, privacy: .public)"
            )
            return true
        }

        var message = updatedMessages[messageIndex]
        guard let partIndex = message.parts.firstIndex(where: { $0.id == partID }) else {
            return false
        }

        var part = message.parts[partIndex]
        part.apply(delta: delta, to: field)
        message.parts[partIndex] = part
        updatedMessages[messageIndex] = message
        messages = updatedMessages
        logger.notice(
            "Published part delta sessionID=\(self.id, privacy: .public) partID=\(partID, privacy: .public) field=\(field.rawString, privacy: .public) visibleTextBytes=\(message.visibleText.utf8.count, privacy: .public)"
        )
        return true
    }

    func removeMessagePart(partID: String) -> Bool {
        let hadBufferedDeltas = pendingPartDeltas.removeValue(forKey: partID) != nil
        var updatedMessages = messages

        guard let messageIndex = updatedMessages.firstIndex(where: { message in
            message.parts.contains(where: { $0.id == partID })
        }) else {
            return hadBufferedDeltas
        }

        var message = updatedMessages[messageIndex]
        let originalCount = message.parts.count
        message.parts.removeAll { $0.id == partID }
        guard message.parts.count != originalCount else { return hadBufferedDeltas }
        updatedMessages[messageIndex] = message
        messages = updatedMessages
        return true
    }

    func removeMessage(messageID: String) -> Bool {
        let originalCount = messages.count
        let updatedMessages = messages.filter { $0.id != messageID }
        guard updatedMessages.count != originalCount else { return false }
        messages = updatedMessages
        return true
    }

    private func ensureMessageShell(in messages: inout [MessageEnvelope], messageID: String, createdAtMS: Double?) {
        guard !messages.contains(where: { $0.id == messageID }) else { return }

        let created = createdAtMS ?? Date().timeIntervalSince1970 * 1000
        let info = MessageInfo(
            id: messageID,
            sessionID: id,
            role: .assistant,
            time: .init(created: created, completed: nil),
            parentID: nil,
            agent: nil,
            model: nil,
            modelID: nil,
            providerID: nil,
            mode: nil,
            path: nil,
            cost: nil,
            tokens: nil,
            finish: nil,
            summary: nil,
            error: nil
        )
        messages.append(MessageEnvelope(info: info, parts: []))
        messages.sort { $0.info.time.created < $1.info.time.created }
    }

    private func resolvedPartApplyingPendingDeltas(_ part: MessagePart) -> MessagePart {
        guard let pending = pendingPartDeltas.removeValue(forKey: part.id), !pending.isEmpty else {
            return part
        }

        var resolvedPart = part
        for delta in pending {
            resolvedPart.apply(delta: delta.delta, to: delta.field)
        }
        return resolvedPart
    }

    func recomputeDisplay(modelContextLimits: [ModelContextKey: Int]) {
        guard let sessionModel else {
            session = persistedSession
            return
        }

        let todoProgress = TodoProgress.from(todos)
        let hasPendingPermission = !permissions.isEmpty
        let updatedAtMS = max(sessionModel.time.updated, messages.last?.info.time.created ?? 0)

        session = SessionDisplay(
            id: sessionModel.id,
            title: sessionModel.title,
            createdAtMS: sessionModel.time.created,
            updatedAtMS: updatedAtMS,
            parentID: sessionModel.parentID,
            status: status,
            hasPendingPermission: hasPendingPermission,
            todoProgress: todoProgress,
            contextUsageText: contextUsageText(modelContextLimits: modelContextLimits),
            isArchived: sessionModel.time.archived != nil
        )
    }

    private func contextUsageText(modelContextLimits: [ModelContextKey: Int]) -> String? {
        guard let payload = messages.last(where: { $0.totalTokens != nil && $0.info.modelContextKey != nil }),
              let modelKey = payload.info.modelContextKey,
              let usedTokens = payload.totalTokens,
              let limit = modelContextLimits[modelKey],
              limit > 0 else {
            return nil
        }

        let percentage = min(100, Int((Double(usedTokens) / Double(limit) * 100).rounded()))
        return "\(percentage)% used"
    }

    private static func partSort(_ lhs: MessagePart, _ rhs: MessagePart) -> Bool {
        let lhsStart = lhs.time?.start ?? .leastNormalMagnitude
        let rhsStart = rhs.time?.start ?? .leastNormalMagnitude
        if lhsStart == rhsStart {
            return lhs.id < rhs.id
        }
        return lhsStart < rhsStart
    }
}

@MainActor
final class WorkspaceLiveStore: ObservableObject, @unchecked Sendable {
    let connection: WorkspaceConnection
    private let logger = Logger(subsystem: "ai.opencode.app", category: "workspace-sync")

    var directory: String { connection.directory }

    @Published private(set) var sessions: [SessionDisplay] = []
    @Published private(set) var paneStates: [String: SessionPaneState] = [:]

    private var notifier: any WorkspaceEventNotifying
    private var modelContextLimits: [ModelContextKey: Int] = [:]
    private var sessionStates: [String: SessionLiveState] = [:]
    private var previousStatusBySessionID: [String: SessionStatus] = [:]
    private var questionRequestIDsBySessionID: [String: Set<String>] = [:]
    private var permissionRequestIDsBySessionID: [String: Set<String>] = [:]
    private var hasEstablishedNotificationBaseline = false

    init(connection: WorkspaceConnection, notifier: any WorkspaceEventNotifying = NoopWorkspaceEventNotifier()) {
        self.connection = connection
        self.notifier = notifier
    }

    func setNotifier(_ notifier: any WorkspaceEventNotifying) {
        self.notifier = notifier
    }

    func sessionState(for sessionID: String) -> SessionLiveState {
        if let existing = sessionStates[sessionID] {
            return existing
        }

        let state = SessionLiveState(id: sessionID)
        sessionStates[sessionID] = state
        return state
    }

    func existingSessionState(for sessionID: String) -> SessionLiveState? {
        sessionStates[sessionID]
    }

    func allMessagesBySession(for sessionIDs: [String]) -> [String: [MessageEnvelope]] {
        Dictionary(uniqueKeysWithValues: sessionIDs.compactMap { sessionID in
            guard let state = sessionStates[sessionID] else { return nil }
            return (sessionID, state.messages)
        })
    }

    func sessionDisplay(for sessionID: String) -> SessionDisplay? {
        sessionStates[sessionID]?.session
    }

    func setModelContextLimits(_ limits: [ModelContextKey: Int]) {
        modelContextLimits = limits
        refreshSessionsList()
    }

    func replacePaneStates(_ paneStates: [String: SessionPaneState]) {
        self.paneStates = paneStates
    }

    func applyWorkspaceSnapshot(_ snapshot: WorkspaceSnapshot) {
        let shouldNotify = hasEstablishedNotificationBaseline
        let incomingSessionIDs = Set(snapshot.sessions.map(\.id))
        let questionsBySession = Dictionary(grouping: snapshot.questions, by: \.sessionID)
        let permissionsBySession = Dictionary(grouping: snapshot.permissions, by: \.sessionID)

        for session in snapshot.sessions {
            let state = sessionState(for: session.id)
            state.applySessionModel(session)
            let previousStatus = previousStatusBySessionID[session.id]
            let newStatus = snapshot.statuses[session.id]
            state.applyStatus(newStatus)
            notifyIfSessionStopped(sessionID: session.id, previousStatus: previousStatus, newStatus: newStatus, shouldNotify: shouldNotify)
            updateTrackedStatus(newStatus, sessionID: session.id)
        }

        for sessionID in incomingSessionIDs {
            let state = sessionState(for: sessionID)
            let questions = questionsBySession[sessionID, default: []]
            let permissions = permissionsBySession[sessionID, default: []]
            state.replaceQuestions(questions)
            state.replacePermissions(permissions)
            notifyForNewInteractions(sessionID: sessionID, questions: questions, permissions: permissions, shouldNotify: shouldNotify)
            questionRequestIDsBySessionID[sessionID] = Set(questions.map(\.id))
            permissionRequestIDsBySessionID[sessionID] = Set(permissions.map(\.id))
        }

        for sessionID in sessionStates.keys where !incomingSessionIDs.contains(sessionID) {
            sessionStates.removeValue(forKey: sessionID)
            paneStates.removeValue(forKey: sessionID)
            previousStatusBySessionID.removeValue(forKey: sessionID)
            questionRequestIDsBySessionID.removeValue(forKey: sessionID)
            permissionRequestIDsBySessionID.removeValue(forKey: sessionID)
        }

        refreshSessionsList()
        hasEstablishedNotificationBaseline = true
    }

    func applyPersistenceSnapshot(_ snapshot: PersistenceSnapshot) {
        paneStates = snapshot.paneStates
        let incomingSessionIDs = Set(snapshot.sessions.map(\.id))

        for session in snapshot.sessions {
            sessionState(for: session.id).applyPersistedSession(session)
        }

        for (sessionID, messages) in snapshot.messagesBySession {
            sessionState(for: sessionID).replaceMessages(messages)
        }

        for (sessionID, questions) in snapshot.questionsBySession {
            sessionState(for: sessionID).replaceQuestions(questions)
            questionRequestIDsBySessionID[sessionID] = Set(questions.map(\.id))
        }

        for (sessionID, permissions) in snapshot.permissionsBySession {
            sessionState(for: sessionID).replacePermissions(permissions)
            permissionRequestIDsBySessionID[sessionID] = Set(permissions.map(\.id))
        }

        for session in snapshot.sessions {
            if let status = session.status {
                previousStatusBySessionID[session.id] = status
            } else {
                previousStatusBySessionID.removeValue(forKey: session.id)
            }
        }

        for sessionID in sessionStates.keys where !incomingSessionIDs.contains(sessionID) {
            sessionStates.removeValue(forKey: sessionID)
            paneStates.removeValue(forKey: sessionID)
            previousStatusBySessionID.removeValue(forKey: sessionID)
            questionRequestIDsBySessionID.removeValue(forKey: sessionID)
            permissionRequestIDsBySessionID.removeValue(forKey: sessionID)
        }

        refreshSessionsList()
        hasEstablishedNotificationBaseline = true
    }

    func applySessionLifecycle(session: OpenCodeSession, lifecycle: SessionLifecycleEvent) {
        let lifecycleDescription = String(describing: lifecycle)
        switch lifecycle {
        case .created, .updated:
            logger.notice(
                "Apply session lifecycle sessionID=\(session.id, privacy: .public) lifecycle=\(lifecycleDescription, privacy: .public) updatedAtMS=\(session.time.updated, privacy: .public)"
            )
            sessionState(for: session.id).applySessionModel(session)
        case .deleted:
            logger.notice(
                "Apply session lifecycle sessionID=\(session.id, privacy: .public) lifecycle=\(lifecycleDescription, privacy: .public)"
            )
            sessionStates.removeValue(forKey: session.id)
            paneStates.removeValue(forKey: session.id)
            previousStatusBySessionID.removeValue(forKey: session.id)
            questionRequestIDsBySessionID.removeValue(forKey: session.id)
            permissionRequestIDsBySessionID.removeValue(forKey: session.id)
        }

        refreshSessionsList()
    }

    func applyStatus(sessionID: String, status: SessionStatus?) {
        let previousStatus = previousStatusBySessionID[sessionID]
        sessionState(for: sessionID).applyStatus(status)
        notifyIfSessionStopped(sessionID: sessionID, previousStatus: previousStatus, newStatus: status, shouldNotify: hasEstablishedNotificationBaseline)
        updateTrackedStatus(status, sessionID: sessionID)
        refreshSessionsList()
    }

    func replaceMessages(sessionID: String, messages: [MessageEnvelope]) {
        sessionState(for: sessionID).replaceMessages(messages)
        refreshSessionsList()
    }

    func upsertMessageInfo(_ info: MessageInfo) {
        sessionState(for: info.sessionID).upsertMessageInfo(info)
        refreshSessionsList()
    }

    func replaceTodos(sessionID: String, todos: [SessionTodo]) {
        sessionState(for: sessionID).replaceTodos(todos)
        refreshSessionsList()
    }

    func replaceInteractions(sessionID: String, questions: [QuestionRequest], permissions: [PermissionRequest]) {
        let state = sessionState(for: sessionID)
        state.replaceQuestions(questions)
        state.replacePermissions(permissions)
        notifyForNewInteractions(sessionID: sessionID, questions: questions, permissions: permissions, shouldNotify: hasEstablishedNotificationBaseline)
        questionRequestIDsBySessionID[sessionID] = Set(questions.map(\.id))
        permissionRequestIDsBySessionID[sessionID] = Set(permissions.map(\.id))
        refreshSessionsList()
    }

    func applyInteractionSnapshot(_ snapshot: InteractionSnapshot) {
        let shouldNotify = hasEstablishedNotificationBaseline
        let questionsBySession = Dictionary(grouping: snapshot.questions, by: \.sessionID)
        let permissionsBySession = Dictionary(grouping: snapshot.permissions, by: \.sessionID)
        let sessionIDs = Set(questionsBySession.keys).union(permissionsBySession.keys).union(sessionStates.keys)

        for sessionID in sessionIDs {
            let state = sessionState(for: sessionID)
            let questions = questionsBySession[sessionID, default: []]
            let permissions = permissionsBySession[sessionID, default: []]
            state.replaceQuestions(questions)
            state.replacePermissions(permissions)
            notifyForNewInteractions(sessionID: sessionID, questions: questions, permissions: permissions, shouldNotify: shouldNotify)
            questionRequestIDsBySessionID[sessionID] = Set(questions.map(\.id))
            permissionRequestIDsBySessionID[sessionID] = Set(permissions.map(\.id))
        }

        refreshSessionsList()
        hasEstablishedNotificationBaseline = true
    }

    @discardableResult
    func applyMessagePart(_ part: MessagePart) -> MessagePart? {
        guard let sessionID = part.sessionID else { return nil }
        let appliedPart = sessionState(for: sessionID).applyMessagePart(part)
        if appliedPart != nil {
            refreshSessionsList()
        }
        return appliedPart
    }

    @discardableResult
    func applyMessagePartDelta(sessionID: String, partID: String, field: MessagePartDeltaField, delta: String) -> Bool {
        let changed = sessionState(for: sessionID).applyMessagePartDelta(partID: partID, field: field, delta: delta)
        if changed {
            refreshSessionsList()
        }
        return changed
    }

    @discardableResult
    func removeMessagePart(sessionID: String, partID: String) -> Bool {
        let changed = sessionState(for: sessionID).removeMessagePart(partID: partID)
        if changed {
            refreshSessionsList()
        }
        return changed
    }

    @discardableResult
    func removeMessage(sessionID: String, messageID: String) -> Bool {
        let changed = sessionState(for: sessionID).removeMessage(messageID: messageID)
        if changed {
            refreshSessionsList()
        }
        return changed
    }

    private func refreshSessionsList() {
        for state in sessionStates.values {
            state.recomputeDisplay(modelContextLimits: modelContextLimits)
        }

        sessions = sessionStates.values
            .compactMap(\.session)
            .sorted { lhs, rhs in
                if lhs.updatedAtMS == rhs.updatedAtMS {
                    return lhs.id < rhs.id
                }
                return lhs.updatedAtMS > rhs.updatedAtMS
            }

        let orderedSessionIDs = sessions.map(\.id).joined(separator: ",")
        logger.notice(
            "Refresh sessions list count=\(self.sessions.count, privacy: .public) order=\(orderedSessionIDs, privacy: .public)"
        )
    }

    private func updateTrackedStatus(_ status: SessionStatus?, sessionID: String) {
        if let status {
            previousStatusBySessionID[sessionID] = status
        } else {
            previousStatusBySessionID.removeValue(forKey: sessionID)
        }
    }

    private func notifyIfSessionStopped(
        sessionID: String,
        previousStatus: SessionStatus?,
        newStatus: SessionStatus?,
        shouldNotify: Bool
    ) {
        guard shouldNotify,
              previousStatus?.isThinkingActive == true,
              newStatus?.isThinkingActive != true else { return }

        let sessionTitle = sessionState(for: sessionID).sessionTitle
        notifier.notify(.sessionStopped(sessionID: sessionID, sessionTitle: sessionTitle))
    }

    private func notifyForNewInteractions(
        sessionID: String,
        questions: [QuestionRequest],
        permissions: [PermissionRequest],
        shouldNotify: Bool
    ) {
        guard shouldNotify else { return }

        let sessionTitle = sessionState(for: sessionID).sessionTitle
        let previousPermissionIDs = permissionRequestIDsBySessionID[sessionID, default: []]
        for permission in permissions where !previousPermissionIDs.contains(permission.id) {
            notifier.notify(
                .permissionRequested(
                    sessionID: sessionID,
                    sessionTitle: sessionTitle,
                    permission: permission.permission
                )
            )
        }

        let previousQuestionIDs = questionRequestIDsBySessionID[sessionID, default: []]
        for request in questions where !previousQuestionIDs.contains(request.id) {
            let questionText = request.questions.first?.question ?? "Question requires an answer"
            notifier.notify(
                .questionAsked(
                    sessionID: sessionID,
                    sessionTitle: sessionTitle,
                    question: questionText
                )
            )
        }
    }
}

actor WorkspaceLiveStoreRegistry {
    static let shared = WorkspaceLiveStoreRegistry()

    private var stores: [WorkspaceConnection: WorkspaceLiveStore] = [:]
    private var notifier: any WorkspaceEventNotifying

    init(notifier: any WorkspaceEventNotifying = NoopWorkspaceEventNotifier()) {
        self.notifier = notifier
    }

    func configureNotifier(_ notifier: any WorkspaceEventNotifying) async {
        self.notifier = notifier
        for store in stores.values {
            await MainActor.run {
                store.setNotifier(notifier)
            }
        }
    }

    func store(for connection: WorkspaceConnection) async -> WorkspaceLiveStore {
        if let existing = stores[connection] {
            return existing
        }

        let notifier = self.notifier
        let store = await MainActor.run {
            WorkspaceLiveStore(connection: connection, notifier: notifier)
        }
        stores[connection] = store
        return store
    }
}
