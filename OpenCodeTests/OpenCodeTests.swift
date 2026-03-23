import Foundation
import XCTest
@testable import OpenCode

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
}

final class ThemeControllerTests: XCTestCase {
    @MainActor
    func testThemeControllerDefaultsToNative() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let controller = ThemeController(defaults: defaults)

        XCTAssertEqual(controller.selectedThemeID, .native)
        XCTAssertEqual(controller.selectedTheme.id, .native)
    }

    @MainActor
    func testThemeControllerRestoresAndPersistsSelection() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(OpenCodeThemeID.githubDark.rawValue, forKey: ThemeController.Constants.selectedThemeKey)

        let controller = ThemeController(defaults: defaults)
        XCTAssertEqual(controller.selectedThemeID, .githubDark)

        controller.selectTheme(.nord)

        XCTAssertEqual(controller.selectedThemeID, .nord)
        XCTAssertEqual(defaults.string(forKey: ThemeController.Constants.selectedThemeKey), OpenCodeThemeID.nord.rawValue)
    }
}

final class MessagePartToolPresentationTests: XCTestCase {
    func testApplyPatchPresentationSummarizesFilesAndDiffStats() {
        let part = makeToolMessagePart(
            tool: "functions.apply_patch",
            input: [
                "patchText": .string("*** Begin Patch\n*** Update File: Sources/Foo.swift\n*** Add File: Sources/Bar.swift\n*** End Patch")
            ],
            metadata: [
                "summary": .object([
                    "additions": .number(12),
                    "deletions": .number(3)
                ])
            ]
        )

        let presentation = part.toolPresentation

        guard case let .patch(summary) = presentation.summaryStyle else {
            return XCTFail("Expected patch summary style")
        }

        XCTAssertEqual(summary.target, "Foo.swift +1")
        XCTAssertEqual(summary.additions, 12)
        XCTAssertEqual(summary.deletions, 3)
        XCTAssertEqual(presentation.detailFields, [ToolDetailField(title: "Files", value: "Foo.swift\nBar.swift")])
        XCTAssertNil(presentation.statusLabel)
        XCTAssertNil(presentation.fallbackDetail)

        guard case let .patch(detail) = presentation.drawerStyle else {
            return XCTFail("Expected patch drawer style")
        }

        XCTAssertEqual(detail.files.map(\.path), ["Sources/Foo.swift", "Sources/Bar.swift"])
        XCTAssertEqual(detail.files.map(\.operation), [.updated, .added])
    }

    func testApplyPatchPresentationBuildsInlineDiffData() {
        let part = makeToolMessagePart(
            tool: "functions.apply_patch",
            input: [
                "patchText": .string(
                    "*** Begin Patch\n*** Update File: Sources/Foo.swift\n@@\n-old line\n same line\n+new line\n*** End Patch"
                )
            ]
        )

        let presentation = part.toolPresentation

        guard case let .patch(detail) = presentation.drawerStyle else {
            return XCTFail("Expected patch drawer style")
        }

        XCTAssertEqual(detail.files.count, 1)
        XCTAssertEqual(detail.files[0].path, "Sources/Foo.swift")
        XCTAssertEqual(detail.files[0].hunks.count, 1)
        XCTAssertEqual(detail.files[0].hunks[0].header, "@@")
        XCTAssertEqual(
            detail.files[0].hunks[0].lines,
            [
                ToolPatchLine(id: 0, kind: .deletion, text: "old line"),
                ToolPatchLine(id: 1, kind: .context, text: "same line"),
                ToolPatchLine(id: 2, kind: .addition, text: "new line")
            ]
        )
    }

    func testApplyPatchPresentationCapturesMoveDestination() {
        let part = makeToolMessagePart(
            tool: "functions.apply_patch",
            input: [
                "patchText": .string(
                    "*** Begin Patch\n*** Update File: Sources/Foo.swift\n*** Move to: Sources/Bar.swift\n*** End Patch"
                )
            ]
        )

        let presentation = part.toolPresentation

        guard case let .patch(detail) = presentation.drawerStyle else {
            return XCTFail("Expected patch drawer style")
        }

        XCTAssertEqual(detail.files.count, 1)
        XCTAssertEqual(detail.files[0].path, "Sources/Foo.swift")
        XCTAssertEqual(detail.files[0].destinationPath, "Sources/Bar.swift")
        XCTAssertEqual(detail.files[0].operation, .moved)
    }

    func testToolDrawerTitleHidesDuplicateOutput() {
        let repeated = "Success. Updated the following files:\nSources/Foo.swift"
        let part = makeToolMessagePart(
            tool: "functions.apply_patch",
            output: repeated,
            title: repeated
        )

        XCTAssertNil(part.toolDrawerTitle)
    }

    func testToolDrawerTitleKeepsDistinctTitle() {
        let part = makeToolMessagePart(
            tool: "functions.apply_patch",
            output: "Success. Updated the following files:\nSources/Foo.swift",
            title: "Applying patch"
        )

        XCTAssertEqual(part.toolDrawerTitle, "Applying patch")
    }

    func testBashPresentationPrefersDescriptionAndExposesCommandDetails() {
        let part = makeToolMessagePart(
            tool: "functions.bash",
            status: .running,
            input: [
                "description": .string("shows working tree status"),
                "command": .string("git status --short")
            ]
        )

        let presentation = part.toolPresentation

        guard case let .standard(summary) = presentation.summaryStyle else {
            return XCTFail("Expected standard summary style")
        }

        XCTAssertEqual(summary.action, "Shows working tree status")
        XCTAssertNil(summary.target)
        XCTAssertEqual(presentation.detailFields, [ToolDetailField(title: "Command", value: "git status --short")])
        XCTAssertEqual(presentation.statusLabel, "Running")
        XCTAssertNil(presentation.fallbackDetail)
    }

    func testReadPresentationUsesDedicatedSummaryStyle() {
        let part = makeToolMessagePart(
            tool: "functions.read",
            input: [
                "filePath": .string("/tmp/Notes.swift")
            ]
        )

        let presentation = part.toolPresentation

        guard case let .read(summary) = presentation.summaryStyle else {
            return XCTFail("Expected read summary style")
        }

        XCTAssertEqual(summary.fileName, "Notes.swift")
        XCTAssertEqual(summary.path, "/tmp/Notes.swift")
    }

    func testUnknownToolFallsBackToStatusWhenThereAreNoDetails() {
        let part = makeToolMessagePart(tool: "functions.custom_tool", status: .pending)

        let presentation = part.toolPresentation

        guard case let .standard(summary) = presentation.summaryStyle else {
            return XCTFail("Expected standard summary style")
        }

        XCTAssertEqual(summary.action, "Custom Tool")
        XCTAssertEqual(presentation.statusLabel, "Pending")
        XCTAssertEqual(presentation.fallbackDetail, "Pending")
        XCTAssertTrue(presentation.detailFields.isEmpty)
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
final class OpenCodeAppModelTests: XCTestCase {
    func testCreateSessionUsesInjectedServiceAndCoordinatorRegistry() async throws {
        let directory = "/tmp/project"
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: directory)
        let session = makeSession(id: "created-session", directory: directory)
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let workspaceService = MockWorkspaceService(createSessionResult: session)
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false,
            initialDirectory: directory
        )

        appState.selectedDirectory = directory
        appState.createSession()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(workspaceService.createSessionCalls, [.init(directory: directory, title: nil, parentID: nil)])
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, session.id)
        let resolvedCoordinator = await registry.coordinator(for: connection) as? MockWorkspaceSyncCoordinator
        XCTAssertTrue(resolvedCoordinator === coordinator)
        let refreshedTodos = await coordinator.refreshedTodosSessionIDsSnapshot()
        XCTAssertEqual(refreshedTodos, [session.id, session.id])
    }

    func testSendMessageUsesInjectedServiceAndCoordinator() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.modelCatalogResult = makeModelCatalog()
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
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
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.focusedSessionID = "session-1"

        appState.scrollFocusedSessionTimeline(to: .top)

        XCTAssertEqual(appState.focusedSessionScrollRequest?.sessionID, "session-1")
        XCTAssertEqual(appState.focusedSessionScrollRequest?.direction, .top)
    }

    func testScrollFocusedSessionTimelineGeneratesUniqueRequests() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.focusedSessionID = "session-1"

        appState.scrollFocusedSessionTimeline(to: .bottom)
        let firstRequest = appState.focusedSessionScrollRequest
        appState.scrollFocusedSessionTimeline(to: .bottom)

        XCTAssertEqual(appState.focusedSessionScrollRequest?.sessionID, "session-1")
        XCTAssertEqual(appState.focusedSessionScrollRequest?.direction, .bottom)
        XCTAssertNotEqual(appState.focusedSessionScrollRequest?.id, firstRequest?.id)
    }

    func testFocusPreviousPaneMovesFocusAndRequestsPromptFocus() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]
        appState.focusedSessionID = "session-2"

        appState.focusPreviousPane()

        XCTAssertEqual(appState.focusedSessionID, "session-1")
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, "session-1")
    }

    func testFocusNextPaneMovesFocusAndRequestsPromptFocus() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]
        appState.focusedSessionID = "session-2"

        appState.focusNextPane()

        XCTAssertEqual(appState.focusedSessionID, "session-3")
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, "session-3")
    }

    func testFocusAdjacentPaneIgnoresOutOfBoundsRequests() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2"]
        appState.focusedSessionID = "session-1"

        appState.focusPreviousPane()

        XCTAssertEqual(appState.focusedSessionID, "session-1")
        XCTAssertNil(appState.promptFocusRequest)
    }

    func testCloseFocusedSessionMovesFocusToPaneOnRight() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]
        appState.focusedSessionID = "session-2"

        appState.closeSession("session-2")

        XCTAssertEqual(appState.openSessionIDs, ["session-1", "session-3"])
        XCTAssertEqual(appState.focusedSessionID, "session-3")
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, "session-3")
    }

    func testCloseFocusedSessionMovesFocusToPaneOnLeftWhenNoPaneOnRight() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]
        appState.focusedSessionID = "session-3"

        appState.closeSession("session-3")

        XCTAssertEqual(appState.openSessionIDs, ["session-1", "session-2"])
        XCTAssertEqual(appState.focusedSessionID, "session-2")
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, "session-2")
    }

    func testCloseLastFocusedSessionClearsFocus() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1"]
        appState.focusedSessionID = "session-1"

        appState.closeSession("session-1")

        XCTAssertEqual(appState.openSessionIDs, [])
        XCTAssertNil(appState.focusedSessionID)
        XCTAssertNil(appState.promptFocusRequest)
    }

    func testWorkspaceCommandCenterTracksPaneFocusAfterBinding() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        let commandCenter = WorkspaceCommandCenter.shared

        commandCenter.bind(appState: appState)
        XCTAssertFalse(commandCenter.canFocusPreviousPane)
        XCTAssertFalse(commandCenter.canFocusNextPane)

        appState.openSessionIDs = ["session-1", "session-2"]
        appState.focusedSessionID = "session-1"

        XCTAssertTrue(commandCenter.canFocusPreviousPane)
        XCTAssertTrue(commandCenter.canFocusNextPane)

        appState.focusedSessionID = nil

        XCTAssertFalse(commandCenter.canFocusPreviousPane)
        XCTAssertFalse(commandCenter.canFocusNextPane)
    }

    func testWorkspaceCommandCenterEnablesPaneCommandsAtEdgesWhenPaneIsFocused() {
        let commandCenter = WorkspaceCommandCenter.shared

        commandCenter.updateAvailability(
            selectedDirectory: "/tmp/project",
            focusedSessionID: "session-1",
            openSessionIDs: ["session-1"]
        )

        XCTAssertTrue(commandCenter.canFocusPreviousPane)
        XCTAssertTrue(commandCenter.canFocusNextPane)
    }

    func testWorkspaceCommandCenterEnablesCloseSessionForFocusedWorkspacePane() {
        let commandCenter = WorkspaceCommandCenter.shared

        commandCenter.updateAvailability(
            selectedDirectory: "/tmp/project",
            focusedSessionID: "session-1",
            openSessionIDs: ["session-1"]
        )

        XCTAssertTrue(commandCenter.canCloseFocusedSession)
    }

    func testWorkspaceCommandCenterDisablesCloseSessionWithoutFocusedWorkspacePane() {
        let commandCenter = WorkspaceCommandCenter.shared

        commandCenter.updateAvailability(
            selectedDirectory: "/tmp/project",
            focusedSessionID: nil,
            openSessionIDs: ["session-1"]
        )

        XCTAssertFalse(commandCenter.canCloseFocusedSession)
    }

    func testLoadRestoresPersistedPaneStateAndClampsPaneWidths() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(
                sessions: [
                    makeSession(id: "session-1", directory: directory, updatedAt: 1_000),
                    makeSession(id: "session-2", directory: directory, updatedAt: 2_000)
                ],
                statuses: [:],
                questions: [],
                permissions: []
            )
        )
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        await repository.savePanes(
            directory: directory,
            panes: [
                SessionPaneState(sessionID: "session-2", position: 0, width: 1_400, isHidden: false),
                SessionPaneState(sessionID: "session-1", position: 1, width: 120, isHidden: false)
            ]
        )

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: true
        )

        await appState.load(directory: directory)

        XCTAssertEqual(appState.openSessionIDs, ["session-2", "session-1"])
        XCTAssertEqual(appState.focusedSessionID, "session-2")
        XCTAssertEqual(appState.paneWidth(for: "session-2"), appState.maxPaneWidth)
        XCTAssertEqual(appState.paneWidth(for: "session-1"), appState.minPaneWidth)
    }

    func testLoadOpensMostRecentVisibleSessionWhenNoPaneStateExists() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let visibleSession = makeSession(id: "session-visible", directory: directory, updatedAt: 3_000)
        let archivedSession = makeSession(id: "session-archived", directory: directory, updatedAt: 9_000, archivedAt: 9_000)
        let subagentSession = makeSession(id: "session-subagent", directory: directory, updatedAt: 8_000, parentID: "parent-1")
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(
                sessions: [archivedSession, subagentSession, visibleSession],
                statuses: [:],
                questions: [],
                permissions: []
            )
        )
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)

        XCTAssertEqual(appState.openSessionIDs, [visibleSession.id])
        XCTAssertEqual(appState.focusedSessionID, visibleSession.id)
    }

    func testLoadFailureRestoresPreviousWorkspaceState() async throws {
        let firstDirectory = try makeTemporaryDirectory()
        let secondDirectory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(
                sessions: [makeSession(id: "session-1", directory: firstDirectory)],
                statuses: [:],
                questions: [],
                permissions: []
            )
        )
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: firstDirectory)
        let originalLiveStore = appState.liveStore
        let originalSnapshot = appState.snapshot

        workspaceService.loadWorkspaceError = URLError(.badServerResponse)
        await appState.load(directory: secondDirectory)

        XCTAssertEqual(appState.selectedDirectory, firstDirectory)
        XCTAssertTrue(appState.liveStore === originalLiveStore)
        XCTAssertEqual(appState.snapshot, originalSnapshot)
        XCTAssertNotNil(appState.errorMessage)
    }

    func testConnectToRemoteServerNormalizesURLAndLoadsProjectSuggestions() async throws {
        let client = MockOpenCodeAPIClient(
            health: .init(healthy: true, version: "1.0.0"),
            projects: [
                makeProject(id: "project-b", worktree: "/tmp/b"),
                makeProject(id: "project-a", worktree: "/tmp/a")
            ]
        )

        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            apiClientProviderOverride: { _ in client }
        )
        appState.remoteServerURLText = "example.com"

        appState.connectToRemoteServer()
        try await waitForAsyncWork()

        XCTAssertEqual(appState.serverURL.absoluteString, "https://example.com")
        XCTAssertEqual(appState.remoteServerURLText, "https://example.com")
        XCTAssertEqual(appState.launchStage, .remoteDirectoryEntry)
        XCTAssertEqual(appState.remoteProjectSuggestions, ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(client.healthCallCount, 1)
        XCTAssertEqual(client.projectsCallCount, 1)
    }

    func testOpenLocalDirectoryStartsServerAndUsesInjectedChooser() async throws {
        let client = MockOpenCodeAPIClient(health: .init(healthy: false, version: "1.0.0"))
        let probe = LocalServerProbe()

        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            localServerStarter: {
                Task {
                    await probe.recordStart()
                }
                return LocalServerLaunchHandle()
            },
            apiClientProviderOverride: { _ in client },
            directoryChooser: {
                Task {
                    await probe.recordChooser()
                }
            },
            serverWaiter: { url, timeout in
                await probe.recordWait(url: url, timeout: timeout)
                return true
            }
        )

        appState.openLocalDirectory()
        try await waitForAsyncWork()

        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.startedCount, 1)
        XCTAssertEqual(snapshot.chooserCount, 1)
        XCTAssertEqual(snapshot.waitedURL, OpenCodeAppModel.defaultServerURL)
        XCTAssertEqual(snapshot.waitedTimeout, .seconds(10))
        XCTAssertEqual(appState.serverURL, OpenCodeAppModel.defaultServerURL)
        XCTAssertFalse(appState.isStartingLocalServer)
        XCTAssertNil(appState.errorMessage)
    }

    @MainActor
    func testSetDirectoryChooserReplacesDefaultNoOpChooser() async throws {
        let client = MockOpenCodeAPIClient(health: .init(healthy: false, version: "1.0.0"))
        let probe = LocalServerProbe()

        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            localServerStarter: {
                Task {
                    await probe.recordStart()
                }
                return LocalServerLaunchHandle()
            },
            apiClientProviderOverride: { _ in client },
            serverWaiter: { url, timeout in
                await probe.recordWait(url: url, timeout: timeout)
                return true
            }
        )

        appState.setDirectoryChooser {
            Task {
                await probe.recordChooser()
            }
        }

        appState.openLocalDirectory()
        try await waitForAsyncWork()

        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.startedCount, 1)
        XCTAssertEqual(snapshot.chooserCount, 1)
    }

    func testArchiveSessionUsesInjectedServiceAndUpdatesOpenSessions() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session1 = makeSession(id: "session-1", directory: directory, updatedAt: 3_000)
        let session2 = makeSession(id: "session-2", directory: directory, updatedAt: 2_000)
        let archived = makeSession(id: "session-1", directory: directory, updatedAt: 4_000, archivedAt: 4_000)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session1, session2], statuses: [:], questions: [], permissions: []),
            archiveSessionResult: archived
        )
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)
        appState.openSessionIDs = [session1.id, session2.id]
        appState.focusedSessionID = session1.id

        appState.archiveSession(session1.id)
        try await waitForAsyncWork()

        XCTAssertEqual(workspaceService.archiveSessionCalls, [.init(directory: directory, sessionID: session1.id)])
        XCTAssertEqual(appState.openSessionIDs, [session2.id])
        XCTAssertEqual(appState.focusedSessionID, session2.id)
        let updatedOpenSessions = await coordinator.updatedOpenSessionIDsSnapshot()
        XCTAssertEqual(updatedOpenSessions.last, [session2.id])
    }

    func testAnswerActionsUseInjectedServiceAndRefreshInteractions() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let question = makeQuestion(id: "question-1", sessionID: session.id)
        let permission = makePermission(id: "permission-1", sessionID: session.id)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)

        appState.answerPermission(permission, reply: .always)
        appState.answerQuestion(question, answers: [["A"]])
        appState.rejectQuestion(question)
        try await waitForAsyncWork()

        XCTAssertEqual(workspaceService.permissionReplyCalls, [.init(directory: directory, requestID: permission.id, reply: .always)])
        XCTAssertEqual(workspaceService.questionReplyCalls, [.init(directory: directory, requestID: question.id, answers: [["A"]])])
        XCTAssertEqual(workspaceService.rejectQuestionCalls, [.init(directory: directory, requestID: question.id)])
        let refreshedInteractionsCount = await coordinator.refreshedInteractionsCountSnapshot()
        XCTAssertEqual(refreshedInteractionsCount, 3)
    }

    func testPermissionForSessionDeduplicatesEquivalentRequests() async {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let store = WorkspaceLiveStore(connection: connection)
        let session = makeSession(id: "session-1", directory: connection.directory)
        let permission = makePermission(id: "permission-1", sessionID: session.id)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [permission, permission])
        )

        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.bindLiveStore(store)

        XCTAssertEqual(appState.permissionForSession(session.id).count, 1)
    }

    func testLoadPrefersRecentModelAndNormalizesThinkingLevelSelection() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.modelCatalogResult = makeRichModelCatalog()
        workspaceService.modelContextLimitsResult = [
            ModelContextKey(providerID: "openai", modelID: "gpt-4.1"): 128_000,
            ModelContextKey(providerID: "anthropic", modelID: "claude-sonnet"): 200_000
        ]

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
                model: .init(providerID: "openai", modelID: "gpt-4.1"),
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

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)

        XCTAssertEqual(appState.selectedModelOption(for: session.id)?.reference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
        XCTAssertEqual(appState.selectedThinkingLevel(for: session.id), OpenCodeAppModel.defaultThinkingLevel)
        XCTAssertEqual(appState.modelOptions(for: session.id).first?.reference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
    }

    func testSendMessageFailureRestoresDraftAndSetsError() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.sendMessageError = URLError(.notConnectedToInternet)
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)
        appState.drafts[session.id] = "Hello world"

        appState.sendMessage(sessionID: session.id)
        try await waitForAsyncWork()

        XCTAssertEqual(appState.drafts[session.id], "Hello world")
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertEqual(workspaceService.sendMessageCalls.count, 1)
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
    func testRetryStatusUsesBusyIndicatorTint() {
        let indicator = SessionIndicator.resolve(
            status: .retry(attempt: 1, message: "Retrying", next: 123),
            hasPendingPermission: false
        )

        XCTAssertEqual(indicator.tint, .busy)
        XCTAssertEqual(indicator.label, "Retrying")
        XCTAssertTrue(indicator.showsTodoProgress)
    }

    func testRefreshAllUsesInjectedWorkspaceService() async throws {
        let directory = "/tmp/project"
        let connection = WorkspaceConnection(serverURL: URL(string: "http://127.0.0.1:4096")!, directory: directory)
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
            connection: connection,
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
        let connection = WorkspaceConnection(serverURL: URL(string: "http://127.0.0.1:4096")!, directory: directory)
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

        let store = await storeRegistry.store(for: connection)
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
            connection: connection,
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
        let connection = WorkspaceConnection(serverURL: URL(string: "http://127.0.0.1:4096")!, directory: directory)
        let storeRegistry = WorkspaceLiveStoreRegistry()
        let store = await storeRegistry.store(for: connection)
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
        let connection = WorkspaceConnection(serverURL: URL(string: "http://127.0.0.1:4096")!, directory: directory)
        let storeRegistry = WorkspaceLiveStoreRegistry()
        let store = await storeRegistry.store(for: connection)
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

    func testEmptyWorkspaceSnapshotDoesNotPruneExistingSessions() async throws {
        let directory = "/tmp/project"
        let session = makeSession(id: "session-1", directory: directory)
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: []),
            modelContextLimits: [:],
            openSessionIDs: [session.id]
        )

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(sessions: [], statuses: [:], questions: [], permissions: []),
            modelContextLimits: [:],
            openSessionIDs: []
        )

        let snapshot = await repository.loadSnapshot(directory: directory)

        XCTAssertEqual(snapshot.sessions.map(\.id), [session.id])
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

    struct PermissionReplyCall: Equatable {
        let directory: String
        let requestID: String
        let reply: PermissionReply
    }

    struct QuestionReplyCall: Equatable {
        let directory: String
        let requestID: String
        let answers: [[String]]
    }

    struct RequestCall: Equatable {
        let directory: String
        let requestID: String
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
    var loadWorkspaceError: Error?
    var sendMessageError: Error?

    private(set) var loadWorkspaceDirectories: [String] = []
    private(set) var loadInteractionsDirectories: [String] = []
    private(set) var createSessionCalls: [CreateSessionCall] = []
    private(set) var archiveSessionCalls: [SessionCall] = []
    private(set) var loadSessionsDirectories: [String] = []
    private(set) var loadMessagesCalls: [SessionCall] = []
    private(set) var loadTodosCalls: [SessionCall] = []
    private(set) var loadStatusesDirectories: [String] = []
    private(set) var sendMessageCalls: [MessageCall] = []
    private(set) var permissionReplyCalls: [PermissionReplyCall] = []
    private(set) var questionReplyCalls: [QuestionReplyCall] = []
    private(set) var rejectQuestionCalls: [RequestCall] = []

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
        if let loadWorkspaceError {
            throw loadWorkspaceError
        }
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
        if let sendMessageError {
            throw sendMessageError
        }
    }

    func replyToPermission(directory: String, requestID: String, reply: PermissionReply) async throws {
        record { permissionReplyCalls.append(.init(directory: directory, requestID: requestID, reply: reply)) }
    }

    func replyToQuestion(directory: String, requestID: String, answers: [[String]]) async throws {
        record { questionReplyCalls.append(.init(directory: directory, requestID: requestID, answers: answers)) }
    }

    func rejectQuestion(directory: String, requestID: String) async throws {
        record { rejectQuestionCalls.append(.init(directory: directory, requestID: requestID)) }
    }

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

    func updatedOpenSessionIDsSnapshot() -> [[String]] {
        updatedOpenSessionIDs
    }

    func refreshedInteractionsCountSnapshot() -> Int {
        refreshedInteractionsCount
    }
}

private actor LocalServerProbe {
    struct Snapshot {
        let startedCount: Int
        let chooserCount: Int
        let waitedURL: URL?
        let waitedTimeout: Duration?
    }

    private var startedCount = 0
    private var chooserCount = 0
    private var waitedURL: URL?
    private var waitedTimeout: Duration?

    func recordStart() {
        startedCount += 1
    }

    func recordChooser() {
        chooserCount += 1
    }

    func recordWait(url: URL, timeout: Duration) {
        waitedURL = url
        waitedTimeout = timeout
    }

    func snapshot() -> Snapshot {
        Snapshot(
            startedCount: startedCount,
            chooserCount: chooserCount,
            waitedURL: waitedURL,
            waitedTimeout: waitedTimeout
        )
    }
}

private actor TestWorkspaceSyncRegistry: WorkspaceSyncRegistryProtocol {
    private let coordinatorInstance: any WorkspaceSyncCoordinating

    init(coordinator: any WorkspaceSyncCoordinating) {
        coordinatorInstance = coordinator
    }

    func coordinator(for connection: WorkspaceConnection) -> any WorkspaceSyncCoordinating {
        coordinatorInstance
    }
}

private final class MockOpenCodeAPIClient: OpenCodeAPIClientProtocol, @unchecked Sendable {
    let sessionsResult: [OpenCodeSession]
    let statusesResult: [String: SessionStatus]
    let questionsResult: [QuestionRequest]
    let permissionsResult: [PermissionRequest]
    let healthResult: OpenCodeServerHealth
    let projectsResult: [OpenCodeProject]

    private let lock = NSLock()
    private(set) var recordedDirectories: [String] = []
    private(set) var healthCallCount = 0
    private(set) var projectsCallCount = 0

    init(
        sessions: [OpenCodeSession] = [],
        statuses: [String: SessionStatus] = [:],
        questions: [QuestionRequest] = [],
        permissions: [PermissionRequest] = [],
        health: OpenCodeServerHealth = .init(healthy: true, version: "1.0.0"),
        projects: [OpenCodeProject] = []
    ) {
        sessionsResult = sessions
        statusesResult = statuses
        questionsResult = questions
        permissionsResult = permissions
        healthResult = health
        projectsResult = projects
    }

    func health() async throws -> OpenCodeServerHealth {
        recordSync {
            healthCallCount += 1
        }
        return healthResult
    }

    func projects() async throws -> [OpenCodeProject] {
        recordSync {
            projectsCallCount += 1
        }
        return projectsResult
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

    private func recordSync(_ update: () -> Void) {
        lock.lock()
        update()
        lock.unlock()
    }
}

private enum TestError: Error {
    case unimplemented
}

private func makeSession(
    id: String,
    directory: String = "/tmp/project",
    updatedAt: Double = 2_000,
    parentID: String? = nil,
    archivedAt: Double? = nil
) -> OpenCodeSession {
    OpenCodeSession(
        id: id,
        slug: id,
        projectID: "project-1",
        workspaceID: "workspace-1",
        directory: directory,
        parentID: parentID,
        title: "Session \(id)",
        version: "1",
        summary: nil,
        time: .init(created: 1_000, updated: updatedAt, compacting: nil, archived: archivedAt)
    )
}

private func makeProject(id: String, worktree: String) -> OpenCodeProject {
    OpenCodeProject(
        id: id,
        worktree: worktree,
        vcsDir: nil,
        vcs: nil,
        time: .init(created: 1_000, initialized: 1_000)
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

private func makeRichModelCatalog() -> ModelCatalog {
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
            ),
            ModelProvider(
                id: "openai",
                name: "OpenAI",
                models: [
                    "gpt-4.1": ModelDefinition(
                        id: "gpt-4.1",
                        providerID: "openai",
                        name: "GPT-4.1",
                        family: nil,
                        status: "active",
                        capabilities: .init(reasoning: true, toolcall: true, input: .init(text: true), output: .init(text: true)),
                        limit: .init(context: 128_000),
                        variants: [
                            "low": .init(reasoningEffort: nil, reasoningSummary: nil, include: nil),
                            "high": .init(reasoningEffort: nil, reasoningSummary: nil, include: nil)
                        ],
                        releaseDate: nil
                    )
                ]
            )
        ],
        defaultModels: ["anthropic": "claude-sonnet"],
        connectedProviderIDs: ["anthropic", "openai"]
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

private func makeToolMessagePart(
    tool: String,
    status: ToolExecutionStatus = .completed,
    input: [String: JSONValue] = [:],
    metadata: [String: JSONValue]? = nil,
    output: String? = nil,
    error: String? = nil,
    title: String? = nil
) -> MessagePart {
    MessagePart(
        id: UUID().uuidString,
        sessionID: "session-1",
        messageID: "message-1",
        type: .tool,
        text: nil,
        synthetic: nil,
        ignored: nil,
        time: nil,
        metadata: nil,
        callID: nil,
        tool: tool,
        state: .init(
            status: status,
            input: input,
            raw: nil,
            output: output,
            title: title,
            metadata: metadata,
            error: error,
            time: nil,
            attachments: nil
        ),
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

private func waitForAsyncWork(milliseconds: UInt64 = 200) async throws {
    try await Task.sleep(for: .milliseconds(Int(milliseconds)))
}
