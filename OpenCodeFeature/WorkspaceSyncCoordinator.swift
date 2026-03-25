import Foundation
import OSLog

protocol WorkspaceSyncCoordinating: Sendable {
    func start(modelContextLimits: [ModelContextKey: Int], openSessionIDs: [String], performInitialSync: Bool) async throws
    func updateModelContextLimits(_ limits: [ModelContextKey: Int]) async
    func updateOpenSessionIDs(_ openSessionIDs: [String]) async
    func refreshAll() async throws
    func refreshMessages(sessionID: String) async
    func refreshTodos(sessionID: String) async
    func refreshInteractions(sessionID: String?) async
    func refreshStatus(sessionID: String) async
}

protocol WorkspaceSyncRegistryProtocol: Actor {
    func coordinator(for connection: WorkspaceConnection) -> any WorkspaceSyncCoordinating
    func store(for connection: WorkspaceConnection) async -> WorkspaceLiveStore
}

private enum MessageMutationFallback: Sendable {
    case refreshSessionMessages(String)
}

actor WorkspaceSyncRegistry: WorkspaceSyncRegistryProtocol {
    static let shared = WorkspaceSyncRegistry()

    private var coordinators: [WorkspaceConnection: WorkspaceSyncCoordinator] = [:]
    private let storeRegistry: WorkspaceLiveStoreRegistry
    private let coordinatorFactory: @Sendable (WorkspaceConnection, WorkspaceLiveStoreRegistry) -> WorkspaceSyncCoordinator

    init(
        storeRegistry: WorkspaceLiveStoreRegistry = .shared,
        coordinatorFactory: @escaping @Sendable (WorkspaceConnection, WorkspaceLiveStoreRegistry) -> WorkspaceSyncCoordinator = { connection, storeRegistry in
            WorkspaceSyncCoordinator(connection: connection, storeRegistry: storeRegistry)
        }
    ) {
        self.storeRegistry = storeRegistry
        self.coordinatorFactory = coordinatorFactory
    }

    func coordinator(for connection: WorkspaceConnection) -> any WorkspaceSyncCoordinating {
        if let existing = coordinators[connection] {
            return existing
        }

        let coordinator = coordinatorFactory(connection, storeRegistry)
        coordinators[connection] = coordinator
        return coordinator
    }

    func store(for connection: WorkspaceConnection) async -> WorkspaceLiveStore {
        await storeRegistry.store(for: connection)
    }
}

actor WorkspaceSyncCoordinator: WorkspaceSyncCoordinating {
    private let logger = Logger(subsystem: "ai.opencode.app", category: "workspace-sync")
    private let client: any OpenCodeAPIClientProtocol
    private let workspaceService: any WorkspaceServiceProtocol
    private let payloadDecoder = EventPayloadDecoder()
    private let repository: PersistenceRepository
    private let storeRegistry: WorkspaceLiveStoreRegistry

    private let connection: WorkspaceConnection
    private var directory: String { connection.directory }
    private var modelContextLimits: [ModelContextKey: Int] = [:]
    private var openSessionIDs: [String] = []

    private var eventTask: Task<Void, Never>?
    private var messageRefreshTasks: [String: Task<Void, Never>] = [:]
    private var todoRefreshTasks: [String: Task<Void, Never>] = [:]
    private var sessionRefreshTask: Task<Void, Never>?
    private var didStart = false

    private enum MessageRefreshReason: Sendable {
        case messageUpdated
        case messageRemoved(messageID: String?)
        case partUpdated(partID: String?)
        case partDeltaMiss(partID: String, field: MessagePartDeltaField, deltaBytes: Int)
        case partRemovedMiss(partID: String?)

        var summary: String {
            switch self {
            case .messageUpdated:
                return "message-updated"
            case let .messageRemoved(messageID):
                return "message-removed messageID=\(messageID ?? "n/a")"
            case let .partUpdated(partID):
                return "part-updated partID=\(partID ?? "n/a")"
            case let .partDeltaMiss(partID, field, deltaBytes):
                return "part-delta-miss partID=\(partID) field=\(field.rawString) deltaBytes=\(deltaBytes)"
            case let .partRemovedMiss(partID):
                return "part-removed-miss partID=\(partID ?? "n/a")"
            }
        }
    }

    init(
        connection: WorkspaceConnection,
        client: (any OpenCodeAPIClientProtocol)? = nil,
        workspaceService: (any WorkspaceServiceProtocol)? = nil,
        repository: PersistenceRepository = .shared,
        storeRegistry: WorkspaceLiveStoreRegistry = .shared
    ) {
        self.connection = connection
        let resolvedClient = client ?? OpenCodeAPIClient(baseURL: connection.serverURL)
        self.client = resolvedClient
        self.workspaceService = workspaceService ?? WorkspaceService(client: resolvedClient)
        self.repository = repository
        self.storeRegistry = storeRegistry
    }

    func start(modelContextLimits: [ModelContextKey: Int], openSessionIDs: [String], performInitialSync: Bool = true) async throws {
        self.modelContextLimits = modelContextLimits
        self.openSessionIDs = openSessionIDs

        logger.notice(
            "Coordinator start directory=\(self.directory, privacy: .public) performInitialSync=\(performInitialSync, privacy: .public) openSessions=\(openSessionIDs.joined(separator: ","), privacy: .public) alreadyStarted=\(self.didStart, privacy: .public)"
        )

        if performInitialSync {
            try await refreshAll()
        }

        guard !didStart else { return }
        didStart = true
        startEventStream()
    }

    func updateModelContextLimits(_ limits: [ModelContextKey: Int]) {
        modelContextLimits = limits
    }

    func updateOpenSessionIDs(_ openSessionIDs: [String]) {
        self.openSessionIDs = openSessionIDs
        logger.notice(
            "Coordinator open sessions updated directory=\(self.directory, privacy: .public) openSessions=\(openSessionIDs.joined(separator: ","), privacy: .public)"
        )
    }

    func refreshAll() async throws {
        async let workspaceSnapshotTask = workspaceService.loadWorkspace(directory: directory)
        let snapshot = try await workspaceSnapshotTask
        let limits = modelContextLimits
        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: snapshot,
            modelContextLimits: limits,
            openSessionIDs: openSessionIDs
        )

        await withStore { store in
            store.setModelContextLimits(limits)
            store.applyWorkspaceSnapshot(snapshot)
        }

        for sessionID in openSessionIDs {
            await refreshMessages(sessionID: sessionID)
            await refreshTodos(sessionID: sessionID)
        }
    }

    func refreshMessages(sessionID: String) async {
        let callStack = Thread.callStackSymbols.prefix(12).joined(separator: " | ")
        PerformanceInstrumentation.log(
            "coordinator-refresh-messages-callstack directory=\(directory) sessionID=\(sessionID) stack=\(callStack)"
        )
        logger.notice("Refreshing messages for \(sessionID, privacy: .public)")
        messageRefreshTasks[sessionID]?.cancel()
        messageRefreshTasks[sessionID] = Task {
            do {
                let refreshStart = PerformanceInstrumentation.begin(
                    "coordinator-refresh-messages",
                    details: "directory=\(directory) sessionID=\(sessionID)"
                )
                let messages = try await workspaceService.loadMessages(directory: directory, sessionID: sessionID)
                let totalParts = messages.reduce(0) { $0 + $1.parts.count }
                let messagesWithParts = messages.filter { !$0.parts.isEmpty }.count
                PerformanceInstrumentation.log(
                    "coordinator-refresh-messages-loaded directory=\(directory) sessionID=\(sessionID) messages=\(messages.count) totalParts=\(totalParts) messagesWithParts=\(messagesWithParts)"
                )
                logger.notice("Loaded messages for \(sessionID, privacy: .public) count=\(messages.count, privacy: .public)")
                let limits = modelContextLimits
                await repository.replaceMessages(
                    directory: directory,
                    sessionID: sessionID,
                    messages: messages,
                    modelContextLimits: limits
                )
                let hydratedUpdatedAtMS = await withStore { store in
                    store.sessionDisplay(for: sessionID)?.updatedAtMS ?? 0
                }
                await repository.markMessagesHydrated(
                    directory: directory,
                    sessionID: sessionID,
                    updatedAtMS: hydratedUpdatedAtMS
                )
                await withStore { store in
                    store.setModelContextLimits(limits)
                    store.replaceMessages(sessionID: sessionID, messages: messages)
                    store.markMessagesHydrated(sessionID: sessionID, updatedAtMS: hydratedUpdatedAtMS)
                }
                PerformanceInstrumentation.end(
                    "coordinator-refresh-messages",
                    from: refreshStart,
                    details: "directory=\(directory) sessionID=\(sessionID) messages=\(messages.count) totalParts=\(totalParts)",
                    thresholdMS: 1
                )
            } catch {
                logger.error("Refresh messages failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                PerformanceInstrumentation.log(
                    "coordinator-refresh-messages-failed directory=\(directory) sessionID=\(sessionID) error=\(error.localizedDescription)"
                )
            }
        }
        await messageRefreshTasks[sessionID]?.value
    }

    func refreshTodos(sessionID: String) async {
        logger.notice("Refreshing todos for \(sessionID, privacy: .public)")
        todoRefreshTasks[sessionID]?.cancel()
        todoRefreshTasks[sessionID] = Task {
            do {
                let todos = try await workspaceService.loadTodos(directory: directory, sessionID: sessionID)
                await repository.replaceTodos(
                    directory: directory,
                    sessionID: sessionID,
                    todos: todos,
                    modelContextLimits: modelContextLimits
                )
                await withStore { store in
                    store.replaceTodos(sessionID: sessionID, todos: todos)
                }
            } catch {
                logger.error("Refresh todos failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        await todoRefreshTasks[sessionID]?.value
    }

    func refreshInteractions(sessionID: String? = nil) async {
        logger.notice("Refreshing interactions sessionID=\((sessionID ?? "all"), privacy: .public)")
        do {
            let snapshot = try await workspaceService.loadInteractions(directory: directory)
            await repository.replaceInteractions(directory: directory, snapshot: snapshot, modelContextLimits: modelContextLimits)
            await withStore { store in
                if let sessionID {
                    let questions = snapshot.questions.filter { $0.sessionID == sessionID }
                    let permissions = snapshot.permissions.filter { $0.sessionID == sessionID }
                    store.replaceInteractions(sessionID: sessionID, questions: questions, permissions: permissions)
                } else {
                    store.applyInteractionSnapshot(snapshot)
                }
            }
        } catch {
            logger.error("Refresh interactions failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshStatus(sessionID: String) async {
        logger.notice("Refreshing status for \(sessionID, privacy: .public)")
        do {
            let statuses = try await workspaceService.loadStatuses(directory: directory)
            let status = statuses[sessionID]
            await repository.applyStatus(
                directory: directory,
                sessionID: sessionID,
                status: status,
                modelContextLimits: modelContextLimits
            )
            await withStore { store in
                store.applyStatus(sessionID: sessionID, status: status)
            }
        } catch {
            logger.error("Refresh status failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startEventStream() {
        eventTask?.cancel()
        eventTask = Task {
            self.logger.notice("Starting event stream loop directory=\(self.directory, privacy: .public)")
            while !Task.isCancelled {
                do {
                    let connection = try await client.openEventStream(directory: directory)
                    self.logger.notice(
                        "Event stream connected directory=\(self.directory, privacy: .public) status=\(connection.response.statusCode, privacy: .public)"
                    )
                    var payloadLines: [String] = []
                    var lineBuffer = Data()

                    for try await byte in connection.bytes {
                        try Task.checkCancellation()

                        if byte == 0x0A {
                            let line = decodeEventStreamLine(from: lineBuffer)
                            lineBuffer.removeAll(keepingCapacity: true)
                            await handleEventStreamLine(line, payloadLines: &payloadLines)
                            continue
                        }

                        lineBuffer.append(byte)
                    }

                    if !lineBuffer.isEmpty {
                        let line = decodeEventStreamLine(from: lineBuffer)
                        await handleEventStreamLine(line, payloadLines: &payloadLines)
                    }

                    if !payloadLines.isEmpty {
                        await dispatchEventPayloadLines(&payloadLines)
                    }

                    await repository.flushBufferedStreamMutations()

                    self.logger.error("Event stream ended without cancellation directory=\(self.directory, privacy: .public); reconnecting")
                } catch is CancellationError {
                    await repository.flushBufferedStreamMutations()
                    self.logger.notice("Event stream cancelled directory=\(self.directory, privacy: .public)")
                    break
                } catch {
                    await repository.flushBufferedStreamMutations()
                    self.logger.error("Event stream failed directory=\(self.directory, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
    }

    private func handleEventData(_ payload: String) async {
        do {
            let event = try payloadDecoder.decode(payload)
            let sessionID = eventSessionID(from: event) ?? "nil"
            logger.notice(
                "SSE event received directory=\(self.directory, privacy: .public) type=\(event.type.rawString, privacy: .public) sessionID=\(sessionID, privacy: .public)"
            )
            await handle(payload: event)
        } catch {
            logger.error("Event decode failed: \(error.localizedDescription, privacy: .public) payload=\(String(payload.prefix(200)), privacy: .private)")
        }
    }

    private func handleEventStreamLine(_ line: String, payloadLines: inout [String]) async {
        if line.isEmpty {
            await dispatchEventPayloadLines(&payloadLines)
            return
        }

        if line.hasPrefix("data:") {
            payloadLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
    }

    private func dispatchEventPayloadLines(_ payloadLines: inout [String]) async {
        guard !payloadLines.isEmpty else { return }

        let payload = payloadLines.joined(separator: "\n")
        payloadLines.removeAll()
        await handleEventData(payload)
    }

    private func handle(payload: EventPayload) async {
        switch payload.type {
        case .serverConnected:
            logger.notice("SSE server connected event directory=\(self.directory, privacy: .public)")
            return

        case .sessionCreated, .sessionUpdated, .sessionDeleted:
            guard
                let sessionObject = payload.object(.info),
                let session = sessionObject.decoded(OpenCodeSession.self),
                let lifecycle = payload.type.lifecycleEvent
            else { return }

            logger.notice(
                "Session lifecycle event directory=\(self.directory, privacy: .public) type=\(payload.type.rawString, privacy: .public) sessionID=\(session.id, privacy: .public)"
            )

            await repository.applySessionLifecycle(
                directory: directory,
                session: session,
                lifecycle: lifecycle,
                modelContextLimits: modelContextLimits
            )
            let store = await storeRegistry.store(for: connection)
            await MainActor.run {
                store.applySessionLifecycle(session: session, lifecycle: lifecycle)
            }

        case .sessionStatus:
            guard
                let sessionID = payload.string(.sessionID),
                let statusObject = payload.object(.status),
                let status = statusObject.decoded(SessionStatus.self)
            else { return }

            await repository.applyStatus(
                directory: directory,
                sessionID: sessionID,
                status: status,
                modelContextLimits: modelContextLimits
            )
            let store = await storeRegistry.store(for: connection)
            await MainActor.run {
                store.applyStatus(sessionID: sessionID, status: status)
            }

        case .messageUpdated:
            guard
                let infoObject = payload.object(.info),
                let info = infoObject.decoded(MessageInfo.self)
            else { return }

            logger.notice(
                "Message updated event directory=\(self.directory, privacy: .public) sessionID=\(info.sessionID, privacy: .public) messageID=\(info.id, privacy: .public)"
            )

            await withStore { store in
                store.upsertMessageInfo(info)
            }
            await repository.upsertMessageInfo(
                directory: directory,
                sessionID: info.sessionID,
                info: info,
                modelContextLimits: modelContextLimits
            )

        case .messageRemoved:
            guard let sessionID = payload.string(.sessionID) else { return }
            if let messageID = payload.string(.messageID) {
                let removed = await withStore { store in
                    store.removeMessage(sessionID: sessionID, messageID: messageID)
                }
                if removed {
                    await repository.removeMessage(directory: directory, sessionID: sessionID, messageID: messageID, modelContextLimits: modelContextLimits)
                    return
                }
            }
            await scheduleMessageRefresh(for: sessionID, reason: .messageRemoved(messageID: payload.string(.messageID)))

        case .messagePartUpdated, .messagePartDelta, .messagePartRemoved:
            guard let sessionID = payload.string(.sessionID) ?? payload.object(.part)?.decoded(MessagePart.self)?.sessionID else { return }

            switch payload.type {
            case .messagePartUpdated:
                if let partObject = payload.object(.part), let part = partObject.decoded(MessagePart.self) {
                    PerformanceInstrumentation.log(
                        "event-message-part-updated directory=\(directory) sessionID=\(sessionID) messageID=\(part.messageID ?? "nil") partID=\(part.id) type=\(part.type.rawString)"
                    )
                    let appliedPart = await withStore { store in
                        store.applyMessagePart(part)
                    }
                    if let appliedPart {
                        await repository.upsertMessagePart(directory: directory, sessionID: sessionID, part: appliedPart, modelContextLimits: modelContextLimits)
                        return
                    }
                }
                await scheduleMessageRefresh(for: sessionID, reason: .partUpdated(partID: payload.object(.part)?[EventPropertyKey.partID.rawValue]?.stringValue ?? payload.object(.part)?["id"]?.stringValue))
            case .messagePartDelta:
                guard let partID = payload.string(.partID) else {
                    await scheduleMessageRefresh(for: sessionID, reason: .partDeltaMiss(partID: "n/a", field: .unknown(""), deltaBytes: 0))
                    return
                }
                let field = MessagePartDeltaField(rawString: payload.string(.field) ?? "")
                let delta = payload.string(.delta) ?? ""
                PerformanceInstrumentation.log(
                    "event-message-part-delta directory=\(directory) sessionID=\(sessionID) partID=\(partID) field=\(field.rawString) deltaBytes=\(delta.utf8.count)"
                )
                let applied = await withStore { store in
                    store.applyMessagePartDelta(sessionID: sessionID, partID: partID, field: field, delta: delta)
                }
                if applied {
                    await repository.applyMessagePartDelta(directory: directory, sessionID: sessionID, partID: partID, field: field, delta: delta, modelContextLimits: modelContextLimits)
                } else {
                    await scheduleMessageRefresh(for: sessionID, reason: .partDeltaMiss(partID: partID, field: field, deltaBytes: delta.utf8.count))
                }
            case .messagePartRemoved:
                guard let partID = payload.string(.partID) else {
                    await scheduleMessageRefresh(for: sessionID, reason: .partRemovedMiss(partID: nil))
                    return
                }
                PerformanceInstrumentation.log(
                    "event-message-part-removed directory=\(directory) sessionID=\(sessionID) partID=\(partID)"
                )
                let removed = await withStore { store in
                    store.removeMessagePart(sessionID: sessionID, partID: partID)
                }
                if removed {
                    await repository.removeMessagePart(directory: directory, sessionID: sessionID, partID: partID, modelContextLimits: modelContextLimits)
                } else {
                    await scheduleMessageRefresh(for: sessionID, reason: .partRemovedMiss(partID: partID))
                }
            default:
                break
            }

        case .permissionAsked, .permissionReplied, .questionAsked, .questionReplied, .questionRejected:
            await refreshInteractions(sessionID: eventSessionID(from: payload))

        case .todoUpdated:
            if let sessionID = payload.string(.sessionID) {
                logger.notice(
                    "Todo updated event directory=\(self.directory, privacy: .public) sessionID=\(sessionID, privacy: .public)"
                )
                await refreshTodos(sessionID: sessionID)
            }

        case .sessionError:
            let sessionID = eventSessionID(from: payload) ?? "nil"
            logger.error(
                "Session error event directory=\(self.directory, privacy: .public) sessionID=\(sessionID, privacy: .public) details=\(self.payloadSummary(payload), privacy: .public)"
            )
            return

        case .unknown:
            logger.notice(
                "Unknown SSE event directory=\(self.directory, privacy: .public) details=\(self.payloadSummary(payload), privacy: .public)"
            )
            return
        }
    }

    private func withStore<T: Sendable>(_ body: @MainActor @escaping (WorkspaceLiveStore) -> T) async -> T {
        let store = await storeRegistry.store(for: connection)
        return await MainActor.run {
            body(store)
        }
    }

    private func scheduleMessageRefresh(for sessionID: String, reason: MessageRefreshReason) async {
        let rescheduled = messageRefreshTasks[sessionID] != nil
        logger.notice(
            "Scheduling message refresh for \(sessionID, privacy: .public) rescheduled=\(rescheduled, privacy: .public) reason=\(reason.summary, privacy: .public)"
        )
        messageRefreshTasks[sessionID]?.cancel()
        messageRefreshTasks[sessionID] = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            logger.notice("Executing scheduled message refresh for \(sessionID, privacy: .public) reason=\(reason.summary, privacy: .public)")
            await refreshMessages(sessionID: sessionID)
        }
    }

    private func scheduleSessionRefresh() async {
        logger.notice("Scheduling session refresh")
        sessionRefreshTask?.cancel()
        sessionRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let sessions = try await workspaceService.loadSessions(directory: directory)
                let statuses = try await workspaceService.loadStatuses(directory: directory)
                let snapshot = WorkspaceSnapshot(sessions: sessions, statuses: statuses, questions: [], permissions: [])
                await repository.applyWorkspaceSnapshot(
                    directory: directory,
                    snapshot: snapshot,
                    modelContextLimits: modelContextLimits,
                    openSessionIDs: openSessionIDs
                )
            } catch {
                logger.error("Session refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func eventSessionID(from payload: EventPayload) -> String? {
        if let sessionID = payload.string(.sessionID) {
            return sessionID
        }

        if let sessionID = payload.object(.info)?[EventPropertyKey.sessionID.rawValue]?.stringValue {
            return sessionID
        }

        if let sessionID = payload.object(.part)?[EventPropertyKey.sessionID.rawValue]?.stringValue {
            return sessionID
        }

        return nil
    }

    private func decodeEventStreamLine(from data: Data) -> String {
        var lineData = data

        if lineData.last == 0x0D {
            lineData.removeLast()
        }

        return String(decoding: lineData, as: UTF8.self)
    }

    private func payloadSummary(_ payload: EventPayload) -> String {
        let sessionID = eventSessionID(from: payload) ?? "nil"
        let details = payload.propertyObject.isEmpty
            ? "none"
            : payload.propertyObject
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.prettyDescription)" }
                .joined(separator: " | ")
        return "type=\(payload.type.rawString) sessionID=\(sessionID) properties=\(details)"
    }
}
