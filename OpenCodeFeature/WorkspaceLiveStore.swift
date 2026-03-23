import Combine
import Foundation
import OSLog

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
    private var status: SessionStatus?
    private var pendingPartDeltas: [String: [BufferedPartDelta]] = [:]

    init(id: String) {
        self.id = id
    }

    func applySessionModel(_ session: OpenCodeSession) {
        sessionModel = session
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
        if let messageIndex = messages.firstIndex(where: { $0.id == info.id }) {
            let existingParts = messages[messageIndex].parts
            messages[messageIndex] = MessageEnvelope(info: info, parts: existingParts)
        } else {
            messages.append(MessageEnvelope(info: info, parts: []))
            messages.sort { $0.info.time.created < $1.info.time.created }
        }
    }

    func applyMessagePart(_ part: MessagePart) -> MessagePart? {
        let resolvedPart = resolvedPartApplyingPendingDeltas(part)

        guard let messageID = resolvedPart.messageID else {
            logger.notice("Direct part apply miss sessionID=\(self.id, privacy: .public) partID=\(part.id, privacy: .public) reason=missing-message-id")
            return nil
        }

        ensureMessageShell(messageID: messageID, createdAtMS: resolvedPart.time?.start)

        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
            logger.notice(
                "Direct part apply miss sessionID=\(self.id, privacy: .public) messageID=\(messageID, privacy: .public) partID=\(resolvedPart.id, privacy: .public) reason=message-not-loaded loadedMessages=\(self.messages.count, privacy: .public)"
            )
            return nil
        }

        var message = messages[messageIndex]
        if let partIndex = message.parts.firstIndex(where: { $0.id == resolvedPart.id }) {
            message.parts[partIndex] = resolvedPart
        } else {
            message.parts.append(resolvedPart)
            message.parts.sort(by: Self.partSort)
        }
        messages[messageIndex] = message
        return resolvedPart
    }

    func applyMessagePartDelta(partID: String, field: MessagePartDeltaField, delta: String) -> Bool {
        guard let messageIndex = messages.firstIndex(where: { message in
            message.parts.contains(where: { $0.id == partID })
        }) else {
            pendingPartDeltas[partID, default: []].append(BufferedPartDelta(field: field, delta: delta))
            logger.notice(
                "Buffered part delta sessionID=\(self.id, privacy: .public) partID=\(partID, privacy: .public) field=\(field.rawString, privacy: .public) deltaBytes=\(delta.utf8.count, privacy: .public) bufferedCount=\(self.pendingPartDeltas[partID]?.count ?? 0, privacy: .public)"
            )
            return true
        }

        var message = messages[messageIndex]
        guard let partIndex = message.parts.firstIndex(where: { $0.id == partID }) else {
            return false
        }

        var part = message.parts[partIndex]
        part.apply(delta: delta, to: field)
        message.parts[partIndex] = part
        messages[messageIndex] = message
        return true
    }

    func removeMessagePart(partID: String) -> Bool {
        let hadBufferedDeltas = pendingPartDeltas.removeValue(forKey: partID) != nil
        guard let messageIndex = messages.firstIndex(where: { message in
            message.parts.contains(where: { $0.id == partID })
        }) else {
            return hadBufferedDeltas
        }

        var message = messages[messageIndex]
        let originalCount = message.parts.count
        message.parts.removeAll { $0.id == partID }
        guard message.parts.count != originalCount else { return hadBufferedDeltas }
        messages[messageIndex] = message
        return true
    }

    func removeMessage(messageID: String) -> Bool {
        let originalCount = messages.count
        messages.removeAll { $0.id == messageID }
        return messages.count != originalCount
    }

    private func ensureMessageShell(messageID: String, createdAtMS: Double?) {
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
            session = nil
            return
        }

        let todoProgress = TodoProgress.from(todos)
        let hasPendingPermission = !permissions.isEmpty
        let updatedAtMS = max(sessionModel.time.updated, messages.last?.info.time.created ?? 0)

        session = SessionDisplay(
            id: sessionModel.id,
            title: sessionModel.title,
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

    var directory: String { connection.directory }

    @Published private(set) var sessions: [SessionDisplay] = []
    @Published private(set) var paneStates: [String: SessionPaneState] = [:]

    private var modelContextLimits: [ModelContextKey: Int] = [:]
    private var sessionStates: [String: SessionLiveState] = [:]

    init(connection: WorkspaceConnection) {
        self.connection = connection
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
        let incomingSessionIDs = Set(snapshot.sessions.map(\.id))

        for session in snapshot.sessions {
            let state = sessionState(for: session.id)
            state.applySessionModel(session)
            state.applyStatus(snapshot.statuses[session.id])
        }

        let questionsBySession = Dictionary(grouping: snapshot.questions, by: \.sessionID)
        let permissionsBySession = Dictionary(grouping: snapshot.permissions, by: \.sessionID)

        for sessionID in incomingSessionIDs {
            let state = sessionState(for: sessionID)
            state.replaceQuestions(questionsBySession[sessionID, default: []])
            state.replacePermissions(permissionsBySession[sessionID, default: []])
        }

        for sessionID in sessionStates.keys where !incomingSessionIDs.contains(sessionID) {
            sessionStates.removeValue(forKey: sessionID)
            paneStates.removeValue(forKey: sessionID)
        }

        refreshSessionsList()
    }

    func applyPersistenceSnapshot(_ snapshot: PersistenceSnapshot) {
        paneStates = snapshot.paneStates

        for (sessionID, messages) in snapshot.messagesBySession {
            sessionState(for: sessionID).replaceMessages(messages)
        }

        for (sessionID, questions) in snapshot.questionsBySession {
            sessionState(for: sessionID).replaceQuestions(questions)
        }

        for (sessionID, permissions) in snapshot.permissionsBySession {
            sessionState(for: sessionID).replacePermissions(permissions)
        }

        refreshSessionsList()
    }

    func applySessionLifecycle(session: OpenCodeSession, lifecycle: SessionLifecycleEvent) {
        switch lifecycle {
        case .created, .updated:
            sessionState(for: session.id).applySessionModel(session)
        case .deleted:
            sessionStates.removeValue(forKey: session.id)
            paneStates.removeValue(forKey: session.id)
        }

        refreshSessionsList()
    }

    func applyStatus(sessionID: String, status: SessionStatus?) {
        sessionState(for: sessionID).applyStatus(status)
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
        refreshSessionsList()
    }

    func applyInteractionSnapshot(_ snapshot: InteractionSnapshot) {
        let questionsBySession = Dictionary(grouping: snapshot.questions, by: \.sessionID)
        let permissionsBySession = Dictionary(grouping: snapshot.permissions, by: \.sessionID)
        let sessionIDs = Set(questionsBySession.keys).union(permissionsBySession.keys).union(sessionStates.keys)

        for sessionID in sessionIDs {
            let state = sessionState(for: sessionID)
            state.replaceQuestions(questionsBySession[sessionID, default: []])
            state.replacePermissions(permissionsBySession[sessionID, default: []])
        }

        refreshSessionsList()
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
    }
}

actor WorkspaceLiveStoreRegistry {
    static let shared = WorkspaceLiveStoreRegistry()

    private var stores: [WorkspaceConnection: WorkspaceLiveStore] = [:]

    func store(for connection: WorkspaceConnection) async -> WorkspaceLiveStore {
        if let existing = stores[connection] {
            return existing
        }

        let store = await MainActor.run {
            WorkspaceLiveStore(connection: connection)
        }
        stores[connection] = store
        return store
    }
}
