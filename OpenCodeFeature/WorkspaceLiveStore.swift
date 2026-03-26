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
final class SessionMessageState: ObservableObject, @unchecked Sendable {
    @Published private(set) var snapshot: MessageEnvelope

    var id: String { snapshot.id }

    init(snapshot: MessageEnvelope) {
        self.snapshot = snapshot
    }

    func replace(with snapshot: MessageEnvelope) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }

    func updateInfo(_ info: MessageInfo) {
        guard snapshot.info != info else { return }
        snapshot = MessageEnvelope(info: info, parts: snapshot.parts)
    }

    func updateParts(_ parts: [MessagePart]) {
        guard snapshot.parts != parts else { return }
        snapshot = MessageEnvelope(info: snapshot.info, parts: parts)
    }

    var info: MessageInfo { snapshot.info }
    var parts: [MessagePart] { snapshot.parts }
    var createdAtMS: Double { snapshot.info.time.created }
    var createdAt: Date { snapshot.createdAt }
    var totalTokens: Int? { snapshot.totalTokens }
    var visibleText: String { snapshot.visibleText }
    var reasoningText: String { snapshot.reasoningText }
    var latestReasoningTitle: String? { snapshot.latestReasoningTitle }
    var toolParts: [MessagePart] { snapshot.toolParts }
    var stepFinish: MessagePart? { snapshot.stepFinish }
}

struct TranscriptMessageRow: Identifiable, Equatable {
    let id: String
    let showsTimestamp: Bool
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
    @Published private(set) var transcriptRows: [TranscriptMessageRow] = []
    @Published private(set) var latestReasoningTitle: String?
    @Published private(set) var latestTodoToolPartID: String?
    @Published private(set) var todos: [SessionTodo] = []
    @Published private(set) var questions: [QuestionRequest] = []
    @Published private(set) var permissions: [PermissionRequest] = []

    private var sessionModel: OpenCodeSession?
    private var persistedSession: SessionDisplay?
    private var status: SessionStatus?
    private var messageStatesByID: [String: SessionMessageState] = [:]
    private var messageIDByPartID: [String: String] = [:]
    private var pendingPartDeltas: [String: [BufferedPartDelta]] = [:]

    var sessionTitle: String {
        sessionModel?.title ?? persistedSession?.title ?? session?.title ?? id
    }

    init(id: String) {
        self.id = id
    }

    var messages: [MessageEnvelope] {
        orderedMessageStates().map(\.snapshot)
    }

    func orderedMessageStates() -> [SessionMessageState] {
        transcriptRows.compactMap { messageStatesByID[$0.id] }
    }

    func messageState(for messageID: String) -> SessionMessageState? {
        messageStatesByID[messageID]
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
        guard !messageListsMatch(messages, sortedMessages) else { return }

        let incomingIDs = Set(sortedMessages.map(\.id))
        for messageID in messageStatesByID.keys where !incomingIDs.contains(messageID) {
            removeMessageState(messageID: messageID)
        }

        var nextPartIndex: [String: String] = [:]
        for message in sortedMessages {
            if let existing = messageStatesByID[message.id] {
                existing.replace(with: message)
            } else {
                messageStatesByID[message.id] = SessionMessageState(snapshot: message)
            }

            for part in message.parts {
                nextPartIndex[part.id] = message.id
            }
        }

        messageIDByPartID = nextPartIndex
        refreshTranscriptState(using: sortedMessages)
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
        if let existing = messageStatesByID[info.id] {
            existing.updateInfo(info)
        } else {
            messageStatesByID[info.id] = SessionMessageState(snapshot: MessageEnvelope(info: info, parts: []))
        }

        refreshTranscriptState()
        DebugLogging.notice(logger,
            "Published message info sessionID=\(self.id) messageID=\(info.id) totalMessages=\(messageStatesByID.count)"
        )
    }

    func applyMessagePart(_ part: MessagePart) -> MessagePart? {
        let resolvedPart = resolvedPartApplyingPendingDeltas(part)

        guard let messageID = resolvedPart.messageID else {
            DebugLogging.notice(logger, "Direct part apply miss sessionID=\(self.id) partID=\(part.id) reason=missing-message-id")
            return nil
        }

        let createdShell = ensureMessageShell(messageID: messageID, createdAtMS: resolvedPart.time?.start)

        guard let messageState = messageStatesByID[messageID] else {
            DebugLogging.notice(logger,
                "Direct part apply miss sessionID=\(self.id) messageID=\(messageID) partID=\(resolvedPart.id) reason=message-not-loaded loadedMessages=\(messageStatesByID.count)"
            )
            return nil
        }

        var message = messageState.snapshot
        if let partIndex = message.parts.firstIndex(where: { $0.id == resolvedPart.id }) {
            message.parts[partIndex] = resolvedPart
        } else {
            message.parts.append(resolvedPart)
            message.parts.sort(by: Self.partSort)
        }
        messageState.replace(with: message)
        messageIDByPartID[resolvedPart.id] = messageID
        refreshTranscriptStateIfNeeded(structureChanged: createdShell)
        DebugLogging.notice(logger,
            "Published message part sessionID=\(self.id) messageID=\(messageID) partID=\(resolvedPart.id) partType=\(resolvedPart.type.rawString) messageParts=\(message.parts.count)"
        )
        return resolvedPart
    }

    func applyMessagePartDelta(partID: String, field: MessagePartDeltaField, delta: String) -> Bool {
        guard let messageID = messageID(containingPartID: partID),
              let messageState = messageStatesByID[messageID] else {
            pendingPartDeltas[partID, default: []].append(BufferedPartDelta(field: field, delta: delta))
            DebugLogging.notice(logger,
                "Buffered part delta sessionID=\(self.id) partID=\(partID) field=\(field.rawString) deltaBytes=\(delta.utf8.count) bufferedCount=\(self.pendingPartDeltas[partID]?.count ?? 0)"
            )
            return true
        }

        var message = messageState.snapshot
        guard let partIndex = message.parts.firstIndex(where: { $0.id == partID }) else {
            return false
        }

        var part = message.parts[partIndex]
        part.apply(delta: delta, to: field)
        message.parts[partIndex] = part
        messageState.replace(with: message)
        refreshTranscriptMetadata()
        DebugLogging.notice(logger,
            "Published part delta sessionID=\(self.id) partID=\(partID) field=\(field.rawString) visibleTextBytes=\(message.visibleText.utf8.count)"
        )
        return true
    }

    func removeMessagePart(partID: String) -> Bool {
        let hadBufferedDeltas = pendingPartDeltas.removeValue(forKey: partID) != nil
        guard let messageID = messageID(containingPartID: partID),
              let messageState = messageStatesByID[messageID] else {
            return hadBufferedDeltas
        }

        var message = messageState.snapshot
        let originalCount = message.parts.count
        message.parts.removeAll { $0.id == partID }
        guard message.parts.count != originalCount else { return hadBufferedDeltas }
        messageState.replace(with: message)
        messageIDByPartID.removeValue(forKey: partID)
        refreshTranscriptMetadata()
        return true
    }

    func removeMessage(messageID: String) -> Bool {
        guard messageStatesByID[messageID] != nil else { return false }
        removeMessageState(messageID: messageID)
        refreshTranscriptState()
        return true
    }

    private func ensureMessageShell(messageID: String, createdAtMS: Double?) -> Bool {
        guard messageStatesByID[messageID] == nil else { return false }

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
        messageStatesByID[messageID] = SessionMessageState(snapshot: MessageEnvelope(info: info, parts: []))
        return true
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

    private func messageListsMatch(_ lhs: [MessageEnvelope], _ rhs: [MessageEnvelope]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { existingMessage, incomingMessage in
            existingMessage == incomingMessage
        }
    }

    private func messageID(containingPartID partID: String) -> String? {
        if let messageID = messageIDByPartID[partID] {
            return messageID
        }

        for (messageID, messageState) in messageStatesByID where messageState.parts.contains(where: { $0.id == partID }) {
            messageIDByPartID[partID] = messageID
            return messageID
        }

        return nil
    }

    private func removeMessageState(messageID: String) {
        guard let removed = messageStatesByID.removeValue(forKey: messageID) else { return }
        for part in removed.parts {
            messageIDByPartID.removeValue(forKey: part.id)
            pendingPartDeltas.removeValue(forKey: part.id)
        }
    }

    private func sortedSnapshots() -> [MessageEnvelope] {
        messageStatesByID.values
            .map(\.snapshot)
            .sorted { lhs, rhs in
                if lhs.info.time.created == rhs.info.time.created {
                    return lhs.id < rhs.id
                }
                return lhs.info.time.created < rhs.info.time.created
            }
    }

    private func refreshTranscriptState() {
        refreshTranscriptState(using: sortedSnapshots())
    }

    private func refreshTranscriptState(using sortedMessages: [MessageEnvelope]) {
        let nextRows = Self.makeTranscriptRows(from: sortedMessages)
        if transcriptRows != nextRows {
            transcriptRows = nextRows
        }
        refreshTranscriptMetadata(using: sortedMessages)
    }

    private func refreshTranscriptStateIfNeeded(structureChanged: Bool) {
        let sortedMessages = sortedSnapshots()
        if structureChanged {
            let nextRows = Self.makeTranscriptRows(from: sortedMessages)
            if transcriptRows != nextRows {
                transcriptRows = nextRows
            }
        }
        refreshTranscriptMetadata(using: sortedMessages)
    }

    private func refreshTranscriptMetadata() {
        refreshTranscriptMetadata(using: sortedSnapshots())
    }

    private func refreshTranscriptMetadata(using sortedMessages: [MessageEnvelope]) {
        let nextLatestReasoningTitle = sortedMessages.reversed().compactMap(\.latestReasoningTitle).first
        if latestReasoningTitle != nextLatestReasoningTitle {
            latestReasoningTitle = nextLatestReasoningTitle
        }

        let nextLatestTodoToolPartID = sortedMessages
            .reversed()
            .compactMap { message in
                message.toolParts.last(where: \.isTodoWriteTool)?.id
            }
            .first
        if latestTodoToolPartID != nextLatestTodoToolPartID {
            latestTodoToolPartID = nextLatestTodoToolPartID
        }
    }

    private static func makeTranscriptRows(from messages: [MessageEnvelope]) -> [TranscriptMessageRow] {
        messages.enumerated().map { index, message in
            let showsTimestamp = if index == 0 {
                true
            } else {
                message.createdAt.timeIntervalSince(messages[index - 1].createdAt) > 300
            }

            return TranscriptMessageRow(id: message.id, showsTimestamp: showsTimestamp)
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
    struct RawSSEEventEntry: Identifiable {
        let id: Int
        let payload: String
    }

    private static let rawSSEEventLimit = 10_000
    private static let rawSSEEventTrimCount = 2_000

    let connection: WorkspaceConnection
    private let logger = Logger(subsystem: "ai.opencode.app", category: "workspace-sync")

    var directory: String { connection.directory }

    @Published private(set) var orderedVisibleSessionIDs: [String] = []
    @Published private(set) var paneStates: [String: SessionPaneState] = [:]
    @Published private(set) var rawSSEEvents: [RawSSEEventEntry] = []

    private var notifier: any WorkspaceEventNotifying
    private var modelContextLimits: [ModelContextKey: Int] = [:]
    private var sessionStates: [String: SessionLiveState] = [:]
    private var orderedSessionIDs: [String] = []
    private var deferredMessageSessionIDs: Set<String> = []
    private var previousStatusBySessionID: [String: SessionStatus] = [:]
    private var questionRequestIDsBySessionID: [String: Set<String>] = [:]
    private var permissionRequestIDsBySessionID: [String: Set<String>] = [:]
    private var hasEstablishedNotificationBaseline = false
    private var nextRawSSEEventID = 0

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

    func appendRawSSEEvent(_ payload: String) {
        rawSSEEvents.append(RawSSEEventEntry(id: nextRawSSEEventID, payload: payload))
        nextRawSSEEventID += 1

        if rawSSEEvents.count > Self.rawSSEEventLimit {
            rawSSEEvents.removeFirst(Self.rawSSEEventTrimCount)
        }
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
        let _ = affectedVisibleSessions.compactMap { sessionID -> String? in
            let oldValue = beforeMessageCounts[sessionID, default: 0]
            let newValue = afterMessagesBySession[sessionID, default: sessionStates[sessionID]?.messages.count ?? 0]
            guard oldValue != newValue else { return nil }
            return "\(sessionID):\(oldValue)->\(newValue)"
        }
        let _ = affectedVisibleSessions.compactMap { sessionID -> String? in
            let oldValue = beforeQuestionCounts[sessionID, default: 0]
            let newValue = afterQuestionsBySession[sessionID, default: sessionStates[sessionID]?.questions.count ?? 0]
            guard oldValue != newValue else { return nil }
            return "\(sessionID):\(oldValue)->\(newValue)"
        }
        let _ = affectedVisibleSessions.compactMap { sessionID -> String? in
            let oldValue = beforePermissionCounts[sessionID, default: 0]
            let newValue = afterPermissionsBySession[sessionID, default: sessionStates[sessionID]?.permissions.count ?? 0]
            guard oldValue != newValue else { return nil }
            return "\(sessionID):\(oldValue)->\(newValue)"
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
