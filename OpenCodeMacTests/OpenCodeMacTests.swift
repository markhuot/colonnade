import Foundation
import XCTest
@testable import OpenCodeMac

final class TodoProgressTests: XCTestCase {
    func testFromCountsOnlyNonCancelledTodos() {
        let todos = [
            SessionTodo(content: "pending", status: .pending, priority: .high),
            SessionTodo(content: "done", status: .completed, priority: .medium),
            SessionTodo(content: "active", status: .inProgress, priority: .low),
            SessionTodo(content: "skip", status: .cancelled, priority: .low)
        ]

        let progress = TodoProgress.from(todos)

        XCTAssertEqual(progress?.completed, 1)
        XCTAssertEqual(progress?.total, 3)
        XCTAssertEqual(progress?.actionable, 2)
        XCTAssertEqual(progress?.percentageText, "33%")
    }

    func testFromReturnsNilWhenNoActionableTodosRemain() {
        let todos = [
            SessionTodo(content: "done", status: .completed, priority: .medium),
            SessionTodo(content: "cancelled", status: .cancelled, priority: .low)
        ]

        XCTAssertNil(TodoProgress.from(todos))
    }
}

final class MessageInfoTests: XCTestCase {
    func testMarkdownRendererParsesCompletedLinkAcrossStreamedText() {
        let partial = MarkdownRenderer.attributedString(from: "See [Open")
        XCTAssertNotNil(partial)
        XCTAssertNil(partial?.runs.first?.link)

        let completed = MarkdownRenderer.attributedString(from: "See [OpenCode](https://opencode.ai)")

        XCTAssertEqual(String(completed?.characters ?? AttributedString("" ).characters), "See OpenCode")
        XCTAssertTrue(completed?.runs.contains(where: { $0.link?.absoluteString == "https://opencode.ai" }) == true)
    }

    func testModelContextKeyFallsBackToNestedModelReference() {
        let info = MessageInfo(
            id: "message-1",
            sessionID: "session-1",
            role: .assistant,
            time: .init(created: 1_234, completed: nil),
            parentID: nil,
            agent: nil,
            model: .init(providerID: "anthropic", modelID: "claude-sonnet"),
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

        XCTAssertEqual(info.modelContextKey, ModelContextKey(providerID: "anthropic", modelID: "claude-sonnet"))
    }

    func testMarkdownRendererParsesUnorderedAndOrderedLists() {
        let blocks = MarkdownRenderer.blocks(from: "Intro\n\n- first\n* second\n\n1. one\n2. two")

        XCTAssertEqual(
            blocks,
            [
                .paragraph("Intro"),
                .unorderedList([
                    .init(marker: "-", text: "first"),
                    .init(marker: "*", text: "second")
                ]),
                .orderedList([
                    .init(marker: "1.", text: "one"),
                    .init(marker: "2.", text: "two")
                ])
            ]
        )
    }

    func testMarkdownRendererParsesCodeFenceBlocks() {
        let blocks = MarkdownRenderer.blocks(from: "Before\n\n```\nlet x = 1\nprint(x)\n```\n\nAfter")

        XCTAssertEqual(
            blocks,
            [
                .paragraph("Before"),
                .codeFence("let x = 1\nprint(x)"),
                .paragraph("After")
            ]
        )
    }

    func testMarkdownRendererTreatsUnclosedFenceAsCodeFenceDuringStreaming() {
        let blocks = MarkdownRenderer.blocks(from: "```\npartial")

        XCTAssertEqual(blocks, [.codeFence("partial")])
    }
}

final class EventPayloadDecoderTests: XCTestCase {
    func testDecodeParsesStructuredPayload() throws {
        let payload = """
        {
          "type": "session.status",
          "properties": {
            "sessionID": "session-1",
            "status": {
              "type": "busy"
            }
          }
        }
        """

        let event = try EventPayloadDecoder().decode(payload)

        XCTAssertEqual(event.type, .sessionStatus)
        XCTAssertEqual(event.string(.sessionID), "session-1")
        XCTAssertEqual(event.object(.status)?.decoded(SessionStatus.self), .busy)
    }
}

final class WorkspaceServiceTests: XCTestCase {
    func testLoadWorkspaceReturnsValuesFromInjectedClient() async throws {
        let session = makeSession(id: "session-1")
        let question = makeQuestion(id: "question-1", sessionID: session.id)
        let permission = makePermission(id: "permission-1", sessionID: session.id)
        let client = MockOpenCodeAPIClient(
            sessions: [session],
            statuses: [session.id: .busy],
            questions: [question],
            permissions: [permission]
        )

        let snapshot = try await WorkspaceService(client: client).loadWorkspace(directory: "/tmp/project")

        XCTAssertEqual(snapshot.sessions, [session])
        XCTAssertEqual(snapshot.statuses, [session.id: .busy])
        XCTAssertEqual(snapshot.questions, [question])
        XCTAssertEqual(snapshot.permissions, [permission])
        XCTAssertEqual(client.recordedDirectories, ["/tmp/project", "/tmp/project", "/tmp/project", "/tmp/project"])
    }
}

@MainActor
final class OpenCodeAppStateTests: XCTestCase {
    func testCreateSessionUsesInjectedServiceAndCoordinatorRegistry() async throws {
        let directory = "/tmp/project"
        let session = makeSession(id: "created-session", directory: directory)
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let workspaceService = MockWorkspaceService(createSessionResult: session)
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppState(
            workspaceService: workspaceService,
            repository: repository,
            persistence: PersistenceController(inMemory: true),
            syncRegistry: registry,
            persistsWorkspacePaneState: false,
            initialDirectory: directory
        )

        appState.selectedDirectory = directory
        appState.createSession()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(workspaceService.createSessionCalls, [.init(directory: directory, title: nil, parentID: nil)])
        let resolvedCoordinator = await registry.coordinator(for: directory) as? MockWorkspaceSyncCoordinator
        XCTAssertTrue(resolvedCoordinator === coordinator)
        let refreshedTodos = await coordinator.refreshedTodosSessionIDsSnapshot()
        XCTAssertEqual(refreshedTodos, [session.id, session.id])
    }

    func testSendMessageUsesInjectedServiceAndCoordinator() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let persistence = PersistenceController(inMemory: true)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.modelCatalogResult = makeModelCatalog()
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppState(
            workspaceService: workspaceService,
            repository: repository,
            persistence: persistence,
            syncRegistry: registry,
            persistsWorkspacePaneState: false,
            initialDirectory: directory
        )

        await appState.load(directory: directory)
        appState.openSessionIDs = [session.id]
        appState.setSelectedModel("anthropic/claude-sonnet", for: session.id)
        appState.drafts[session.id] = "Ship it"
        appState.sendMessage(sessionID: session.id)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(workspaceService.sendMessageCalls.count, 1)
        XCTAssertEqual(workspaceService.sendMessageCalls.first?.directory, directory)
        XCTAssertEqual(workspaceService.sendMessageCalls.first?.sessionID, session.id)
        XCTAssertEqual(workspaceService.sendMessageCalls.first?.text, "Ship it")
        XCTAssertEqual(workspaceService.sendMessageCalls.first?.model, ModelReference(providerID: "anthropic", modelID: "claude-sonnet"))
        let refreshedMessages = await coordinator.refreshedMessageSessionIDsSnapshot()
        XCTAssertEqual(refreshedMessages.suffix(1), [session.id])
    }

    func testScrollFocusedSessionTimelineTargetsFocusedSession() {
        let appState = OpenCodeAppState(persistsWorkspacePaneState: false)
        appState.focusedSessionID = "session-1"

        appState.scrollFocusedSessionTimeline(to: .top)

        XCTAssertEqual(appState.focusedSessionScrollRequest?.sessionID, "session-1")
        XCTAssertEqual(appState.focusedSessionScrollRequest?.direction, .top)
    }

    func testScrollFocusedSessionTimelineGeneratesUniqueRequests() {
        let appState = OpenCodeAppState(persistsWorkspacePaneState: false)
        appState.focusedSessionID = "session-1"

        appState.scrollFocusedSessionTimeline(to: .bottom)
        let firstRequest = appState.focusedSessionScrollRequest
        appState.scrollFocusedSessionTimeline(to: .bottom)

        XCTAssertEqual(appState.focusedSessionScrollRequest?.sessionID, "session-1")
        XCTAssertEqual(appState.focusedSessionScrollRequest?.direction, .bottom)
        XCTAssertNotEqual(appState.focusedSessionScrollRequest?.id, firstRequest?.id)
    }

    func testFocusPreviousPaneMovesFocusAndRequestsPromptFocus() {
        let appState = OpenCodeAppState(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]
        appState.focusedSessionID = "session-2"

        appState.focusPreviousPane()

        XCTAssertEqual(appState.focusedSessionID, "session-1")
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, "session-1")
    }

    func testFocusNextPaneMovesFocusAndRequestsPromptFocus() {
        let appState = OpenCodeAppState(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]
        appState.focusedSessionID = "session-2"

        appState.focusNextPane()

        XCTAssertEqual(appState.focusedSessionID, "session-3")
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, "session-3")
    }

    func testFocusAdjacentPaneIgnoresOutOfBoundsRequests() {
        let appState = OpenCodeAppState(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2"]
        appState.focusedSessionID = "session-1"

        appState.focusPreviousPane()

        XCTAssertEqual(appState.focusedSessionID, "session-1")
        XCTAssertNil(appState.promptFocusRequest)
    }
}

final class FocusedSessionTimelineKeyEventTests: XCTestCase {
    func testScrollDirectionMapsHomeAndEndKeys() {
        XCTAssertEqual(
            FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 115, modifiers: [], isTextInputActive: false),
            .top
        )
        XCTAssertEqual(
            FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 119, modifiers: [], isTextInputActive: false),
            .bottom
        )
    }

    func testScrollDirectionIgnoresTextInputAndModifiedKeys() {
        XCTAssertNil(
            FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 115, modifiers: [], isTextInputActive: true)
        )
        XCTAssertNil(
            FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 119, modifiers: [.shift], isTextInputActive: false)
        )
    }
}

final class WorkspaceSyncCoordinatorTests: XCTestCase {
    func testRefreshAllUsesInjectedWorkspaceService() async throws {
        let directory = "/tmp/project"
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let service = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(
                sessions: [session],
                statuses: [session.id: .busy],
                questions: [],
                permissions: []
            ),
            messagesResult: [session.id: [makeMessage(sessionID: session.id)]],
            todosResult: [session.id: [SessionTodo(content: "todo", status: .pending, priority: .high)]]
        )

        let coordinator = WorkspaceSyncCoordinator(
            directory: directory,
            client: MockOpenCodeAPIClient(),
            workspaceService: service,
            repository: repository
        )

        try await coordinator.start(modelContextLimits: [:], openSessionIDs: [session.id])
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(service.loadWorkspaceDirectories, [directory])
        XCTAssertEqual(service.loadMessagesCalls, [.init(directory: directory, sessionID: session.id)])
        XCTAssertEqual(service.loadTodosCalls, [.init(directory: directory, sessionID: session.id)])

        let snapshot = await repository.loadSnapshot(directory: directory)
        XCTAssertEqual(snapshot.sessions.map(\.id), [session.id])
        XCTAssertEqual(snapshot.messagesBySession[session.id]?.count, 1)
    }

    func testRefreshStatusClearsStaleRetryWhenSessionBecomesIdle() async throws {
        let directory = "/tmp/project"
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let storeRegistry = WorkspaceLiveStoreRegistry()
        let session = makeSession(id: "session-1", directory: directory)
        let service = MockWorkspaceService(statusesResult: [:])

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(
                sessions: [session],
                statuses: [session.id: .retry(attempt: 1, message: "Retrying", next: 123)],
                questions: [],
                permissions: []
            ),
            modelContextLimits: [:],
            openSessionIDs: [session.id]
        )

        let store = await storeRegistry.store(for: directory)
        await MainActor.run {
            store.applyWorkspaceSnapshot(
                WorkspaceSnapshot(
                    sessions: [session],
                    statuses: [session.id: .retry(attempt: 1, message: "Retrying", next: 123)],
                    questions: [],
                    permissions: []
                )
            )
        }

        let coordinator = WorkspaceSyncCoordinator(
            directory: directory,
            client: MockOpenCodeAPIClient(),
            workspaceService: service,
            repository: repository,
            storeRegistry: storeRegistry
        )

        await coordinator.refreshStatus(sessionID: session.id)

        let snapshot = await repository.loadSnapshot(directory: directory)
        XCTAssertNil(snapshot.sessions.first?.status)

        let display = await MainActor.run {
            store.sessionDisplay(for: session.id)
        }
        XCTAssertNil(display?.status)
        XCTAssertEqual(display?.indicator.label, nil)
    }

    func testMessageUpdatedSeedsShellAndPartDeltaRendersWithoutRefresh() async throws {
        let directory = "/tmp/project"
        let storeRegistry = WorkspaceLiveStoreRegistry()
        let store = await storeRegistry.store(for: directory)
        let session = makeSession(id: "session-1", directory: directory)
        let messageID = "message-1"
        let partID = "part-1"

        await MainActor.run {
            store.applyWorkspaceSnapshot(
                WorkspaceSnapshot(
                    sessions: [session],
                    statuses: [:],
                    questions: [],
                    permissions: []
                )
            )

            store.upsertMessageInfo(
                MessageInfo(
                    id: messageID,
                    sessionID: session.id,
                    role: .assistant,
                    time: .init(created: 2_000, completed: nil),
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
            )

            XCTAssertTrue(store.applyMessagePartDelta(sessionID: session.id, partID: partID, field: .text, delta: "Hello"))

            let appliedPart = store.applyMessagePart(
                MessagePart(
                    id: partID,
                    sessionID: session.id,
                    messageID: messageID,
                    type: .text,
                    text: nil,
                    synthetic: nil,
                    ignored: nil,
                    time: .init(start: 2_000, end: nil, compacted: nil),
                    metadata: nil,
                    callID: nil,
                    tool: nil,
                    state: nil,
                    mime: nil,
                    filename: nil,
                    url: nil,
                    reason: nil,
                    cost: nil,
                    tokens: nil,
                    prompt: nil,
                    description: nil,
                    agent: nil,
                    model: nil,
                    command: nil,
                    name: nil,
                    source: nil,
                    hash: nil,
                    files: nil,
                    snapshot: nil
                )
            )

            XCTAssertEqual(appliedPart?.text, "Hello")
            let messages = store.sessionState(for: session.id).messages
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages.first?.visibleText, "Hello")
        }
    }

    func testMessagePartUpdatedSeedsAssistantMessageWithoutPriorMessageRefresh() async throws {
        let directory = "/tmp/project"
        let storeRegistry = WorkspaceLiveStoreRegistry()
        let store = await storeRegistry.store(for: directory)
        let session = makeSession(id: "session-1", directory: directory)

        await MainActor.run {
            store.applyWorkspaceSnapshot(
                WorkspaceSnapshot(
                    sessions: [session],
                    statuses: [:],
                    questions: [],
                    permissions: []
                )
            )

            let appliedPart = store.applyMessagePart(
                MessagePart(
                    id: "part-1",
                    sessionID: session.id,
                    messageID: "message-1",
                    type: .text,
                    text: "Final answer",
                    synthetic: nil,
                    ignored: nil,
                    time: .init(start: 2_000, end: nil, compacted: nil),
                    metadata: nil,
                    callID: nil,
                    tool: nil,
                    state: nil,
                    mime: nil,
                    filename: nil,
                    url: nil,
                    reason: nil,
                    cost: nil,
                    tokens: nil,
                    prompt: nil,
                    description: nil,
                    agent: nil,
                    model: nil,
                    command: nil,
                    name: nil,
                    source: nil,
                    hash: nil,
                    files: nil,
                    snapshot: nil
                )
            )

            XCTAssertEqual(appliedPart?.text, "Final answer")
            let messages = store.sessionState(for: session.id).messages
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages.first?.id, "message-1")
            XCTAssertEqual(messages.first?.info.role, .assistant)
            XCTAssertEqual(messages.first?.visibleText, "Final answer")
        }
    }

    func testLoadSnapshotFlushesBufferedStreamingDeltas() async throws {
        let directory = "/tmp/project"
        let session = makeSession(id: "session-1", directory: directory)
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: []),
            modelContextLimits: [:],
            openSessionIDs: [session.id]
        )

        await repository.upsertMessageInfo(
            directory: directory,
            sessionID: session.id,
            info: MessageInfo(
                id: "message-1",
                sessionID: session.id,
                role: .assistant,
                time: .init(created: 2_000, completed: nil),
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
            ),
            modelContextLimits: [:]
        )

        await repository.upsertMessagePart(
            directory: directory,
            sessionID: session.id,
            part: makeMessagePart(id: "part-1", sessionID: session.id, messageID: "message-1"),
            modelContextLimits: [:]
        )
        await repository.applyMessagePartDelta(
            directory: directory,
            sessionID: session.id,
            partID: "part-1",
            field: .text,
            delta: "Hello",
            modelContextLimits: [:]
        )
        await repository.applyMessagePartDelta(
            directory: directory,
            sessionID: session.id,
            partID: "part-1",
            field: .text,
            delta: " world",
            modelContextLimits: [:]
        )

        let snapshot = await repository.loadSnapshot(directory: directory)

        XCTAssertEqual(snapshot.messagesBySession[session.id]?.first?.visibleText, "Hello world")
    }

    func testExplicitFlushPersistsBufferedRemovalsAfterDeltas() async throws {
        let directory = "/tmp/project"
        let session = makeSession(id: "session-1", directory: directory)
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: []),
            modelContextLimits: [:],
            openSessionIDs: [session.id]
        )

        await repository.upsertMessageInfo(
            directory: directory,
            sessionID: session.id,
            info: MessageInfo(
                id: "message-1",
                sessionID: session.id,
                role: .assistant,
                time: .init(created: 2_000, completed: nil),
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
            ),
            modelContextLimits: [:]
        )

        await repository.upsertMessagePart(
            directory: directory,
            sessionID: session.id,
            part: makeMessagePart(id: "part-1", sessionID: session.id, messageID: "message-1", text: "seed"),
            modelContextLimits: [:]
        )
        await repository.applyMessagePartDelta(
            directory: directory,
            sessionID: session.id,
            partID: "part-1",
            field: .text,
            delta: " more",
            modelContextLimits: [:]
        )
        await repository.removeMessage(
            directory: directory,
            sessionID: session.id,
            messageID: "message-1",
            modelContextLimits: [:]
        )
        await repository.flushBufferedStreamMutations()

        let snapshot = await repository.loadSnapshot(directory: directory)

        XCTAssertNil(snapshot.messagesBySession[session.id])
    }
}

private final class MockWorkspaceService: WorkspaceServiceProtocol, @unchecked Sendable {
    struct CreateSessionCall: Equatable {
        let directory: String
        let title: String?
        let parentID: String?
    }

    struct MessageCall: Equatable {
        let directory: String
        let sessionID: String
        let text: String
        let model: ModelReference?
        let variant: String?
    }

    struct SessionCall: Equatable {
        let directory: String
        let sessionID: String
    }

    private let lock = NSLock()

    var workspaceSnapshotResult: WorkspaceSnapshot
    var interactionSnapshotResult: InteractionSnapshot
    var createSessionResult: OpenCodeSession
    var archiveSessionResult: OpenCodeSession
    var loadSessionsResult: [OpenCodeSession]
    var messagesResult: [String: [MessageEnvelope]]
    var todosResult: [String: [SessionTodo]]
    var statusesResult: [String: SessionStatus]
    var modelContextLimitsResult: [ModelContextKey: Int]
    var modelCatalogResult: ModelCatalog

    private(set) var loadWorkspaceDirectories: [String] = []
    private(set) var loadInteractionsDirectories: [String] = []
    private(set) var createSessionCalls: [CreateSessionCall] = []
    private(set) var archiveSessionCalls: [SessionCall] = []
    private(set) var loadSessionsDirectories: [String] = []
    private(set) var loadMessagesCalls: [SessionCall] = []
    private(set) var loadTodosCalls: [SessionCall] = []
    private(set) var loadStatusesDirectories: [String] = []
    private(set) var sendMessageCalls: [MessageCall] = []

    init(
        workspaceSnapshotResult: WorkspaceSnapshot = WorkspaceSnapshot(sessions: [], statuses: [:], questions: [], permissions: []),
        interactionSnapshotResult: InteractionSnapshot = InteractionSnapshot(questions: [], permissions: []),
        createSessionResult: OpenCodeSession = makeSession(id: "created-session"),
        archiveSessionResult: OpenCodeSession = makeSession(id: "archived-session"),
        loadSessionsResult: [OpenCodeSession] = [],
        messagesResult: [String: [MessageEnvelope]] = [:],
        todosResult: [String: [SessionTodo]] = [:],
        statusesResult: [String: SessionStatus] = [:],
        modelContextLimitsResult: [ModelContextKey: Int] = [:],
        modelCatalogResult: ModelCatalog = .init(providers: [], defaultModels: [:], connectedProviderIDs: [])
    ) {
        self.workspaceSnapshotResult = workspaceSnapshotResult
        self.interactionSnapshotResult = interactionSnapshotResult
        self.createSessionResult = createSessionResult
        self.archiveSessionResult = archiveSessionResult
        self.loadSessionsResult = loadSessionsResult
        self.messagesResult = messagesResult
        self.todosResult = todosResult
        self.statusesResult = statusesResult
        self.modelContextLimitsResult = modelContextLimitsResult
        self.modelCatalogResult = modelCatalogResult
    }

    func loadWorkspace(directory: String) async throws -> WorkspaceSnapshot {
        record { loadWorkspaceDirectories.append(directory) }
        return workspaceSnapshotResult
    }

    func loadInteractions(directory: String) async throws -> InteractionSnapshot {
        record { loadInteractionsDirectories.append(directory) }
        return interactionSnapshotResult
    }

    func createSession(directory: String, title: String?, parentID: String?) async throws -> OpenCodeSession {
        record { createSessionCalls.append(.init(directory: directory, title: title, parentID: parentID)) }
        return createSessionResult
    }

    func archiveSession(directory: String, sessionID: String) async throws -> OpenCodeSession {
        record { archiveSessionCalls.append(.init(directory: directory, sessionID: sessionID)) }
        return archiveSessionResult
    }

    func loadSessions(directory: String) async throws -> [OpenCodeSession] {
        record { loadSessionsDirectories.append(directory) }
        return loadSessionsResult
    }

    func loadMessages(directory: String, sessionID: String) async throws -> [MessageEnvelope] {
        record { loadMessagesCalls.append(.init(directory: directory, sessionID: sessionID)) }
        return messagesResult[sessionID, default: []]
    }

    func loadTodos(directory: String, sessionID: String) async throws -> [SessionTodo] {
        record { loadTodosCalls.append(.init(directory: directory, sessionID: sessionID)) }
        return todosResult[sessionID, default: []]
    }

    func loadStatuses(directory: String) async throws -> [String: SessionStatus] {
        record { loadStatusesDirectories.append(directory) }
        return statusesResult
    }

    func loadModelContextLimits() async throws -> [ModelContextKey: Int] {
        modelContextLimitsResult
    }

    func loadModelCatalog() async throws -> ModelCatalog {
        modelCatalogResult
    }

    func sendMessage(directory: String, sessionID: String, text: String, model: ModelReference?, variant: String?) async throws {
        record { sendMessageCalls.append(.init(directory: directory, sessionID: sessionID, text: text, model: model, variant: variant)) }
    }

    func replyToPermission(directory: String, requestID: String, reply: PermissionReply) async throws {}
    func replyToQuestion(directory: String, requestID: String, answers: [[String]]) async throws {}
    func rejectQuestion(directory: String, requestID: String) async throws {}

    private func record(_ update: () -> Void) {
        lock.lock()
        update()
        lock.unlock()
    }
}

private actor MockWorkspaceSyncCoordinator: WorkspaceSyncCoordinating {
    private(set) var startedCalls: [([ModelContextKey: Int], [String], Bool)] = []
    private(set) var updatedModelContextLimits: [[ModelContextKey: Int]] = []
    private(set) var updatedOpenSessionIDs: [[String]] = []
    private(set) var refreshedMessageSessionIDs: [String] = []
    private(set) var refreshedTodosSessionIDs: [String] = []
    private(set) var refreshedInteractionsCount = 0

    func start(modelContextLimits: [ModelContextKey: Int], openSessionIDs: [String], performInitialSync: Bool) async throws {
        startedCalls.append((modelContextLimits, openSessionIDs, performInitialSync))
    }

    func updateModelContextLimits(_ limits: [ModelContextKey: Int]) async {
        updatedModelContextLimits.append(limits)
    }

    func updateOpenSessionIDs(_ openSessionIDs: [String]) async {
        updatedOpenSessionIDs.append(openSessionIDs)
    }

    func refreshAll() async throws {}

    func refreshMessages(sessionID: String) async {
        refreshedMessageSessionIDs.append(sessionID)
    }

    func refreshTodos(sessionID: String) async {
        refreshedTodosSessionIDs.append(sessionID)
    }

    func refreshInteractions(sessionID _: String?) async {
        refreshedInteractionsCount += 1
    }

    func refreshedMessageSessionIDsSnapshot() -> [String] {
        refreshedMessageSessionIDs
    }

    func refreshedTodosSessionIDsSnapshot() -> [String] {
        refreshedTodosSessionIDs
    }
}

private actor TestWorkspaceSyncRegistry: WorkspaceSyncRegistryProtocol {
    private let coordinatorInstance: any WorkspaceSyncCoordinating

    init(coordinator: any WorkspaceSyncCoordinating) {
        coordinatorInstance = coordinator
    }

    func coordinator(for directory: String) -> any WorkspaceSyncCoordinating {
        coordinatorInstance
    }
}

private final class MockOpenCodeAPIClient: OpenCodeAPIClientProtocol, @unchecked Sendable {
    let sessionsResult: [OpenCodeSession]
    let statusesResult: [String: SessionStatus]
    let questionsResult: [QuestionRequest]
    let permissionsResult: [PermissionRequest]

    private let lock = NSLock()
    private(set) var recordedDirectories: [String] = []

    init(
        sessions: [OpenCodeSession] = [],
        statuses: [String: SessionStatus] = [:],
        questions: [QuestionRequest] = [],
        permissions: [PermissionRequest] = []
    ) {
        sessionsResult = sessions
        statusesResult = statuses
        questionsResult = questions
        permissionsResult = permissions
    }

    func sessions(directory: String) async throws -> [OpenCodeSession] {
        record(directory)
        return sessionsResult
    }

    func sessionStatus(directory: String) async throws -> [String: SessionStatus] {
        record(directory)
        return statusesResult
    }

    func messages(directory: String, sessionID: String) async throws -> [MessageEnvelope] {
        record(directory)
        return []
    }

    func todos(directory: String, sessionID: String) async throws -> [SessionTodo] {
        record(directory)
        return []
    }

    func createSession(directory: String, title: String?, parentID: String?) async throws -> OpenCodeSession {
        record(directory)
        throw TestError.unimplemented
    }

    func archiveSession(directory: String, sessionID: String, archivedAtMS: Double) async throws -> OpenCodeSession {
        record(directory)
        throw TestError.unimplemented
    }

    func sendMessage(directory: String, sessionID: String, text: String, model: ModelReference?, variant: String?) async throws {
        record(directory)
    }

    func modelCatalog() async throws -> ModelCatalog {
        .init(providers: [], defaultModels: [:], connectedProviderIDs: [])
    }

    func questions(directory: String) async throws -> [QuestionRequest] {
        record(directory)
        return questionsResult
    }

    func permissions(directory: String) async throws -> [PermissionRequest] {
        record(directory)
        return permissionsResult
    }

    func modelContextLimits() async throws -> [ModelContextKey: Int] {
        [:]
    }

    func replyToQuestion(directory: String, requestID: String, answers: [[String]]) async throws {
        record(directory)
    }

    func rejectQuestion(directory: String, requestID: String) async throws {
        record(directory)
    }

    func replyToPermission(directory: String, requestID: String, reply: PermissionReply, message: String?) async throws {
        record(directory)
    }

    func openEventStream(directory: String) async throws -> OpenCodeAPIClient.EventStreamConnection {
        record(directory)
        throw TestError.unimplemented
    }

    private func record(_ directory: String) {
        lock.lock()
        recordedDirectories.append(directory)
        lock.unlock()
    }
}

private enum TestError: Error {
    case unimplemented
}

private func makeSession(id: String, directory: String = "/tmp/project") -> OpenCodeSession {
    OpenCodeSession(
        id: id,
        slug: id,
        projectID: "project-1",
        workspaceID: "workspace-1",
        directory: directory,
        parentID: nil,
        title: "Session \(id)",
        version: "1",
        summary: nil,
        time: .init(created: 1_000, updated: 2_000, compacting: nil, archived: nil)
    )
}

private func makeQuestion(id: String, sessionID: String) -> QuestionRequest {
    QuestionRequest(
        id: id,
        sessionID: sessionID,
        questions: [
            .init(
                question: "Pick one",
                header: "Choice",
                options: [.init(label: "A", description: "Alpha")],
                multiple: false,
                custom: false
            )
        ]
    )
}

private func makePermission(id: String, sessionID: String) -> PermissionRequest {
    PermissionRequest(
        id: id,
        sessionID: sessionID,
        permission: "write",
        patterns: ["*.swift"],
        metadata: [:],
        always: [],
        tool: .init(messageID: "message-1", callID: "call-1")
    )
}

private func makeModelCatalog() -> ModelCatalog {
    ModelCatalog(
        providers: [
            ModelProvider(
                id: "anthropic",
                name: "Anthropic",
                models: [
                    "claude-sonnet": ModelDefinition(
                        id: "claude-sonnet",
                        providerID: "anthropic",
                        name: "Claude Sonnet",
                        family: nil,
                        status: "active",
                        capabilities: .init(reasoning: true, toolcall: true, input: .init(text: true), output: .init(text: true)),
                        limit: .init(context: 200_000),
                        variants: ["high": .init(reasoningEffort: nil, reasoningSummary: nil, include: nil)],
                        releaseDate: nil
                    )
                ]
            )
        ],
        defaultModels: ["anthropic": "claude-sonnet"],
        connectedProviderIDs: ["anthropic"]
    )
}

private func makeMessage(sessionID: String, providerID: String = "anthropic", modelID: String = "claude-sonnet") -> MessageEnvelope {
    MessageEnvelope(
        info: MessageInfo(
            id: "message-\(sessionID)",
            sessionID: sessionID,
            role: .assistant,
            time: .init(created: 1_500, completed: nil),
            parentID: nil,
            agent: nil,
            model: .init(providerID: providerID, modelID: modelID),
            modelID: nil,
            providerID: nil,
            mode: nil,
            path: nil,
            cost: nil,
            tokens: .init(total: 100, input: 40, output: 60, reasoning: nil, cache: nil),
            finish: nil,
            summary: nil,
            error: nil
        ),
        parts: [
            MessagePart(
                id: "part-\(sessionID)",
                sessionID: sessionID,
                messageID: "message-\(sessionID)",
                type: .text,
                text: "Hello",
                synthetic: nil,
                ignored: nil,
                time: nil,
                metadata: nil,
                callID: nil,
                tool: nil,
                state: nil,
                mime: nil,
                filename: nil,
                url: nil,
                reason: nil,
                cost: nil,
                tokens: nil,
                prompt: nil,
                description: nil,
                agent: nil,
                model: nil,
                command: nil,
                name: nil,
                source: nil,
                hash: nil,
                files: nil,
                snapshot: nil
            )
        ]
    )
}

private func makeMessagePart(id: String, sessionID: String, messageID: String, text: String? = nil) -> MessagePart {
    MessagePart(
        id: id,
        sessionID: sessionID,
        messageID: messageID,
        type: .text,
        text: text,
        synthetic: nil,
        ignored: nil,
        time: .init(start: 2_000, end: nil, compacted: nil),
        metadata: nil,
        callID: nil,
        tool: nil,
        state: nil,
        mime: nil,
        filename: nil,
        url: nil,
        reason: nil,
        cost: nil,
        tokens: nil,
        prompt: nil,
        description: nil,
        agent: nil,
        model: nil,
        command: nil,
        name: nil,
        source: nil,
        hash: nil,
        files: nil,
        snapshot: nil
    )
}

private func makeTemporaryDirectory() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}
