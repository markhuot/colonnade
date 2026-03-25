import Combine
import Foundation
import OSLog

protocol WorkspaceEventNotifying: Sendable {
    func notify(_ event: WorkspaceEventNotification)
}

enum WorkspaceEventNotification: Equatable, Sendable {
    case sessionStopped(connection: WorkspaceConnection, sessionID: String, sessionTitle: String)
    case permissionRequested(connection: WorkspaceConnection, sessionID: String, sessionTitle: String, permission: String)
    case questionAsked(connection: WorkspaceConnection, sessionID: String, sessionTitle: String, question: String)

    var connection: WorkspaceConnection {
        switch self {
        case let .sessionStopped(connection, _, _),
             let .permissionRequested(connection, _, _, _),
             let .questionAsked(connection, _, _, _):
            return connection
        }
    }

    var sessionID: String {
        switch self {
        case let .sessionStopped(_, sessionID, _),
             let .permissionRequested(_, sessionID, _, _),
             let .questionAsked(_, sessionID, _, _):
            return sessionID
        }
    }
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

    func markMessagesHydrated(updatedAtMS: Double) {
        if let persistedSession {
            self.persistedSession = SessionDisplay(
                id: persistedSession.id,
                title: persistedSession.title,
                createdAtMS: persistedSession.createdAtMS,
                updatedAtMS: persistedSession.updatedAtMS,
                hydratedMessageUpdatedAtMS: updatedAtMS,
                parentID: persistedSession.parentID,
                status: persistedSession.status,
                hasPendingPermission: persistedSession.hasPendingPermission,
                todoProgress: persistedSession.todoProgress,
                contextUsageText: persistedSession.contextUsageText,
                isArchived: persistedSession.isArchived
            )
        }

        if let session {
            self.session = SessionDisplay(
                id: session.id,
                title: session.title,
                createdAtMS: session.createdAtMS,
                updatedAtMS: session.updatedAtMS,
                hydratedMessageUpdatedAtMS: updatedAtMS,
                parentID: session.parentID,
                status: session.status,
                hasPendingPermission: session.hasPendingPermission,
                todoProgress: session.todoProgress,
                contextUsageText: session.contextUsageText,
                isArchived: session.isArchived
            )
        }
    }

    func applyStatus(_ status: SessionStatus?) {
        self.status = status
    }

    func replaceMessages(_ incomingMessages: [MessageEnvelope]) {
        let sortedMessages = incomingMessages.sorted { $0.info.time.created < $1.info.time.created }
        let totalParts = sortedMessages.reduce(0) { $0 + $1.parts.count }
        let messagesWithParts = sortedMessages.filter { !$0.parts.isEmpty }.count
        PerformanceInstrumentation.log(
            "session-state-replace-messages sessionID=\(self.id) existingMessages=\(self.messages.count) incomingMessages=\(sortedMessages.count) totalParts=\(totalParts) messagesWithParts=\(messagesWithParts)"
        )
        guard !messageListsMatch(self.messages, sortedMessages) else { return }
        self.messages = mergedMessagesPreservingIdentity(with: sortedMessages)
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
        let start = PerformanceInstrumentation.begin(
            "session-state-upsert-message-info",
            details: "sessionID=\(self.id) messageID=\(info.id) existingMessages=\(messages.count)"
        )
        var updatedMessages = messages
        if let messageIndex = updatedMessages.firstIndex(where: { $0.id == info.id }) {
            let existingParts = updatedMessages[messageIndex].parts
            updatedMessages[messageIndex] = MessageEnvelope(info: info, parts: existingParts)
        } else {
            updatedMessages.append(MessageEnvelope(info: info, parts: []))
            updatedMessages.sort { $0.info.time.created < $1.info.time.created }
        }
        messages = updatedMessages
        PerformanceInstrumentation.end(
            "session-state-upsert-message-info",
            from: start,
            details: "sessionID=\(self.id) messageID=\(info.id) totalMessages=\(updatedMessages.count)",
            thresholdMS: 1
        )
        DebugLogging.notice(logger,
            "Published message info sessionID=\(self.id) messageID=\(info.id) totalMessages=\(updatedMessages.count)"
        )
    }

    func applyMessagePart(_ part: MessagePart) -> MessagePart? {
        let start = PerformanceInstrumentation.begin(
            "session-state-apply-message-part",
            details: "sessionID=\(self.id) partID=\(part.id) existingMessages=\(messages.count)"
        )
        let resolvedPart = resolvedPartApplyingPendingDeltas(part)

        guard let messageID = resolvedPart.messageID else {
            PerformanceInstrumentation.log(
                "session-state-apply-message-part-miss sessionID=\(self.id) partID=\(part.id) reason=missing-message-id"
            )
            DebugLogging.notice(logger, "Direct part apply miss sessionID=\(self.id) partID=\(part.id) reason=missing-message-id")
            return nil
        }

        var updatedMessages = messages
        ensureMessageShell(in: &updatedMessages, messageID: messageID, createdAtMS: resolvedPart.time?.start)

        guard let messageIndex = updatedMessages.firstIndex(where: { $0.id == messageID }) else {
            PerformanceInstrumentation.log(
                "session-state-apply-message-part-miss sessionID=\(self.id) messageID=\(messageID) partID=\(resolvedPart.id) reason=message-not-loaded loadedMessages=\(updatedMessages.count)"
            )
            DebugLogging.notice(logger,
                "Direct part apply miss sessionID=\(self.id) messageID=\(messageID) partID=\(resolvedPart.id) reason=message-not-loaded loadedMessages=\(updatedMessages.count)"
            )
            return nil
        }

        var message = updatedMessages[messageIndex]
        let previousPartsCount = message.parts.count
        let previousVisibleTextBytes = message.visibleText.utf8.count
        if let partIndex = message.parts.firstIndex(where: { $0.id == resolvedPart.id }) {
            message.parts[partIndex] = resolvedPart
        } else {
            message.parts.append(resolvedPart)
            message.parts.sort(by: Self.partSort)
        }
        let updatedVisibleTextBytes = message.visibleText.utf8.count
        updatedMessages[messageIndex] = message
        messages = updatedMessages
        PerformanceInstrumentation.end(
            "session-state-apply-message-part",
            from: start,
            details: "sessionID=\(self.id) messageID=\(messageID) partID=\(resolvedPart.id) messageParts=\(message.parts.count) totalMessages=\(updatedMessages.count)",
            thresholdMS: 1
        )
        DebugLogging.notice(logger,
            "Published message part sessionID=\(self.id) messageID=\(messageID) partID=\(resolvedPart.id) partType=\(resolvedPart.type.rawString) messageParts=\(message.parts.count)"
        )
        PerformanceInstrumentation.log(
            "session-state-apply-message-part-publish sessionID=\(self.id) messageID=\(messageID) partID=\(resolvedPart.id) partsBefore=\(previousPartsCount) partsAfter=\(message.parts.count) visibleTextBytesBefore=\(previousVisibleTextBytes) visibleTextBytesAfter=\(updatedVisibleTextBytes)"
        )
        return resolvedPart
    }

    func applyMessagePartDelta(partID: String, field: MessagePartDeltaField, delta: String) -> Bool {
        let start = PerformanceInstrumentation.begin(
            "session-state-apply-part-delta",
            details: "sessionID=\(self.id) partID=\(partID) field=\(field.rawString) deltaBytes=\(delta.utf8.count) messages=\(messages.count)"
        )
        var updatedMessages = messages

        guard let messageIndex = updatedMessages.firstIndex(where: { message in
            message.parts.contains(where: { $0.id == partID })
        }) else {
            pendingPartDeltas[partID, default: []].append(BufferedPartDelta(field: field, delta: delta))
            PerformanceInstrumentation.log(
                "session-state-apply-part-delta-buffer sessionID=\(self.id) partID=\(partID) field=\(field.rawString) deltaBytes=\(delta.utf8.count) messages=\(messages.count) bufferedCount=\(self.pendingPartDeltas[partID]?.count ?? 0)"
            )
            DebugLogging.notice(logger,
                "Buffered part delta sessionID=\(self.id) partID=\(partID) field=\(field.rawString) deltaBytes=\(delta.utf8.count) bufferedCount=\(self.pendingPartDeltas[partID]?.count ?? 0)"
            )
            return true
        }

        var message = updatedMessages[messageIndex]
        guard let partIndex = message.parts.firstIndex(where: { $0.id == partID }) else {
            PerformanceInstrumentation.log(
                "session-state-apply-part-delta-miss sessionID=\(self.id) messageID=\(message.id) partID=\(partID) field=\(field.rawString) reason=part-not-found parts=\(message.parts.count)"
            )
            return false
        }

        let previousPartsCount = message.parts.count
        let previousVisibleTextBytes = message.visibleText.utf8.count
        var part = message.parts[partIndex]
        part.apply(delta: delta, to: field)
        message.parts[partIndex] = part
        updatedMessages[messageIndex] = message
        messages = updatedMessages
        let updatedVisibleTextBytes = message.visibleText.utf8.count
        PerformanceInstrumentation.end(
            "session-state-apply-part-delta",
            from: start,
            details: "sessionID=\(self.id) partID=\(partID) messageID=\(message.id) visibleTextBytes=\(message.visibleText.utf8.count)",
            thresholdMS: 1
        )
        DebugLogging.notice(logger,
            "Published part delta sessionID=\(self.id) partID=\(partID) field=\(field.rawString) visibleTextBytes=\(message.visibleText.utf8.count)"
        )
        PerformanceInstrumentation.log(
            "session-state-apply-part-delta-publish sessionID=\(self.id) messageID=\(message.id) partID=\(partID) field=\(field.rawString) partIndex=\(partIndex) partsBefore=\(previousPartsCount) partsAfter=\(message.parts.count) visibleTextBytesBefore=\(previousVisibleTextBytes) visibleTextBytesAfter=\(updatedVisibleTextBytes)"
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

    private func mergedMessagesPreservingIdentity(with incomingMessages: [MessageEnvelope]) -> [MessageEnvelope] {
        let existingByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        return incomingMessages.map { incomingMessage in
            guard let existingMessage = existingByID[incomingMessage.id] else {
                return incomingMessage
            }

            guard existingMessage != incomingMessage else {
                return existingMessage
            }

            let mergedParts = mergedPartsPreservingIdentity(existing: existingMessage.parts, incoming: incomingMessage.parts)
            let candidate = MessageEnvelope(info: incomingMessage.info, parts: mergedParts)
            return candidate == existingMessage ? existingMessage : candidate
        }
    }

    private func mergedPartsPreservingIdentity(existing: [MessagePart], incoming: [MessagePart]) -> [MessagePart] {
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        return incoming.map { incomingPart in
            guard let existingPart = existingByID[incomingPart.id] else {
                return incomingPart
            }
            return existingPart == incomingPart ? existingPart : incomingPart
        }
    }

    private func messageListsMatch(_ lhs: [MessageEnvelope], _ rhs: [MessageEnvelope]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { existingMessage, incomingMessage in
            existingMessage == incomingMessage
        }
    }

    @discardableResult
    func recomputeDisplay(modelContextLimits: [ModelContextKey: Int]) -> Bool {
        let updatedSession: SessionDisplay?

        if let sessionModel {
            let todoProgress = TodoProgress.from(todos)
            let hasPendingPermission = !permissions.isEmpty
            let updatedAtMS = max(sessionModel.time.updated, messages.last?.info.time.created ?? 0)

            updatedSession = SessionDisplay(
                id: sessionModel.id,
                title: sessionModel.title,
                createdAtMS: sessionModel.time.created,
                updatedAtMS: updatedAtMS,
                hydratedMessageUpdatedAtMS: persistedSession?.hydratedMessageUpdatedAtMS,
                parentID: sessionModel.parentID,
                status: status,
                hasPendingPermission: hasPendingPermission,
                todoProgress: todoProgress,
                contextUsageText: contextUsageText(modelContextLimits: modelContextLimits),
                isArchived: sessionModel.time.archived != nil
            )
        } else {
            updatedSession = persistedSession
        }

        guard session != updatedSession else { return false }
        session = updatedSession
        return true
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

    @Published private(set) var orderedVisibleSessionIDs: [String] = []
    @Published private(set) var paneStates: [String: SessionPaneState] = [:]

    private var notifier: any WorkspaceEventNotifying
    private var modelContextLimits: [ModelContextKey: Int] = [:]
    private var sessionStates: [String: SessionLiveState] = [:]
    private var orderedSessionIDs: [String] = []
    private var deferredMessageSessionIDs: Set<String> = []
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

    func orderedVisibleSessionStates() -> [SessionLiveState] {
        orderedVisibleSessionIDs.compactMap { sessionStates[$0] }
    }

    func allMessagesBySession(for sessionIDs: [String]) -> [String: [MessageEnvelope]] {
        Dictionary(uniqueKeysWithValues: sessionIDs.compactMap { sessionID in
            guard let state = sessionStates[sessionID] else { return nil }
            return (sessionID, state.messages)
        })
    }

    var sessions: [SessionDisplay] {
        orderedSessionIDs.compactMap(sessionDisplay(for:))
    }

    var visibleSessions: [SessionDisplay] {
        orderedVisibleSessionIDs.compactMap(sessionDisplay(for:))
    }

    func sessionDisplay(for sessionID: String) -> SessionDisplay? {
        sessionStates[sessionID]?.session
    }

    func setModelContextLimits(_ limits: [ModelContextKey: Int]) {
        modelContextLimits = limits
        rebuildSessionOrdering()
    }

    func markMessagesHydrated(sessionID: String, updatedAtMS: Double) {
        sessionState(for: sessionID).markMessagesHydrated(updatedAtMS: updatedAtMS)
    }

    func replacePaneStates(_ paneStates: [String: SessionPaneState]) {
        self.paneStates = paneStates
    }

    func applyWorkspaceSnapshot(_ snapshot: WorkspaceSnapshot) {
        let visibleSessionIDSet = Set(sessions.filter { !$0.isArchived && !$0.isSubagentSession }.map(\.id))
        let openSessionIDSet = Set(sessionStates.keys)
        let beforeVisibleMessageCounts = Dictionary(uniqueKeysWithValues: sessionStates.map { ($0.key, $0.value.messages.count) })
        let beforeVisibleQuestionCounts = Dictionary(uniqueKeysWithValues: sessionStates.map { ($0.key, $0.value.questions.count) })
        let beforeVisiblePermissionCounts = Dictionary(uniqueKeysWithValues: sessionStates.map { ($0.key, $0.value.permissions.count) })
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

        rebuildSessionOrdering()
        logSnapshotDiff(
            name: "workspace-snapshot-apply",
            visibleSessionIDs: visibleSessionIDSet,
            beforeMessageCounts: beforeVisibleMessageCounts,
            afterMessagesBySession: [:],
            beforeQuestionCounts: beforeVisibleQuestionCounts,
            afterQuestionsBySession: Dictionary(uniqueKeysWithValues: incomingSessionIDs.map { ($0, questionsBySession[$0, default: []].count) }),
            beforePermissionCounts: beforeVisiblePermissionCounts,
            afterPermissionsBySession: Dictionary(uniqueKeysWithValues: incomingSessionIDs.map { ($0, permissionsBySession[$0, default: []].count) }),
            previousSessionIDs: openSessionIDSet,
            incomingSessionIDs: incomingSessionIDs
        )
        hasEstablishedNotificationBaseline = true
    }

    func applyPersistenceSnapshot(_ snapshot: PersistenceSnapshot) {
        let visibleSessionIDSet = Set(sessions.filter { !$0.isArchived && !$0.isSubagentSession }.map(\.id))
        let knownSessionIDSet = Set(sessionStates.keys)
        let beforeMessageCounts = Dictionary(uniqueKeysWithValues: sessionStates.map { ($0.key, $0.value.messages.count) })
        let beforeQuestionCounts = Dictionary(uniqueKeysWithValues: sessionStates.map { ($0.key, $0.value.questions.count) })
        let beforePermissionCounts = Dictionary(uniqueKeysWithValues: sessionStates.map { ($0.key, $0.value.permissions.count) })
        paneStates = snapshot.paneStates
        deferredMessageSessionIDs = snapshot.deferredMessageSessionIDs
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

        rebuildSessionOrdering()
        logSnapshotDiff(
            name: "persistence-snapshot-apply",
            visibleSessionIDs: visibleSessionIDSet,
            beforeMessageCounts: beforeMessageCounts,
            afterMessagesBySession: snapshot.messagesBySession.mapValues(\.count),
            beforeQuestionCounts: beforeQuestionCounts,
            afterQuestionsBySession: snapshot.questionsBySession.mapValues(\.count),
            beforePermissionCounts: beforePermissionCounts,
            afterPermissionsBySession: snapshot.permissionsBySession.mapValues(\.count),
            previousSessionIDs: knownSessionIDSet,
            incomingSessionIDs: incomingSessionIDs
        )
        hasEstablishedNotificationBaseline = true
    }

    func applySessionLifecycle(session: OpenCodeSession, lifecycle: SessionLifecycleEvent) {
        let lifecycleDescription = String(describing: lifecycle)
        switch lifecycle {
        case .created, .updated:
            DebugLogging.notice(logger,
                "Apply session lifecycle sessionID=\(session.id) lifecycle=\(lifecycleDescription) updatedAtMS=\(session.time.updated)"
            )
            sessionState(for: session.id).applySessionModel(session)
        case .deleted:
            DebugLogging.notice(logger,
                "Apply session lifecycle sessionID=\(session.id) lifecycle=\(lifecycleDescription)"
            )
            sessionStates.removeValue(forKey: session.id)
            paneStates.removeValue(forKey: session.id)
            previousStatusBySessionID.removeValue(forKey: session.id)
            questionRequestIDsBySessionID.removeValue(forKey: session.id)
            permissionRequestIDsBySessionID.removeValue(forKey: session.id)
        }

        updateSessionOrdering(for: session.id)
    }

    func applyStatus(sessionID: String, status: SessionStatus?) {
        let previousStatus = previousStatusBySessionID[sessionID]
        sessionState(for: sessionID).applyStatus(status)
        notifyIfSessionStopped(sessionID: sessionID, previousStatus: previousStatus, newStatus: status, shouldNotify: hasEstablishedNotificationBaseline)
        updateTrackedStatus(status, sessionID: sessionID)
        updateSessionOrdering(for: sessionID)
    }

    func replaceMessages(sessionID: String, messages: [MessageEnvelope]) {
        deferredMessageSessionIDs.remove(sessionID)
        sessionState(for: sessionID).replaceMessages(messages)
        updateSessionOrdering(for: sessionID)
    }

    func hasDeferredMessages(for sessionID: String) -> Bool {
        deferredMessageSessionIDs.contains(sessionID)
    }

    func needsMessageHydration(for sessionID: String) -> Bool {
        if deferredMessageSessionIDs.contains(sessionID) {
            return true
        }

        let messages = sessionState(for: sessionID).messages
        guard !messages.isEmpty else { return true }

        return !messages.contains { message in
            !message.visibleText.isEmpty || !message.reasoningText.isEmpty || !message.toolParts.isEmpty || message.info.error != nil
        }
    }

    func sessionIDsNeedingHydration(_ sessionIDs: [String]) -> [String] {
        sessionIDs.filter { needsMessageHydration(for: $0) }
    }

    func upsertMessageInfo(_ info: MessageInfo) {
        sessionState(for: info.sessionID).upsertMessageInfo(info)
        updateSessionOrdering(for: info.sessionID)
    }

    func replaceTodos(sessionID: String, todos: [SessionTodo]) {
        sessionState(for: sessionID).replaceTodos(todos)
        updateSessionOrdering(for: sessionID)
    }

    func replaceInteractions(sessionID: String, questions: [QuestionRequest], permissions: [PermissionRequest]) {
        let state = sessionState(for: sessionID)
        state.replaceQuestions(questions)
        state.replacePermissions(permissions)
        notifyForNewInteractions(sessionID: sessionID, questions: questions, permissions: permissions, shouldNotify: hasEstablishedNotificationBaseline)
        questionRequestIDsBySessionID[sessionID] = Set(questions.map(\.id))
        permissionRequestIDsBySessionID[sessionID] = Set(permissions.map(\.id))
        updateSessionOrdering(for: sessionID)
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

        rebuildSessionOrdering()
        hasEstablishedNotificationBaseline = true
    }

    @discardableResult
    func applyMessagePart(_ part: MessagePart) -> MessagePart? {
        guard let sessionID = part.sessionID else { return nil }
        let appliedPart = sessionState(for: sessionID).applyMessagePart(part)
        if appliedPart != nil {
            updateSessionOrdering(for: sessionID)
        }
        return appliedPart
    }

    @discardableResult
    func applyMessagePartDelta(sessionID: String, partID: String, field: MessagePartDeltaField, delta: String) -> Bool {
        let changed = sessionState(for: sessionID).applyMessagePartDelta(partID: partID, field: field, delta: delta)
        if changed {
            updateSessionOrdering(for: sessionID)
        }
        return changed
    }

    @discardableResult
    func removeMessagePart(sessionID: String, partID: String) -> Bool {
        let changed = sessionState(for: sessionID).removeMessagePart(partID: partID)
        if changed {
            updateSessionOrdering(for: sessionID)
        }
        return changed
    }

    @discardableResult
    func removeMessage(sessionID: String, messageID: String) -> Bool {
        let changed = sessionState(for: sessionID).removeMessage(messageID: messageID)
        if changed {
            updateSessionOrdering(for: sessionID)
        }
        return changed
    }

    private func rebuildSessionOrdering() {
        let start = PerformanceInstrumentation.begin(
            "workspace-rebuild-session-ordering",
            details: "directory=\(directory) sessionStates=\(sessionStates.count)"
        )
        for state in sessionStates.values {
            _ = state.recomputeDisplay(modelContextLimits: modelContextLimits)
        }

        let rebuiltOrderedSessionIDs = sessionStates.values
            .compactMap(\.session)
            .sorted { lhs, rhs in
                Self.sessionSortsBefore(lhs, rhs)
            }
            .map(\.id)

        publishSessionOrdering(rebuiltOrderedSessionIDs)

        let orderedSessionIDsSummary = rebuiltOrderedSessionIDs.joined(separator: ",")
        PerformanceInstrumentation.end(
            "workspace-rebuild-session-ordering",
            from: start,
            details: "directory=\(directory) sessions=\(rebuiltOrderedSessionIDs.count) visibleSessions=\(orderedVisibleSessionIDs.count)",
            thresholdMS: 1
        )
        DebugLogging.notice(logger,
            "Rebuilt session ordering count=\(rebuiltOrderedSessionIDs.count) order=\(orderedSessionIDsSummary)"
        )
    }

    private func updateSessionOrdering(for sessionID: String) {
        let state = sessionState(for: sessionID)
        let previousSession = state.session
        let didChange = state.recomputeDisplay(modelContextLimits: modelContextLimits)
        let currentSession = state.session

        let previousOrderKey = previousSession.map(Self.orderKey)
        let currentOrderKey = currentSession.map(Self.orderKey)
        let shouldReorder = previousOrderKey != currentOrderKey || !orderedSessionIDs.contains(sessionID)

        guard didChange || shouldReorder else { return }

        var updatedOrderedSessionIDs = orderedSessionIDs.filter { $0 != sessionID && sessionStates[$0]?.session != nil }

        if let currentSession {
            let insertionIndex = updatedOrderedSessionIDs.firstIndex { existingSessionID in
                guard let existingSession = sessionStates[existingSessionID]?.session else {
                    return false
                }
                return Self.sessionSortsBefore(currentSession, existingSession)
            } ?? updatedOrderedSessionIDs.endIndex
            updatedOrderedSessionIDs.insert(sessionID, at: insertionIndex)
        }

        publishSessionOrdering(updatedOrderedSessionIDs)
    }

    private func publishSessionOrdering(_ updatedOrderedSessionIDs: [String]) {
        let normalizedOrderedSessionIDs = updatedOrderedSessionIDs.filter { sessionStates[$0]?.session != nil }
        orderedSessionIDs = normalizedOrderedSessionIDs

        let updatedVisibleSessionIDs = normalizedOrderedSessionIDs.filter { sessionID in
            guard let session = sessionStates[sessionID]?.session else { return false }
            return !session.isArchived && !session.isSubagentSession
        }

        guard orderedVisibleSessionIDs != updatedVisibleSessionIDs else { return }
        orderedVisibleSessionIDs = updatedVisibleSessionIDs
    }

    private struct SessionOrderKey: Equatable {
        let updatedAtMS: Double
        let id: String
    }

    private static func orderKey(for session: SessionDisplay) -> SessionOrderKey {
        SessionOrderKey(updatedAtMS: session.updatedAtMS, id: session.id)
    }

    private static func sessionSortsBefore(_ lhs: SessionDisplay, _ rhs: SessionDisplay) -> Bool {
        if lhs.updatedAtMS == rhs.updatedAtMS {
            return lhs.id < rhs.id
        }
        return lhs.updatedAtMS > rhs.updatedAtMS
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
        notifier.notify(.sessionStopped(connection: connection, sessionID: sessionID, sessionTitle: sessionTitle))
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
                    connection: connection,
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
                    connection: connection,
                    sessionID: sessionID,
                    sessionTitle: sessionTitle,
                    question: questionText
                )
            )
        }
    }

    private func logSnapshotDiff(
        name: String,
        visibleSessionIDs: Set<String>,
        beforeMessageCounts: [String: Int],
        afterMessagesBySession: [String: Int],
        beforeQuestionCounts: [String: Int],
        afterQuestionsBySession: [String: Int],
        beforePermissionCounts: [String: Int],
        afterPermissionsBySession: [String: Int],
        previousSessionIDs: Set<String>,
        incomingSessionIDs: Set<String>
    ) {
        let affectedVisibleSessions = visibleSessionIDs.union(incomingSessionIDs).sorted()
        let messageChanges = affectedVisibleSessions.compactMap { sessionID -> String? in
            let oldValue = beforeMessageCounts[sessionID, default: 0]
            let newValue = afterMessagesBySession[sessionID, default: sessionStates[sessionID]?.messages.count ?? 0]
            guard oldValue != newValue else { return nil }
            return "\(sessionID):\(oldValue)->\(newValue)"
        }
        let questionChanges = affectedVisibleSessions.compactMap { sessionID -> String? in
            let oldValue = beforeQuestionCounts[sessionID, default: 0]
            let newValue = afterQuestionsBySession[sessionID, default: sessionStates[sessionID]?.questions.count ?? 0]
            guard oldValue != newValue else { return nil }
            return "\(sessionID):\(oldValue)->\(newValue)"
        }
        let permissionChanges = affectedVisibleSessions.compactMap { sessionID -> String? in
            let oldValue = beforePermissionCounts[sessionID, default: 0]
            let newValue = afterPermissionsBySession[sessionID, default: sessionStates[sessionID]?.permissions.count ?? 0]
            guard oldValue != newValue else { return nil }
            return "\(sessionID):\(oldValue)->\(newValue)"
        }
        let insertedSessions = incomingSessionIDs.subtracting(previousSessionIDs).count
        let removedSessions = previousSessionIDs.subtracting(incomingSessionIDs).count

        PerformanceInstrumentation.log(
            "\(name) visibleSessions=\(visibleSessionIDs.count) incomingSessions=\(incomingSessionIDs.count) insertedSessions=\(insertedSessions) removedSessions=\(removedSessions) messageChanges=\(messageChanges.isEmpty ? "none" : messageChanges.joined(separator: ",")) questionChanges=\(questionChanges.isEmpty ? "none" : questionChanges.joined(separator: ",")) permissionChanges=\(permissionChanges.isEmpty ? "none" : permissionChanges.joined(separator: ","))"
        )
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
