import Combine
import CoreData
import Foundation
import OSLog
import XCTest
@testable import Colonnade

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

final class PromptTextSynchronizationStateTests: XCTestCase {
    func testIgnoresStaleBindingUpdateWhileTyping() {
        var state = PromptTextSynchronizationState(text: "")

        state.noteLocalEdit("D")

        XCTAssertFalse(state.shouldApplyExternalText("", currentViewText: "D"))
    }

    func testAppliesIncomingTextAfterSynchronizationAdvances() {
        var state = PromptTextSynchronizationState(text: "")

        state.noteLocalEdit("D")
        state.noteSynchronizedText("D")

        XCTAssertTrue(state.shouldApplyExternalText("Debug", currentViewText: "D"))
    }

    func testAppliesDifferentExternalTextEvenWithPendingLocalEdit() {
        var state = PromptTextSynchronizationState(text: "")

        state.noteLocalEdit("D")

        XCTAssertTrue(state.shouldApplyExternalText("server", currentViewText: "D"))
    }
}

final class PaneFocusOutlineStateTests: XCTestCase {
    func testShowsFocusOutlineForSinglePaneWithoutResponderFocus() {
        XCTAssertTrue(
            PaneFocusOutlineState.showsFocusOutline(
                chrome: .pane,
                openSessionCount: 1,
                focusedSessionID: "session-1",
                sessionID: "session-1",
                paneHasFocus: false
            )
        )
    }

    func testShowsFocusOutlineForMultiPaneOnlyWhenPaneOwnsResponderFocus() {
        XCTAssertFalse(
            PaneFocusOutlineState.showsFocusOutline(
                chrome: .pane,
                openSessionCount: 2,
                focusedSessionID: "session-1",
                sessionID: "session-1",
                paneHasFocus: false
            )
        )

        XCTAssertTrue(
            PaneFocusOutlineState.showsFocusOutline(
                chrome: .pane,
                openSessionCount: 2,
                focusedSessionID: "session-1",
                sessionID: "session-1",
                paneHasFocus: true
            )
        )
    }

    func testDoesNotShowFocusOutlineForUnfocusedSessionEvenWhenPaneHasResponderFocus() {
        XCTAssertFalse(
            PaneFocusOutlineState.showsFocusOutline(
                chrome: .pane,
                openSessionCount: 2,
                focusedSessionID: "session-2",
                sessionID: "session-1",
                paneHasFocus: true
            )
        )
    }

    func testWindowChromeFollowsSelectedSessionWithoutPaneFocusRequirement() {
        XCTAssertTrue(
            PaneFocusOutlineState.showsFocusOutline(
                chrome: .window,
                openSessionCount: 2,
                focusedSessionID: "session-1",
                sessionID: "session-1",
                paneHasFocus: false
            )
        )
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

    func testLatestReasoningTitlePrefersStructuredMetadata() {
        let message = MessageEnvelope(
            info: MessageInfo(
                id: "message-1",
                sessionID: "session-1",
                role: .assistant,
                time: .init(created: 1_234, completed: nil),
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
            parts: [
                MessagePart(
                    id: "reasoning-1",
                    sessionID: "session-1",
                    messageID: "message-1",
                    type: .reasoning,
                    text: "Longer body that should not be used as the title.",
                    synthetic: nil,
                    ignored: nil,
                    time: nil,
                    metadata: ["title": .string("Inspecting prompt UI")],
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

        XCTAssertEqual(message.latestReasoningTitle, "Inspecting prompt UI")
    }

    func testLatestReasoningTitleFallsBackToFirstShortLine() {
        let message = MessageEnvelope(
            info: MessageInfo(
                id: "message-1",
                sessionID: "session-1",
                role: .assistant,
                time: .init(created: 1_234, completed: nil),
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
            parts: [
                MessagePart(
                    id: "reasoning-1",
                    sessionID: "session-1",
                    messageID: "message-1",
                    type: .reasoning,
                    text: "# Inspecting thinking blocks\n\nWorking through the longer explanation.",
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

        XCTAssertEqual(message.latestReasoningTitle, "Inspecting thinking blocks")
    }
}

final class ThemeControllerTests: XCTestCase {
    @MainActor
    func testThemeControllerDefaultsToNative() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let controller = ThemeController(defaults: defaults, supportsTheme: { _ in true })

        XCTAssertEqual(controller.selectedThemeID, .native)
        XCTAssertEqual(controller.selectedTheme.id, .native)
    }

    @MainActor
    func testThemeControllerRestoresAndPersistsSelection() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(OpenCodeThemeID.githubDark.rawValue, forKey: ThemeController.Constants.selectedThemeKey)

        let controller = ThemeController(defaults: defaults, supportsTheme: { _ in true })
        XCTAssertEqual(controller.selectedThemeID, .githubDark)

        controller.selectTheme(.nord)

        XCTAssertEqual(controller.selectedThemeID, .nord)
        XCTAssertEqual(defaults.string(forKey: ThemeController.Constants.selectedThemeKey), OpenCodeThemeID.nord.rawValue)
    }

    @MainActor
    func testThemeControllerFallsBackWhenStoredThemeIsUnsupported() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(OpenCodeThemeID.githubDark.rawValue, forKey: ThemeController.Constants.selectedThemeKey)

        let controller = ThemeController(defaults: defaults, supportsTheme: { $0 == .native })

        XCTAssertEqual(controller.selectedThemeID, .native)
    }

    @MainActor
    func testThemeControllerIgnoresUnsupportedSelection() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let controller = ThemeController(defaults: defaults, supportsTheme: { $0 == .native })
        controller.selectTheme(.githubDark)

        XCTAssertEqual(controller.selectedThemeID, .native)
        XCTAssertNil(defaults.string(forKey: ThemeController.Constants.selectedThemeKey))
    }
}

final class LocalServerPreferencesControllerTests: XCTestCase {
    @MainActor
    func testLocalServerPreferencesDefaultsToBunInstallPath() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let controller = LocalServerPreferencesController(defaults: defaults)

        XCTAssertEqual(controller.opencodeExecutablePath, "~/.bun/bin/opencode")
        XCTAssertNil(defaults.string(forKey: LocalServerPreferencesController.Constants.opencodeExecutablePathKey))
    }

    @MainActor
    func testLocalServerPreferencesPersistsCustomPath() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let controller = LocalServerPreferencesController(defaults: defaults)
        controller.setOpencodeExecutablePath("/opt/homebrew/bin/opencode")

        XCTAssertEqual(controller.opencodeExecutablePath, "/opt/homebrew/bin/opencode")
        XCTAssertEqual(defaults.string(forKey: LocalServerPreferencesController.Constants.opencodeExecutablePathKey), "/opt/homebrew/bin/opencode")
    }

    @MainActor
    func testLocalServerPreferencesResetBlankPathToDefault() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("/tmp/opencode", forKey: LocalServerPreferencesController.Constants.opencodeExecutablePathKey)

        let controller = LocalServerPreferencesController(defaults: defaults)
        controller.setOpencodeExecutablePath("   ")

        XCTAssertEqual(controller.opencodeExecutablePath, "~/.bun/bin/opencode")
        XCTAssertNil(defaults.string(forKey: LocalServerPreferencesController.Constants.opencodeExecutablePathKey))
    }
}

final class ThinkingVisibilityPreferencesTests: XCTestCase {
    func testShowsThinkingDefaultsToTrue() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        XCTAssertTrue(ThinkingVisibilityPreferences.showsThinking(from: defaults))
    }

    func testShowsThinkingPersistsFalse() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        ThinkingVisibilityPreferences.setShowsThinking(false, defaults: defaults)

        XCTAssertFalse(ThinkingVisibilityPreferences.showsThinking(from: defaults))
    }
}

final class SessionTranscriptSupportTests: XCTestCase {
    func testThinkingBannerTitleReturnsLatestReasoningWhenThinkingHiddenAndSessionBusy() {
        let title = SessionTranscriptSupport.thinkingBannerTitle(
            session: makeSessionDisplay(id: "session-1", status: .busy),
            latestReasoningTitle: "Inspecting transcript updates",
            questions: [],
            permissions: [],
            showsThinking: false
        )

        XCTAssertEqual(title, "Inspecting transcript updates")
    }

    func testThinkingBannerTitleReturnsNilWhenThinkingIsVisible() {
        let title = SessionTranscriptSupport.thinkingBannerTitle(
            session: makeSessionDisplay(id: "session-1", status: .busy),
            latestReasoningTitle: "Inspecting transcript updates",
            questions: [],
            permissions: [],
            showsThinking: true
        )

        XCTAssertNil(title)
    }

    func testThinkingBannerTitleReturnsNilWhenQuestionIsPending() {
        let title = SessionTranscriptSupport.thinkingBannerTitle(
            session: makeSessionDisplay(id: "session-1", status: .busy),
            latestReasoningTitle: "Inspecting transcript updates",
            questions: [makeQuestion(id: "question-1", sessionID: "session-1")],
            permissions: [],
            showsThinking: false
        )

        XCTAssertNil(title)
    }

    func testThinkingBannerTitleReturnsNilWhenPermissionIsPending() {
        let title = SessionTranscriptSupport.thinkingBannerTitle(
            session: makeSessionDisplay(id: "session-1", status: .busy),
            latestReasoningTitle: "Inspecting transcript updates",
            questions: [],
            permissions: [makePermission(id: "permission-1", sessionID: "session-1")],
            showsThinking: false
        )

        XCTAssertNil(title)
    }

    func testThinkingBannerTitleReturnsNilWhenSessionIsNotThinking() {
        let title = SessionTranscriptSupport.thinkingBannerTitle(
            session: makeSessionDisplay(id: "session-1", status: .idle),
            latestReasoningTitle: "Inspecting transcript updates",
            questions: [],
            permissions: [],
            showsThinking: false
        )

        XCTAssertNil(title)
    }
}

final class LocalServerLifecycleTests: XCTestCase {
    func testShutdownAllStopsRegisteredProcesses() throws {
        let logger = Logger(subsystem: "ai.opencode.app", category: "test")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 30"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let source = DispatchSource.makeReadSource(fileDescriptor: pipe.fileHandleForReading.fileDescriptor, queue: .global())
        source.setEventHandler {
            _ = pipe.fileHandleForReading.availableData
        }
        source.setCancelHandler {
            try? pipe.fileHandleForReading.close()
        }
        source.resume()

        try process.run()

        let storage = LocalServerProcessStorage(process: process, outputSource: source, logger: logger, onShutdown: nil)
        LocalServerLifecycle.shared.register(storage)
        LocalServerLauncher.shutdownAll()

        let expectation = XCTestExpectation(description: "process exits")
        DispatchQueue.global().async {
            process.waitUntilExit()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
        XCTAssertFalse(process.isRunning)
    }
}

final class SessionStatusTests: XCTestCase {
    func testBusyStatesAreThinkingActive() {
        XCTAssertTrue(SessionStatus.busy.isThinkingActive)
        XCTAssertTrue(SessionStatus.retry(attempt: 1, message: "Retrying", next: 0).isThinkingActive)
        XCTAssertFalse(SessionStatus.idle.isThinkingActive)
        XCTAssertFalse(SessionStatus.unknown("paused").isThinkingActive)
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
        XCTAssertEqual(summary.iconSystemName, "terminal")
        XCTAssertEqual(presentation.detailFields, [ToolDetailField(title: "Command", value: "git status --short")])
        XCTAssertEqual(presentation.statusLabel, "Running")
        XCTAssertNil(presentation.fallbackDetail)
    }

    func testSearchPresentationUsesMagnifyingGlassIcon() {
        let part = makeToolMessagePart(
            tool: "functions.grep",
            input: [
                "pattern": .string("todo")
            ]
        )

        let presentation = part.toolPresentation

        guard case let .standard(summary) = presentation.summaryStyle else {
            return XCTFail("Expected standard summary style")
        }

        XCTAssertEqual(summary.action, "Search")
        XCTAssertEqual(summary.target, "todo")
        XCTAssertEqual(summary.iconSystemName, "magnifyingglass")
    }

    func testWritePresentationUsesGenericIcon() {
        let part = makeToolMessagePart(
            tool: "functions.write",
            input: [
                "filePath": .string("/tmp/Notes.swift")
            ]
        )

        let presentation = part.toolPresentation

        guard case let .standard(summary) = presentation.summaryStyle else {
            return XCTFail("Expected standard summary style")
        }

        XCTAssertEqual(summary.action, "Write")
        XCTAssertEqual(summary.target, "Notes.swift")
        XCTAssertEqual(summary.iconSystemName, ToolCallSummary.genericIconSystemName)
    }

    func testTodoPresentationUsesPinIcon() {
        let part = makeToolMessagePart(tool: "functions.todowrite")

        let presentation = part.toolPresentation

        guard case let .standard(summary) = presentation.summaryStyle else {
            return XCTFail("Expected standard summary style")
        }

        XCTAssertEqual(summary.action, "Todo")
        XCTAssertNil(summary.target)
        XCTAssertEqual(summary.iconSystemName, "pin")
    }

    func testTodoPresentationUsesChecklistDrawer() {
        let part = makeToolMessagePart(
            tool: "functions.todowrite",
            input: [
                "todos": .array([
                    .object([
                        "content": .string("Ship the thing"),
                        "status": .string("completed")
                    ]),
                    .object([
                        "content": .string("Verify the thing"),
                        "status": .string("in_progress")
                    ]),
                    .object([
                        "content": .string("Document the thing"),
                        "status": .string("pending")
                    ])
                ])
            ],
            output: "raw todo json"
        )

        let presentation = part.toolPresentation

        guard case let .todo(detail) = presentation.drawerStyle else {
            return XCTFail("Expected todo drawer style")
        }

        XCTAssertEqual(
            detail.items,
            [
                ToolTodoItem(id: 0, content: "Ship the thing", status: .completed),
                ToolTodoItem(id: 1, content: "Verify the thing", status: .inProgress),
                ToolTodoItem(id: 2, content: "Document the thing", status: .pending)
            ]
        )
        XCTAssertTrue(presentation.drawerStyle.hidesRawOutput)
    }

    func testTaskPresentationUsesSubagentSummaryStyle() {
        let part = makeToolMessagePart(
            tool: "functions.task",
            input: [
                "description": .string("Inspect repo"),
                "subagent_type": .string("explore"),
                "task_id": .string("task-1")
            ]
        )

        let presentation = part.toolPresentation

        guard case let .task(summary) = presentation.summaryStyle else {
            return XCTFail("Expected task summary style")
        }

        XCTAssertEqual(summary.title, "Subagent")
        XCTAssertEqual(summary.target, "Inspect repo")
        XCTAssertEqual(
            presentation.detailFields,
            [
                ToolDetailField(title: "Type", value: "explore"),
                ToolDetailField(title: "Task ID", value: "task-1")
            ]
        )
    }

    func testSubagentInvocationPrefersAttachmentSessionID() {
        let part = makeToolMessagePart(
            tool: "functions.task",
            input: [
                "task_id": .string("task-1"),
                "subagent_type": .string("explore")
            ],
            attachments: [
                .init(
                    id: "attachment-1",
                    sessionID: "session-subagent",
                    messageID: "message-1",
                    type: nil,
                    mime: nil,
                    filename: nil,
                    url: nil
                )
            ]
        )

        XCTAssertEqual(
            part.subagentInvocation,
            MessagePart.SubagentInvocation(taskID: "task-1", sessionID: "session-subagent", subagentType: "explore")
        )
    }

    func testResolveSubagentSessionPrefersExplicitSessionID() {
        let target = SessionDisplay(
            id: "session-subagent",
            title: "Subagent",
            createdAtMS: 1_050,
            updatedAtMS: 1_400,
            hydratedMessageUpdatedAtMS: nil,
            parentID: "parent-1",
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )
        let sibling = SessionDisplay(
            id: "session-sibling",
            title: "Sibling",
            createdAtMS: 1_060,
            updatedAtMS: 1_500,
            hydratedMessageUpdatedAtMS: nil,
            parentID: "parent-1",
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )

        let resolved = MessagePart.resolveSubagentSession(
            for: .init(taskID: "task-1", sessionID: "session-subagent", subagentType: "explore"),
            in: [sibling, target],
            parentSessionID: "parent-1",
            referenceTimeMS: 1_055
        )

        XCTAssertEqual(resolved?.id, target.id)
    }

    func testResolveSubagentSessionFallsBackToClosestChildByCreationTime() {
        let early = SessionDisplay(
            id: "session-early",
            title: "Early",
            createdAtMS: 1_010,
            updatedAtMS: 1_200,
            hydratedMessageUpdatedAtMS: nil,
            parentID: "parent-1",
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )
        let closest = SessionDisplay(
            id: "session-closest",
            title: "Closest",
            createdAtMS: 1_090,
            updatedAtMS: 1_300,
            hydratedMessageUpdatedAtMS: nil,
            parentID: "parent-1",
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )

        let resolved = MessagePart.resolveSubagentSession(
            for: .init(taskID: "task-1", sessionID: nil, subagentType: "explore"),
            in: [early, closest],
            parentSessionID: "parent-1",
            referenceTimeMS: 1_100
        )

        XCTAssertEqual(resolved?.id, closest.id)
    }

    func testResolveSubagentSessionsAssignsDistinctConcurrentChildren() {
        let firstPart = makeToolMessagePart(
            tool: "functions.task",
            input: [
                "description": .string("First"),
                "task_id": .string("task-1")
            ]
        )
        let secondPart = makeToolMessagePart(
            tool: "functions.task",
            input: [
                "description": .string("Second"),
                "task_id": .string("task-2")
            ]
        )

        let firstChild = SessionDisplay(
            id: "session-first",
            title: "First child",
            createdAtMS: 1_005,
            updatedAtMS: 1_100,
            hydratedMessageUpdatedAtMS: nil,
            parentID: "parent-1",
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )
        let secondChild = SessionDisplay(
            id: "session-second",
            title: "Second child",
            createdAtMS: 1_015,
            updatedAtMS: 1_200,
            hydratedMessageUpdatedAtMS: nil,
            parentID: "parent-1",
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )

        let resolutions = MessagePart.resolveSubagentSessions(
            for: [firstPart, secondPart],
            in: [firstChild, secondChild],
            parentSessionID: "parent-1",
            baseReferenceTimeMS: 1_010
        )

        XCTAssertEqual(resolutions[firstPart.id]?.id, firstChild.id)
        XCTAssertEqual(resolutions[secondPart.id]?.id, secondChild.id)
    }

    func testResolveSubagentSessionsStillHonorsExplicitSessionIDs() {
        let firstPart = makeToolMessagePart(
            tool: "functions.task",
            input: [
                "task_id": .string("task-1"),
                "sessionID": .string("session-second")
            ]
        )
        let secondPart = makeToolMessagePart(
            tool: "functions.task",
            input: [
                "task_id": .string("task-2")
            ]
        )

        let firstChild = SessionDisplay(
            id: "session-first",
            title: "First child",
            createdAtMS: 1_005,
            updatedAtMS: 1_100,
            hydratedMessageUpdatedAtMS: nil,
            parentID: "parent-1",
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )
        let secondChild = SessionDisplay(
            id: "session-second",
            title: "Second child",
            createdAtMS: 1_015,
            updatedAtMS: 1_200,
            hydratedMessageUpdatedAtMS: nil,
            parentID: "parent-1",
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )

        let resolutions = MessagePart.resolveSubagentSessions(
            for: [firstPart, secondPart],
            in: [firstChild, secondChild],
            parentSessionID: "parent-1",
            baseReferenceTimeMS: 1_010
        )

        XCTAssertEqual(resolutions[firstPart.id]?.id, secondChild.id)
        XCTAssertEqual(resolutions[secondPart.id]?.id, firstChild.id)
    }

    func testWebFetchPresentationUsesGlobeIcon() {
        let part = makeToolMessagePart(
            tool: "functions.webfetch",
            input: [
                "url": .string("https://example.com")
            ]
        )

        let presentation = part.toolPresentation

        guard case let .standard(summary) = presentation.summaryStyle else {
            return XCTFail("Expected standard summary style")
        }

        XCTAssertEqual(summary.action, "Fetch")
        XCTAssertEqual(summary.target, "https://example.com")
        XCTAssertEqual(summary.iconSystemName, "globe")
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
        XCTAssertEqual(summary.iconSystemName, ToolCallSummary.genericIconSystemName)
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

    func testStopSessionUsesInjectedClient() async throws {
        let client = MockOpenCodeAPIClient()

        try await WorkspaceService(client: client).stopSession(directory: "/tmp/project", sessionID: "session-1")

        XCTAssertEqual(client.abortSessionCalls, [.init(directory: "/tmp/project", sessionID: "session-1")])
    }

    func testRenameSessionUsesInjectedClient() async throws {
        let renamedSession = makeSession(id: "session-1")
        let client = MockOpenCodeAPIClient(renamedSessionResult: renamedSession)

        let session = try await WorkspaceService(client: client).renameSession(directory: "/tmp/project", sessionID: "session-1", title: "Renamed")

        XCTAssertEqual(client.renameSessionCalls, [.init(directory: "/tmp/project", sessionID: "session-1", title: "Renamed")])
        XCTAssertEqual(session, renamedSession)
    }

    func testLoadCommandCatalogReturnsValuesFromInjectedClient() async throws {
        let client = MockOpenCodeAPIClient(commands: .init(commands: [
            .init(name: "happycog/release", description: "Release branch helper", agent: nil, model: nil, template: "tmpl", subtask: nil)
        ]))

        let catalog = try await WorkspaceService(client: client).loadCommandCatalog()

        XCTAssertEqual(catalog.commands.map(\.name), ["happycog/release"])
    }

    func testCommandModelIdentifierUsesProviderSlashModelKey() {
        let model = ModelReference(providerID: "github-copilot", modelID: "gpt-5.4")

        XCTAssertEqual(OpenCodeAPIClient.commandModelIdentifier(model), "github-copilot/gpt-5.4")
        XCTAssertNil(OpenCodeAPIClient.commandModelIdentifier(nil))
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
        appState.sendMessage(sessionID: session.id, text: "Ship it")
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(workspaceService.sendMessageCalls.count, 1)
        XCTAssertEqual(workspaceService.sendMessageCalls.first?.directory, directory)
        XCTAssertEqual(workspaceService.sendMessageCalls.first?.sessionID, session.id)
        XCTAssertEqual(workspaceService.sendMessageCalls.first?.text, "Ship it")
        XCTAssertEqual(workspaceService.sendMessageCalls.first?.model, ModelReference(providerID: "anthropic", modelID: "claude-sonnet"))
        let refreshedMessages = await coordinator.refreshedMessageSessionIDsSnapshot()
        XCTAssertEqual(refreshedMessages.suffix(1), [session.id])
    }

    func testStopSessionUsesInjectedServiceAndRefreshesCoordinator() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [session.id: .busy], questions: [], permissions: [])
        )
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
        appState.stopSession(session.id)
        try await waitForAsyncWork()

        XCTAssertEqual(workspaceService.stopSessionCalls, [.init(directory: directory, sessionID: session.id)])
        let refreshedStatuses = await coordinator.refreshedStatusSessionIDsSnapshot()
        XCTAssertEqual(refreshedStatuses, [session.id])
        let refreshedMessages = await coordinator.refreshedMessageSessionIDsSnapshot()
        XCTAssertEqual(refreshedMessages.suffix(1), [session.id])
        let refreshedInteractions = await coordinator.refreshedInteractionsCountSnapshot()
        XCTAssertEqual(refreshedInteractions, 1)
    }

    func testRenameSessionUsesInjectedServiceAndUpdatesVisibleSessions() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let renamed = OpenCodeSession(
            id: session.id,
            slug: session.slug,
            projectID: session.projectID,
            workspaceID: session.workspaceID,
            directory: session.directory,
            parentID: session.parentID,
            title: "Renamed Session",
            version: session.version,
            summary: session.summary,
            time: .init(created: session.time.created, updated: session.time.updated + 1, compacting: session.time.compacting, archived: session.time.archived)
        )
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: []),
            renameSessionResult: renamed
        )

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)
        appState.renameSession(session.id, title: "  Renamed Session  ")
        try await waitForAsyncWork()

        XCTAssertEqual(workspaceService.renameSessionCalls, [.init(directory: directory, sessionID: session.id, title: "Renamed Session")])
        XCTAssertEqual(appState.visibleSessions.first?.title, "Renamed Session")
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

    func testCloseUnfocusedSessionPreservesFocusedPane() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]
        appState.focusedSessionID = "session-2"

        appState.closeSession("session-1")

        XCTAssertEqual(appState.openSessionIDs, ["session-2", "session-3"])
        XCTAssertEqual(appState.focusedSessionID, "session-2")
        XCTAssertNil(appState.promptFocusRequest)
    }

    func testMoveOpenSessionReordersPanesBeforeTarget() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]
        appState.focusedSessionID = "session-2"

        appState.moveOpenSession("session-3", before: "session-1")

        XCTAssertEqual(appState.openSessionIDs, ["session-3", "session-1", "session-2"])
        XCTAssertEqual(appState.focusedSessionID, "session-2")
    }

    func testMoveOpenSessionAppendsPaneWhenNoTargetProvided() {
        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]

        appState.moveOpenSession("session-1")

        XCTAssertEqual(appState.openSessionIDs, ["session-2", "session-3", "session-1"])
    }

    func testMoveOpenSessionPersistsUpdatedPaneOrder() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let appState = OpenCodeAppModel(repository: repository, persistsWorkspacePaneState: true)
        appState.selectedDirectory = directory
        appState.openSessionIDs = ["session-1", "session-2", "session-3"]

        appState.moveOpenSession("session-3", before: "session-2")
        try await waitForAsyncWork()

        let snapshot = await repository.loadSnapshot(directory: directory)
        let panes = snapshot.paneStates.values.sorted { $0.position < $1.position }
        XCTAssertEqual(panes.map(\.sessionID), ["session-1", "session-3", "session-2"])
    }

    func testWorkspaceCommandCenterTracksPaneFocusAfterBinding() async throws {
        let commandCenter = WorkspaceCommandCenter.shared
        commandCenter.resetForTesting()
        defer { commandCenter.resetForTesting() }

        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)

        commandCenter.bind(appState: appState)
        XCTAssertFalse(commandCenter.canFocusPreviousPane)
        XCTAssertFalse(commandCenter.canFocusNextPane)

        appState.openSessionIDs = ["session-1", "session-2"]
        appState.focusedSessionID = "session-1"
        commandCenter.updateAvailability(
            selectedDirectory: appState.selectedDirectory,
            focusedSessionID: appState.focusedSessionID,
            openSessionIDs: appState.openSessionIDs
        )

        XCTAssertTrue(commandCenter.canFocusPreviousPane)
        XCTAssertTrue(commandCenter.canFocusNextPane)

        appState.focusedSessionID = nil
        commandCenter.updateAvailability(
            selectedDirectory: appState.selectedDirectory,
            focusedSessionID: appState.focusedSessionID,
            openSessionIDs: appState.openSessionIDs
        )

        XCTAssertFalse(commandCenter.canFocusPreviousPane)
        XCTAssertFalse(commandCenter.canFocusNextPane)
    }

    func testWorkspaceCommandCenterEnablesPaneCommandsAtEdgesWhenPaneIsFocused() {
        let commandCenter = WorkspaceCommandCenter.shared
        commandCenter.resetForTesting()
        defer { commandCenter.resetForTesting() }

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
        commandCenter.resetForTesting()
        defer { commandCenter.resetForTesting() }

        commandCenter.updateAvailability(
            selectedDirectory: "/tmp/project",
            focusedSessionID: "session-1",
            openSessionIDs: ["session-1"]
        )

        XCTAssertTrue(commandCenter.canCloseFocusedSession)
    }

    func testWorkspaceCommandCenterDisablesCloseSessionWithoutFocusedWorkspacePane() {
        let commandCenter = WorkspaceCommandCenter.shared
        commandCenter.resetForTesting()
        defer { commandCenter.resetForTesting() }

        commandCenter.updateAvailability(
            selectedDirectory: "/tmp/project",
            focusedSessionID: nil,
            openSessionIDs: ["session-1"]
        )

        XCTAssertFalse(commandCenter.canCloseFocusedSession)
    }

    func testWorkspaceCommandCenterCreatesSessionInForegroundWorkspaceWindow() async throws {
        let commandCenter = WorkspaceCommandCenter.shared
        commandCenter.resetForTesting()
        defer { commandCenter.resetForTesting() }

        let firstDirectory = "/tmp/project-a"
        let secondDirectory = "/tmp/project-b"
        let firstService = MockWorkspaceService(createSessionResult: makeSession(id: "ses-created-a", directory: firstDirectory))
        let secondService = MockWorkspaceService(createSessionResult: makeSession(id: "ses-created-b", directory: secondDirectory))

        let firstAppState = OpenCodeAppModel(
            workspaceService: firstService,
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            initialDirectory: firstDirectory
        )
        firstAppState.selectedDirectory = firstDirectory

        let secondAppState = OpenCodeAppModel(
            workspaceService: secondService,
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            initialDirectory: secondDirectory
        )
        secondAppState.selectedDirectory = secondDirectory

        commandCenter.bind(appState: firstAppState)
        commandCenter.bind(appState: secondAppState)
        commandCenter.registerWorkspaceWindowNumber(11, appState: firstAppState)
        commandCenter.registerWorkspaceWindowNumber(22, appState: secondAppState)
        commandCenter.currentWindowNumberProvider = { 22 }

        commandCenter.createSession()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(firstService.createSessionCalls, [])
        XCTAssertEqual(secondService.createSessionCalls, [.init(directory: secondDirectory, title: nil, parentID: nil)])
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

    func testLoadUsesPersistedSessionsImmediatelyAndRefreshesInBackground() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let cachedSession = makeSession(id: "session-cached", directory: directory, updatedAt: 1_000)
        let freshSession = makeSession(id: "session-fresh", directory: directory, updatedAt: 3_000)

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(sessions: [cachedSession], statuses: [:], questions: [], permissions: []),
            modelContextLimits: [:],
            openSessionIDs: [cachedSession.id]
        )
        await repository.savePanes(
            directory: directory,
            panes: [
                SessionPaneState(sessionID: cachedSession.id, position: 0, width: 640, isHidden: false)
            ]
        )

        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [freshSession, cachedSession], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.loadWorkspaceDelay = .milliseconds(300)
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: true
        )

        let clock = ContinuousClock()
        let start = clock.now
        await appState.load(directory: directory)
        let elapsed = start.duration(to: clock.now)

        XCTAssertLessThan(durationMilliseconds(elapsed), 250)
        XCTAssertFalse(appState.isLoading)
        XCTAssertEqual(appState.sessions.map(\.id), [cachedSession.id])
        XCTAssertEqual(appState.openSessionIDs, [cachedSession.id])
        XCTAssertEqual(appState.focusedSessionID, cachedSession.id)

        try await waitForAsyncWork(milliseconds: 450)

        XCTAssertEqual(appState.sessions.map(\.id), [freshSession.id, cachedSession.id])
        let refreshedMessages = await coordinator.refreshedMessageSessionIDsSnapshot()
        XCTAssertEqual(refreshedMessages, [cachedSession.id])
    }

    func testForegroundResyncRefreshesOpenSessionsAfterBackgroundingOnIOS() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let session = makeSession(id: "session-1", directory: directory, updatedAt: 1_000)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: []),
            todosResult: [session.id: [SessionTodo(content: "todo", status: .pending, priority: .high)]]
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
        appState.openSessionIDs = [session.id]

        appState.noteAppDidEnterBackground()
        appState.noteAppDidBecomeActive()
        try await waitForAsyncWork()

        let updatedOpenSessions = await coordinator.updatedOpenSessionIDsSnapshot()
        XCTAssertEqual(updatedOpenSessions.last, [session.id])

        let refreshedTodos = await coordinator.refreshedTodosSessionIDsSnapshot()
        XCTAssertEqual(refreshedTodos.suffix(1), [session.id])

        let refreshedMessages = await coordinator.refreshedMessageSessionIDsSnapshot()
        XCTAssertEqual(refreshedMessages.suffix(1), [session.id])
    }

    func testForegroundResyncDoesNothingWithoutBackgroundTransition() async throws {
        let directory = try makeTemporaryDirectory()
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let session = makeSession(id: "session-1", directory: directory, updatedAt: 1_000)
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
        appState.openSessionIDs = [session.id]

        let baselineOpenSessionUpdates = await coordinator.updatedOpenSessionIDsSnapshot().count
        let baselineTodoRefreshes = await coordinator.refreshedTodosSessionIDsSnapshot().count
        let baselineMessageRefreshes = await coordinator.refreshedMessageSessionIDsSnapshot().count

        appState.noteAppDidBecomeActive()
        try await waitForAsyncWork()

        let updatedOpenSessions = await coordinator.updatedOpenSessionIDsSnapshot()
        XCTAssertEqual(updatedOpenSessions.count, baselineOpenSessionUpdates)

        let refreshedTodos = await coordinator.refreshedTodosSessionIDsSnapshot()
        XCTAssertEqual(refreshedTodos.count, baselineTodoRefreshes)

        let refreshedMessages = await coordinator.refreshedMessageSessionIDsSnapshot()
        XCTAssertEqual(refreshedMessages.count, baselineMessageRefreshes)
    }

    func testLoadWithCachedDataSurfacesBackgroundRefreshErrorsWithoutDroppingCache() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let cachedSession = makeSession(id: "session-cached", directory: directory, updatedAt: 1_000)

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(sessions: [cachedSession], statuses: [:], questions: [], permissions: []),
            modelContextLimits: [:],
            openSessionIDs: [cachedSession.id]
        )

        let workspaceService = MockWorkspaceService()
        workspaceService.loadWorkspaceDelay = .milliseconds(200)
        workspaceService.loadWorkspaceError = URLError(.cannotConnectToHost)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)

        XCTAssertFalse(appState.isLoading)
        XCTAssertEqual(appState.sessions.map(\.id), [cachedSession.id])
        XCTAssertNil(appState.errorMessage)

        try await waitForAsyncWork(milliseconds: 350)

        XCTAssertEqual(appState.sessions.map(\.id), [cachedSession.id])
        XCTAssertNotNil(appState.errorMessage)
    }

    func testBootstrapRestoresLastSelectedDirectoryIntoBackgroundLoad() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let cachedSession = makeSession(id: "session-cached", directory: directory, updatedAt: 1_000)

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(sessions: [cachedSession], statuses: [:], questions: [], permissions: []),
            modelContextLimits: [:],
            openSessionIDs: [cachedSession.id]
        )
        await repository.savePanes(
            directory: directory,
            panes: [
                SessionPaneState(sessionID: cachedSession.id, position: 0, width: 640, isHidden: false)
            ]
        )
        await repository.selectWorkspace(directory: directory)

        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [cachedSession], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.loadWorkspaceDelay = .milliseconds(250)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: true,
            restoresLastSelectedDirectory: true
        )

        await appState.bootstrapIfNeeded()

        try await waitForAsyncWork(milliseconds: 100)

        XCTAssertEqual(appState.selectedDirectory, directory)
        XCTAssertEqual(appState.openSessionIDs, [cachedSession.id])
        XCTAssertEqual(appState.focusedSessionID, cachedSession.id)
        XCTAssertFalse(appState.isLoading)

        try await waitForAsyncWork(milliseconds: 350)

        XCTAssertEqual(appState.sessions.map(\.id), [cachedSession.id])
        XCTAssertEqual(workspaceService.loadWorkspaceDirectories, [directory])
    }

    func testBootstrapUsesConfiguredRestoredConnectionBeforePersistenceFallback() async throws {
        let directory = "/remote/project"
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let cachedSession = makeSession(id: "session-remote", directory: directory, updatedAt: 1_000)

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: WorkspaceSnapshot(sessions: [cachedSession], statuses: [:], questions: [], permissions: []),
            modelContextLimits: [:],
            openSessionIDs: [cachedSession.id]
        )

        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [cachedSession], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.loadWorkspaceDelay = .milliseconds(250)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: true,
            restoresLastSelectedDirectory: false,
            initialServerURL: URL(string: "https://example.com")!
        )
        appState.configureBootstrapRestoredConnection(
            WorkspaceConnection(serverURL: URL(string: "https://example.com")!, directory: directory)
        )

        await appState.bootstrapIfNeeded()

        try await waitForAsyncWork(milliseconds: 100)

        XCTAssertEqual(appState.serverURL.absoluteString, "https://example.com")
        XCTAssertEqual(appState.selectedDirectory, directory)
        XCTAssertEqual(appState.openSessionIDs, [cachedSession.id])
        XCTAssertEqual(appState.focusedSessionID, cachedSession.id)
        XCTAssertFalse(appState.isLoading)

        try await waitForAsyncWork(milliseconds: 350)

        XCTAssertEqual(appState.sessions.map(\.id), [cachedSession.id])
        XCTAssertEqual(workspaceService.loadWorkspaceDirectories, [directory])
    }

    func testBootstrapIgnoresMissingConfiguredLocalRestorationAndShowsChooser() async throws {
        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            restoresLastSelectedDirectory: false
        )
        appState.configureBootstrapRestoredConnection(
            WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/definitely/missing/directory")
        )

        await appState.bootstrapIfNeeded()

        XCTAssertNil(appState.selectedDirectory)
        XCTAssertEqual(appState.launchStage, .chooseServerMode)
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

    func testConnectToRemoteServerStoresRecentConnections() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let client = MockOpenCodeAPIClient(health: .init(healthy: true, version: "1.0.0"), projects: [])

        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            apiClientProviderOverride: { _ in client },
            recentRemoteConnectionsDefaults: defaults
        )
        appState.remoteServerURLText = "example.com"

        appState.connectToRemoteServer()
        try await waitForAsyncWork()

        XCTAssertEqual(appState.recentRemoteConnections, ["https://example.com"])
        XCTAssertEqual(RecentRemoteConnectionsPreferences.load(from: defaults), ["https://example.com"])
    }

    func testConnectToRemoteServerLoadsServerSpecificRecentProjects() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        RecentProjectDirectoriesPreferences.remember("/projects/a", for: URL(string: "https://example.com")!, defaults: defaults)
        RecentProjectDirectoriesPreferences.remember("/projects/b", for: URL(string: "https://other.example.com")!, defaults: defaults)
        let client = MockOpenCodeAPIClient(health: .init(healthy: true, version: "1.0.0"), projects: [])

        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            apiClientProviderOverride: { _ in client },
            recentProjectDirectoriesDefaults: defaults
        )
        appState.remoteServerURLText = "example.com"

        appState.connectToRemoteServer()
        try await waitForAsyncWork()

        XCTAssertEqual(appState.recentProjectDirectories, ["/projects/a"])
    }

    func testResetServerSelectionReturnsIOSAppToProjectPicker() async throws {
        let directory = "/remote/project"
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(
                sessions: [makeSession(id: "session-1", directory: directory)],
                statuses: [:],
                questions: [],
                permissions: []
            )
        )

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            supportsLocalServer: false,
            initialServerURL: URL(string: "https://example.com")!
        )

        await appState.load(directory: directory)
        appState.remoteProjectSuggestions = ["/remote/other"]
        appState.remoteDirectoryText = directory

        appState.resetServerSelection()

        XCTAssertNil(appState.selectedDirectory)
        XCTAssertEqual(appState.openSessionIDs, [])
        XCTAssertNil(appState.focusedSessionID)
        XCTAssertNil(appState.liveStore)
        XCTAssertEqual(appState.launchStage, .remoteServerEntry)
        XCTAssertEqual(appState.serverURL, OpenCodeAppModel.defaultServerURL)
        XCTAssertEqual(appState.remoteProjectSuggestions, [])
        XCTAssertEqual(appState.remoteDirectoryText, "")
    }

    func testReturnToProjectChooserKeepsCurrentServerAndDirectoryDraft() async throws {
        let directory = "/remote/project"
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(
                sessions: [makeSession(id: "session-1", directory: directory)],
                statuses: [:],
                questions: [],
                permissions: []
            )
        )
        let serverURL = URL(string: "https://example.com")!

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            supportsLocalServer: false,
            initialServerURL: serverURL
        )

        await appState.load(directory: directory)
        appState.launchStage = .remoteDirectoryEntry

        appState.returnToProjectChooser()

        XCTAssertNil(appState.selectedDirectory)
        XCTAssertEqual(appState.serverURL, serverURL)
        XCTAssertEqual(appState.launchStage, .remoteDirectoryEntry)
        XCTAssertEqual(appState.remoteDirectoryText, directory)
    }

    func testRecentRemoteConnectionsKeepMostRecentFiveUniqueValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let entries = [
            "https://one.example.com",
            "https://two.example.com",
            "https://three.example.com",
            "https://four.example.com",
            "https://five.example.com",
            "https://six.example.com",
            "https://three.example.com"
        ]

        for entry in entries {
            RecentRemoteConnectionsPreferences.remember(entry, defaults: defaults)
        }

        XCTAssertEqual(
            RecentRemoteConnectionsPreferences.load(from: defaults),
            [
                "https://three.example.com",
                "https://six.example.com",
                "https://five.example.com",
                "https://four.example.com",
                "https://two.example.com"
            ]
        )
    }

    func testRecentProjectDirectoriesAreStoredPerServer() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let primaryServer = URL(string: "https://one.example.com")!
        let secondaryServer = URL(string: "https://two.example.com")!

        RecentProjectDirectoriesPreferences.remember("/projects/one-a", for: primaryServer, defaults: defaults)
        RecentProjectDirectoriesPreferences.remember("/projects/two-a", for: secondaryServer, defaults: defaults)
        RecentProjectDirectoriesPreferences.remember("/projects/one-b", for: primaryServer, defaults: defaults)

        XCTAssertEqual(
            RecentProjectDirectoriesPreferences.load(for: primaryServer, from: defaults),
            ["/projects/one-b", "/projects/one-a"]
        )
        XCTAssertEqual(
            RecentProjectDirectoriesPreferences.load(for: secondaryServer, from: defaults),
            ["/projects/two-a"]
        )
    }

    func testRecentProjectDirectoriesKeepMostRecentFiveUniqueValuesPerServer() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let serverURL = URL(string: "https://example.com")!

        let entries = [
            "/projects/one",
            "/projects/two",
            "/projects/three",
            "/projects/four",
            "/projects/five",
            "/projects/six",
            "/projects/three"
        ]

        for entry in entries {
            RecentProjectDirectoriesPreferences.remember(entry, for: serverURL, defaults: defaults)
        }

        XCTAssertEqual(
            RecentProjectDirectoriesPreferences.load(for: serverURL, from: defaults),
            [
                "/projects/three",
                "/projects/six",
                "/projects/five",
                "/projects/four",
                "/projects/two"
            ]
        )
    }

    func testLoadStoresRecentProjectDirectoryForServer() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let directory = "/remote/project"
        let serverURL = URL(string: "https://example.com")!
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(
                sessions: [makeSession(id: "session-1", directory: directory)],
                statuses: [:],
                questions: [],
                permissions: []
            )
        )

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            supportsLocalServer: false,
            initialServerURL: serverURL,
            recentProjectDirectoriesDefaults: defaults
        )

        await appState.load(directory: directory)

        XCTAssertEqual(appState.recentProjectDirectories, [directory])
        XCTAssertEqual(RecentProjectDirectoriesPreferences.load(for: serverURL, from: defaults), [directory])
    }

    func testRemoteDirectorySuggestionOptionsReturnBestMatches() {
        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false
        )
        appState.remoteDirectoryText = "/tmp/b"
        appState.remoteProjectSuggestions = ["/tmp/alpha", "/tmp/beta", "/var/project"]

        XCTAssertEqual(appState.remoteDirectorySuggestionOptions().map(\.name), ["/tmp/beta"])
    }

    func testOpenLocalDirectoryStartsServerAndUsesInjectedChooser() async throws {
        let client = MockOpenCodeAPIClient(health: .init(healthy: false, version: "1.0.0"))
        let probe = LocalServerProbe()

        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            localServerStarter: { _ in
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
                return .reached
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
            localServerStarter: { _ in
                Task {
                    await probe.recordStart()
                }
                return LocalServerLaunchHandle()
            },
            apiClientProviderOverride: { _ in client },
            serverWaiter: { url, timeout in
                await probe.recordWait(url: url, timeout: timeout)
                return .reached
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

    func testOpenLocalDirectoryTimeoutSurfacesLastHealthCheckFailure() async throws {
        let client = MockOpenCodeAPIClient(health: .init(healthy: false, version: "1.0.0"))

        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            localServerStarter: { _ in
                LocalServerLaunchHandle()
            },
            apiClientProviderOverride: { _ in client },
            serverWaiter: { _, _ in
                .timedOut(lastFailureDescription: "Health check at http://127.0.0.1:4096/global/health failed: The operation couldn't be completed. (NSURLErrorDomain error -1004.)")
            }
        )

        appState.openLocalDirectory()
        try await waitForAsyncWork()

        XCTAssertEqual(
            appState.errorMessage,
            "The local opencode server did not start on :4096 in time.\n\nLast health check: Health check at http://127.0.0.1:4096/global/health failed: The operation couldn't be completed. (NSURLErrorDomain error -1004.)"
        )
        XCTAssertFalse(appState.isStartingLocalServer)
    }

    func testOpenLocalDirectoryPassesConfiguredExecutablePathToStarter() async throws {
        let client = MockOpenCodeAPIClient(health: .init(healthy: false, version: "1.0.0"))
        let probe = LocalServerProbe()
        let executablePath = "/custom/bin/opencode"
        let startedPath = SynchronizedBox<String?>(nil)

        let appState = OpenCodeAppModel(
            repository: PersistenceRepository(persistence: PersistenceController(inMemory: true)),
            persistsWorkspacePaneState: false,
            localServerStarter: { path in
                startedPath.set(path)
                Task {
                    await probe.recordStart()
                }
                return LocalServerLaunchHandle()
            },
            localServerExecutablePathProvider: { executablePath },
            apiClientProviderOverride: { _ in client },
            directoryChooser: {
                Task {
                    await probe.recordChooser()
                }
            },
            serverWaiter: { _, _ in .reached }
        )

        appState.openLocalDirectory()
        try await waitForAsyncWork()

        XCTAssertEqual(startedPath.get(), executablePath)
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

    func testAnswerPermissionDismissesPromptImmediatelyAndRestoresOnFailure() async throws {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let store = WorkspaceLiveStore(connection: connection)
        let session = makeSession(id: "session-1", directory: connection.directory)
        let permission = makePermission(id: "permission-1", sessionID: session.id)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [permission])
        )

        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.bindLiveStore(store)
        appState.selectedDirectory = connection.directory

        appState.answerPermission(permission, reply: .once)

        XCTAssertTrue(appState.isPermissionDismissed(permission))
        XCTAssertTrue(appState.permissionForSession(session.id).isEmpty)

        let failingService = MockWorkspaceService()
        failingService.permissionReplyError = URLError(.notConnectedToInternet)
        let failingAppState = OpenCodeAppModel(
            workspaceService: failingService,
            persistsWorkspacePaneState: false
        )
        failingAppState.bindLiveStore(store)
        failingAppState.selectedDirectory = connection.directory

        failingAppState.answerPermission(permission, reply: .once)
        try await waitForAsyncWork()

        XCTAssertFalse(failingAppState.isPermissionDismissed(permission))
        XCTAssertEqual(failingAppState.permissionForSession(session.id), [permission])
        XCTAssertNotNil(failingAppState.errorMessage)
    }

    func testAnswerQuestionDismissesPromptImmediatelyAndRestoresOnFailure() async throws {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let store = WorkspaceLiveStore(connection: connection)
        let session = makeSession(id: "session-1", directory: connection.directory)
        let question = makeQuestion(id: "question-1", sessionID: session.id)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [question], permissions: [])
        )

        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.bindLiveStore(store)
        appState.selectedDirectory = connection.directory

        appState.answerQuestion(question, answers: [["A"]])

        XCTAssertTrue(appState.isQuestionDismissed(question))
        XCTAssertTrue(appState.questionForSession(session.id).isEmpty)

        let failingService = MockWorkspaceService()
        failingService.questionReplyError = URLError(.notConnectedToInternet)
        let failingAppState = OpenCodeAppModel(
            workspaceService: failingService,
            persistsWorkspacePaneState: false
        )
        failingAppState.bindLiveStore(store)
        failingAppState.selectedDirectory = connection.directory

        failingAppState.answerQuestion(question, answers: [["A"]])
        try await waitForAsyncWork()

        XCTAssertFalse(failingAppState.isQuestionDismissed(question))
        XCTAssertEqual(failingAppState.questionForSession(session.id), [question])
        XCTAssertNotNil(failingAppState.errorMessage)
    }

    func testRejectQuestionDismissesPromptImmediatelyAndRestoresOnFailure() async throws {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let store = WorkspaceLiveStore(connection: connection)
        let session = makeSession(id: "session-1", directory: connection.directory)
        let question = makeQuestion(id: "question-1", sessionID: session.id)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [question], permissions: [])
        )

        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.bindLiveStore(store)
        appState.selectedDirectory = connection.directory

        appState.rejectQuestion(question)

        XCTAssertTrue(appState.isQuestionDismissed(question))
        XCTAssertTrue(appState.questionForSession(session.id).isEmpty)

        let failingService = MockWorkspaceService()
        failingService.rejectQuestionError = URLError(.notConnectedToInternet)
        let failingAppState = OpenCodeAppModel(
            workspaceService: failingService,
            persistsWorkspacePaneState: false
        )
        failingAppState.bindLiveStore(store)
        failingAppState.selectedDirectory = connection.directory

        failingAppState.rejectQuestion(question)
        try await waitForAsyncWork()

        XCTAssertFalse(failingAppState.isQuestionDismissed(question))
        XCTAssertEqual(failingAppState.questionForSession(session.id), [question])
        XCTAssertNotNil(failingAppState.errorMessage)
    }

    func testAnswerPermissionRefreshesStatusAndMessagesForSession() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
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
        appState.answerPermission(permission, reply: .once)
        try await waitForAsyncWork()

        let refreshedStatuses = await coordinator.refreshedStatusSessionIDsSnapshot()
        let refreshedMessages = await coordinator.refreshedMessageSessionIDsSnapshot()
        XCTAssertEqual(refreshedStatuses, [session.id])
        XCTAssertEqual(refreshedMessages.suffix(1), [session.id])
    }

    func testAnswerPermissionRequestsPromptFocusForSession() async throws {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let store = WorkspaceLiveStore(connection: connection)
        let session = makeSession(id: "session-1", directory: connection.directory)
        let permission = makePermission(id: "permission-1", sessionID: session.id)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [permission])
        )

        let appState = OpenCodeAppModel(persistsWorkspacePaneState: false)
        appState.bindLiveStore(store)
        appState.selectedDirectory = connection.directory

        appState.answerPermission(permission, reply: .once)

        XCTAssertEqual(appState.focusedSessionID, session.id)
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, session.id)
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

    func testWorkspaceLiveStoreNotifiesWhenRunningSessionStops() async {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let notifier = MockWorkspaceEventNotifier()
        let store = WorkspaceLiveStore(connection: connection, notifier: notifier)
        let session = makeSession(id: "session-1", directory: connection.directory)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [session], statuses: [session.id: .busy], questions: [], permissions: [])
        )
        XCTAssertEqual(notifier.eventsSnapshot(), [])

        store.applyStatus(sessionID: session.id, status: .idle)

        XCTAssertEqual(
            notifier.eventsSnapshot(),
            [.sessionStopped(connection: connection, sessionID: session.id, sessionTitle: session.title)]
        )
    }

    func testWorkspaceLiveStoreNotifiesForNewPermissionAndQuestionRequests() async {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let notifier = MockWorkspaceEventNotifier()
        let store = WorkspaceLiveStore(connection: connection, notifier: notifier)
        let session = makeSession(id: "session-1", directory: connection.directory)
        let question = makeQuestion(id: "question-1", sessionID: session.id)
        let permission = makePermission(id: "permission-1", sessionID: session.id)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )

        store.replaceInteractions(sessionID: session.id, questions: [question], permissions: [permission])
        store.replaceInteractions(sessionID: session.id, questions: [question], permissions: [permission])

        XCTAssertEqual(
            notifier.eventsSnapshot(),
            [
                .permissionRequested(connection: connection, sessionID: session.id, sessionTitle: session.title, permission: permission.permission),
                .questionAsked(connection: connection, sessionID: session.id, sessionTitle: session.title, question: question.questions[0].question)
            ]
        )
    }

    func testNotificationTargetHandlerLoadsWorkspaceAndFocusesPane() async throws {
        let directory = try makeTemporaryDirectory()
        let connection = WorkspaceConnection(serverURL: URL(string: "https://example.com")!, directory: directory)
        let session = makeSession(id: "session-1", directory: directory)
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
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
            restoresLastSelectedDirectory: false,
            supportsLocalServer: false
        )

        NativeWorkspaceEventNotifier.shared.setNotificationTargetHandler { target in
            if appState.workspaceConnection != target.connection {
                await appState.updatePreferencesConnection(target.connection)
            }

            appState.openSession(target.sessionID)
            appState.requestSessionCenter(for: target.sessionID)
        }
        defer {
            Task { @MainActor in
                NativeWorkspaceEventNotifier.shared.setNotificationTargetHandler(nil)
            }
        }

        await NativeWorkspaceEventNotifier.shared.handleNotificationTarget(
            .init(connection: connection, sessionID: session.id)
        )

        XCTAssertEqual(appState.serverURL, connection.serverURL)
        XCTAssertEqual(appState.selectedDirectory, directory)
        XCTAssertEqual(appState.focusedSessionID, session.id)
        XCTAssertEqual(appState.openSessionIDs, [session.id])
        XCTAssertEqual(appState.sessionCenterRequest?.sessionID, session.id)
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
        try await waitForAsyncWork(milliseconds: 100)

        XCTAssertEqual(appState.selectedModelOption(for: session.id)?.reference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
        XCTAssertEqual(appState.selectedThinkingLevel(for: session.id), OpenCodeAppModel.defaultThinkingLevel)
        XCTAssertEqual(appState.modelOptions(for: session.id).first?.reference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
    }

    func testLoadPrefersLocalDefaultModelWhenNoRecentModelExists() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.modelCatalogResult = makeRichModelCatalog()

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: false,
            preferredDefaultModelReferenceProvider: {
                ModelReference(providerID: "openai", modelID: "gpt-4.1")
            }
        )

        await appState.load(directory: directory)

        XCTAssertEqual(appState.selectedModelOption(for: session.id)?.reference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
        XCTAssertEqual(appState.modelOptions(for: session.id).first?.reference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
    }

    func testModelOptionsRemainStableAcrossDraftChangesAndUpdateForPreferredDefault() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.modelCatalogResult = makeRichModelCatalog()

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)
        try await waitForAsyncWork(milliseconds: 100)

        let initialOptions = appState.modelOptions(for: session.id)
        let optionsAfterDraftChange = appState.modelOptions(for: session.id)

        XCTAssertEqual(initialOptions, optionsAfterDraftChange)

        appState.setPreferredDefaultModel(ModelReference(providerID: "openai", modelID: "gpt-4.1"))
        let optionsAfterDefaultChange = appState.modelOptions(for: session.id)

        XCTAssertEqual(optionsAfterDefaultChange.first?.reference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
        XCTAssertNotEqual(initialOptions, optionsAfterDefaultChange)
    }

    func testLoadPrefersRecentAgentSelection() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.agentCatalogResult = .init(agents: [
            .init(id: "build", name: "Build", description: nil),
            .init(id: "planner", name: "Planner", description: nil)
        ])

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
                agent: "planner",
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

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)
        try await waitForAsyncWork(milliseconds: 100)

        XCTAssertEqual(appState.selectedAgentOption(for: session.id)?.id, "planner")
        XCTAssertEqual(appState.agentOptions(for: session.id).first?.id, "planner")
    }

    func testSetSelectedModelWithUpdateDefaultPersistsPreferredDefault() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.modelCatalogResult = makeRichModelCatalog()
        let preferenceRecorder = PreferenceRecorder()

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            persistsWorkspacePaneState: false,
            preferredDefaultModelReferenceProvider: { preferenceRecorder.value },
            preferredDefaultModelReferenceSetter: { preferenceRecorder.value = $0 }
        )

        await appState.load(directory: directory)
        appState.setSelectedModel("openai/gpt-4.1", for: session.id, updateDefault: true)

        XCTAssertEqual(preferenceRecorder.value, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
        XCTAssertEqual(appState.preferredDefaultModelReference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
    }

    func testCreateSessionUsesLocalDefaultModelForNewSession() async throws {
        let directory = "/tmp/project"
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: directory)
        let session = makeSession(id: "created-session", directory: directory)
        let repository = PersistenceRepository(persistence: PersistenceController(inMemory: true))
        let workspaceService = MockWorkspaceService(createSessionResult: session)
        workspaceService.modelCatalogResult = makeRichModelCatalog()
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false,
            initialDirectory: directory,
            preferredDefaultModelReferenceProvider: {
                ModelReference(providerID: "openai", modelID: "gpt-4.1")
            }
        )

        await appState.load(directory: directory)
        appState.createSession()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(workspaceService.createSessionCalls, [.init(directory: directory, title: nil, parentID: nil)])
        XCTAssertEqual(appState.selectedModelOption(for: session.id)?.reference, ModelReference(providerID: "openai", modelID: "gpt-4.1"))
        let resolvedCoordinator = await registry.coordinator(for: connection) as? MockWorkspaceSyncCoordinator
        XCTAssertTrue(resolvedCoordinator === coordinator)
    }

    func testSendMessageIncludesSelectedAgent() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.agentCatalogResult = .init(agents: [
            .init(id: "build", name: "Build", description: nil),
            .init(id: "planner", name: "Planner", description: nil)
        ])
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)
        appState.setSelectedAgent("planner", for: session.id)
        appState.sendMessage(sessionID: session.id, text: "Hello world")
        try await waitForAsyncWork()

        XCTAssertEqual(workspaceService.sendMessageCalls.first?.agent, "planner")
    }

    func testLoadCachesCommandCatalog() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.commandCatalogResult = .init(commands: [
            .init(name: "happycog/release", description: "Release branch helper", agent: nil, model: nil, template: "tmpl", subtask: nil)
        ])
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)

        XCTAssertEqual(appState.availableCommandOptions().map(\.slashName), ["/archive", "/close", "/happycog/release", "/new"])
    }

    func testAvailableCommandOptionsPreferLocalSlashCommandsOverRemoteDuplicates() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.commandCatalogResult = .init(commands: [
            .init(name: "new", description: "Server new command", agent: nil, model: nil, template: "tmpl", subtask: nil)
        ])
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)

        let newCommands = appState.availableCommandOptions().filter { $0.slashName == "/new" }
        XCTAssertEqual(newCommands.count, 1)
        XCTAssertEqual(newCommands.first?.description, "Create a new session and focus it")
    }

    func testSlashCommandSuggestionsMatchNestedCommandPath() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )
        workspaceService.commandCatalogResult = .init(commands: [
            .init(name: "happycog/release", description: "Release branch helper", agent: nil, model: nil, template: "tmpl", subtask: nil),
            .init(name: "happycog/init", description: "Init helper", agent: nil, model: nil, template: "tmpl", subtask: nil)
        ])
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator)

        let appState = OpenCodeAppModel(
            workspaceService: workspaceService,
            repository: repository,
            syncRegistry: registry,
            persistsWorkspacePaneState: false
        )

        await appState.load(directory: directory)
        appState.openSessionIDs = [session.id]
        appState.focusedSessionID = session.id
        XCTAssertEqual(appState.slashCommandSuggestions(for: "/rel", sessionID: session.id).map(\.slashName), ["/happycog/release"])
    }

    func testSlashCommandSuggestionsHideAfterCommandSelectionMovesCursorPastSpace() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
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
        appState.openSessionIDs = [session.id]
        appState.focusedSessionID = session.id
        let closeOption = try XCTUnwrap(appState.slashCommandSuggestions(for: "/clo", sessionID: session.id, cursorLocation: 4).first)
        XCTAssertEqual(closeOption.slashName, "/close")

        let acceptedDraft = try XCTUnwrap(appState.applyingSlashCommandSuggestion(closeOption, to: "/clo", sessionID: session.id))

        XCTAssertEqual(acceptedDraft, "/close ")
        XCTAssertTrue(appState.slashCommandSuggestions(for: acceptedDraft, sessionID: session.id, cursorLocation: acceptedDraft.utf16.count).isEmpty)
    }

    func testSendMessageExecutesSlashCommandWhenDraftStartsWithSlash() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session = makeSession(id: "session-1", directory: directory)
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
        appState.openSessionIDs = [session.id]
        appState.sendMessage(sessionID: session.id, text: "/happycog/release 2.3.4 360")
        try await waitForAsyncWork()

        XCTAssertEqual(workspaceService.executeCommandCalls, [
            .init(
                directory: directory,
                sessionID: session.id,
                command: "happycog/release",
                arguments: "2.3.4 360",
                agent: nil,
                model: nil
            )
        ])
        XCTAssertTrue(workspaceService.sendMessageCalls.isEmpty)
    }

    func testSendMessageRunsLocalNewSlashCommand() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let existingSession = makeSession(id: "session-1", directory: directory)
        let createdSession = makeSession(id: "created-session", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [existingSession], statuses: [:], questions: [], permissions: []),
            createSessionResult: createdSession
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
        appState.openSessionIDs = [existingSession.id]
        appState.focusedSessionID = existingSession.id
        XCTAssertTrue(appState.sendMessage(sessionID: existingSession.id, text: "/new"))
        try await waitForAsyncWork()

        XCTAssertEqual(workspaceService.createSessionCalls, [.init(directory: directory, title: nil, parentID: nil)])
        XCTAssertTrue(workspaceService.executeCommandCalls.isEmpty)
        XCTAssertEqual(appState.focusedSessionID, createdSession.id)
        XCTAssertEqual(appState.promptFocusRequest?.sessionID, createdSession.id)
    }

    func testSendMessageRunsLocalCloseSlashCommand() async throws {
        let directory = try makeTemporaryDirectory()
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)
        let session1 = makeSession(id: "session-1", directory: directory)
        let session2 = makeSession(id: "session-2", directory: directory)
        let workspaceService = MockWorkspaceService(
            workspaceSnapshotResult: WorkspaceSnapshot(sessions: [session1, session2], statuses: [:], questions: [], permissions: [])
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
        XCTAssertTrue(appState.sendMessage(sessionID: session1.id, text: "/close"))
        try await waitForAsyncWork()

        XCTAssertEqual(appState.openSessionIDs, [session2.id])
        XCTAssertEqual(appState.focusedSessionID, session2.id)
        XCTAssertTrue(workspaceService.executeCommandCalls.isEmpty)
        let updatedOpenSessions = await coordinator.updatedOpenSessionIDsSnapshot()
        XCTAssertEqual(updatedOpenSessions.last, [session2.id])
    }

    func testSendMessageRunsLocalArchiveSlashCommand() async throws {
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
        XCTAssertTrue(appState.sendMessage(sessionID: session1.id, text: "/archive"))
        try await waitForAsyncWork()

        XCTAssertEqual(workspaceService.archiveSessionCalls, [.init(directory: directory, sessionID: session1.id)])
        XCTAssertEqual(appState.openSessionIDs, [session2.id])
        XCTAssertEqual(appState.focusedSessionID, session2.id)
        XCTAssertTrue(workspaceService.executeCommandCalls.isEmpty)
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
        appState.sendMessage(sessionID: session.id, text: "Hello world")
        try await waitForAsyncWork()

        XCTAssertNotNil(appState.errorMessage)
        XCTAssertEqual(workspaceService.sendMessageCalls.count, 1)
    }
}

final class SessionListEscapeKeyEventTests: XCTestCase {
    func testEscapeRequestsStopWhenListIsFocused() {
        XCTAssertTrue(SessionListEscapeKeyEvent.shouldRequestStop(keyCode: 53, modifiers: [], isListFocused: true))
    }

    func testEscapeIgnoresModifiedKeysOrUnfocusedList() {
        XCTAssertFalse(SessionListEscapeKeyEvent.shouldRequestStop(keyCode: 53, modifiers: [.command], isListFocused: true))
        XCTAssertFalse(SessionListEscapeKeyEvent.shouldRequestStop(keyCode: 53, modifiers: [], isListFocused: false))
        XCTAssertFalse(SessionListEscapeKeyEvent.shouldRequestStop(keyCode: 115, modifiers: [], isListFocused: true))
    }
}

final class FocusedSessionTimelineKeyEventTests: XCTestCase {
    func testHomeAndEndTriggerScrollDirectionWithoutModifiers() {
        XCTAssertEqual(
            FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 115, modifiers: [], isTextInputActive: false),
            .top
        )
        XCTAssertEqual(
            FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 119, modifiers: [], isTextInputActive: false),
            .bottom
        )
    }

    func testScrollDirectionIgnoresModifiedKeysAndTextInput() {
        XCTAssertNil(FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 115, modifiers: [.command], isTextInputActive: false))
        XCTAssertNil(FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 115, modifiers: [], isTextInputActive: true))
        XCTAssertNil(FocusedSessionTimelineKeyEvent.scrollDirection(keyCode: 53, modifiers: [], isTextInputActive: false))
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

    @MainActor
    func testAppModelUsesStoreOwnedBySyncRegistry() async throws {
        let directory = "/tmp/project"
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: directory)
        let sharedStore = WorkspaceLiveStore(connection: connection)
        let coordinator = MockWorkspaceSyncCoordinator()
        let registry = TestWorkspaceSyncRegistry(coordinator: coordinator, store: sharedStore)

        let appState = OpenCodeAppModel(
            syncRegistry: registry,
            persistsWorkspacePaneState: false,
            initialDirectory: directory
        )

        await appState.load(directory: directory)

        XCTAssertTrue(appState.liveStore === sharedStore)
    }

    @MainActor
    func testStreamingMutationsPublishMessageUpdatesImmediately() async throws {
        let state = SessionLiveState(id: "session-1")
        let messageInfo = MessageInfo(
            id: "message-1",
            sessionID: "session-1",
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
        let part = makeMessagePart(id: "part-1", sessionID: "session-1", messageID: "message-1")

        var transcriptRowSnapshots: [[TranscriptMessageRow]] = []
        var cancellables = Set<AnyCancellable>()

        state.$transcriptRows
            .dropFirst()
            .sink { transcriptRowSnapshots.append($0) }
            .store(in: &cancellables)

        state.upsertMessageInfo(messageInfo)

        let messageState = try XCTUnwrap(state.messageState(for: messageInfo.id))
        var messageSnapshots: [MessageEnvelope] = []

        messageState.$snapshot
            .dropFirst()
            .sink { messageSnapshots.append($0) }
            .store(in: &cancellables)

        _ = state.applyMessagePart(part)
        _ = state.applyMessagePartDelta(partID: part.id, field: .text, delta: "Hello")

        XCTAssertEqual(transcriptRowSnapshots.count, 1)
        XCTAssertEqual(transcriptRowSnapshots[0].map(\.id), ["message-1"])
        XCTAssertEqual(messageSnapshots.count, 2)
        XCTAssertEqual(messageSnapshots[0].parts.count, 1)
        XCTAssertEqual(messageSnapshots[1].visibleText, "Hello")
    }

    @MainActor
    func testStreamingTailMessageDoesNotRepublishStableMessageNode() async throws {
        let state = SessionLiveState(id: "session-1")
        let olderMessage = MessageInfo(
            id: "message-1",
            sessionID: "session-1",
            role: .assistant,
            time: .init(created: 1_000, completed: 1_100),
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
        let newerMessage = MessageInfo(
            id: "message-2",
            sessionID: "session-1",
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
        let olderPart = makeMessagePart(id: "part-1", sessionID: "session-1", messageID: "message-1", text: "Stable")
        let newerPart = makeMessagePart(id: "part-2", sessionID: "session-1", messageID: "message-2")

        state.upsertMessageInfo(olderMessage)
        _ = state.applyMessagePart(olderPart)
        state.upsertMessageInfo(newerMessage)
        _ = state.applyMessagePart(newerPart)

        let stableMessageState = try XCTUnwrap(state.messageState(for: olderMessage.id))
        let activeMessageState = try XCTUnwrap(state.messageState(for: newerMessage.id))

        var stableSnapshots: [MessageEnvelope] = []
        var activeSnapshots: [MessageEnvelope] = []
        var transcriptRowSnapshots: [[TranscriptMessageRow]] = []
        var cancellables = Set<AnyCancellable>()

        stableMessageState.$snapshot
            .dropFirst()
            .sink { stableSnapshots.append($0) }
            .store(in: &cancellables)

        activeMessageState.$snapshot
            .dropFirst()
            .sink { activeSnapshots.append($0) }
            .store(in: &cancellables)

        state.$transcriptRows
            .dropFirst()
            .sink { transcriptRowSnapshots.append($0) }
            .store(in: &cancellables)

        _ = state.applyMessagePartDelta(partID: newerPart.id, field: .text, delta: "Hello")

        XCTAssertTrue(stableSnapshots.isEmpty)
        XCTAssertEqual(activeSnapshots.count, 1)
        XCTAssertEqual(activeSnapshots[0].visibleText, "Hello")
        XCTAssertTrue(transcriptRowSnapshots.isEmpty)
    }

    @MainActor
    func testStreamingPartDeltaDoesNotRepublishVisibleSessionIDsWhenOrderIsUnchanged() {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let store = WorkspaceLiveStore(connection: connection)
        let newerSession = makeSession(id: "session-1", directory: connection.directory, updatedAt: 3_000)
        let olderSession = makeSession(id: "session-2", directory: connection.directory, updatedAt: 2_000)
        let messageInfo = MessageInfo(
            id: "message-1",
            sessionID: newerSession.id,
            role: .assistant,
            time: .init(created: 3_000, completed: nil),
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
        let part = makeMessagePart(id: "part-1", sessionID: newerSession.id, messageID: messageInfo.id)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [newerSession, olderSession], statuses: [:], questions: [], permissions: [])
        )
        store.upsertMessageInfo(messageInfo)
        _ = store.applyMessagePart(part)

        var orderedVisibleSnapshots: [[String]] = []
        var cancellables = Set<AnyCancellable>()

        store.$orderedVisibleSessionIDs
            .dropFirst()
            .sink { orderedVisibleSnapshots.append($0) }
            .store(in: &cancellables)

        XCTAssertTrue(store.applyMessagePartDelta(sessionID: newerSession.id, partID: part.id, field: .text, delta: "Hello"))

        XCTAssertEqual(store.orderedVisibleSessionIDs, [newerSession.id, olderSession.id])
        XCTAssertTrue(orderedVisibleSnapshots.isEmpty)
        XCTAssertEqual(store.sessionState(for: newerSession.id).messages.first?.visibleText, "Hello")
    }

    @MainActor
    func testUpsertingNewerMessageReordersVisibleSessions() {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let store = WorkspaceLiveStore(connection: connection)
        let leadingSession = makeSession(id: "session-1", directory: connection.directory, updatedAt: 3_000)
        let trailingSession = makeSession(id: "session-2", directory: connection.directory, updatedAt: 2_000)
        let newerMessage = MessageInfo(
            id: "message-2",
            sessionID: trailingSession.id,
            role: .assistant,
            time: .init(created: 4_000, completed: nil),
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

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [leadingSession, trailingSession], statuses: [:], questions: [], permissions: [])
        )

        var orderedVisibleSnapshots: [[String]] = []
        var sessionSnapshots: [SessionDisplay?] = []
        var cancellables = Set<AnyCancellable>()
        let trailingSessionState = store.sessionState(for: trailingSession.id)

        store.$orderedVisibleSessionIDs
            .dropFirst()
            .sink { orderedVisibleSnapshots.append($0) }
            .store(in: &cancellables)

        trailingSessionState.$session
            .dropFirst()
            .sink { sessionSnapshots.append($0) }
            .store(in: &cancellables)

        store.upsertMessageInfo(newerMessage)

        XCTAssertEqual(store.orderedVisibleSessionIDs, [trailingSession.id, leadingSession.id])
        XCTAssertEqual(orderedVisibleSnapshots, [[trailingSession.id, leadingSession.id]])
        XCTAssertEqual(sessionSnapshots.last??.updatedAtMS, 4_000)
    }

    @MainActor
    func testReplacingInteractionsUpdatesSessionRowWithoutRepublishingVisibleSessionIDs() {
        let connection = WorkspaceConnection(serverURL: OpenCodeAppModel.defaultServerURL, directory: "/tmp/project")
        let store = WorkspaceLiveStore(connection: connection)
        let session = makeSession(id: "session-1", directory: connection.directory, updatedAt: 2_000)
        let permission = makePermission(id: "permission-1", sessionID: session.id)

        store.applyWorkspaceSnapshot(
            WorkspaceSnapshot(sessions: [session], statuses: [:], questions: [], permissions: [])
        )

        var orderedVisibleSnapshots: [[String]] = []
        var sessionSnapshots: [SessionDisplay?] = []
        var cancellables = Set<AnyCancellable>()
        let sessionState = store.sessionState(for: session.id)

        store.$orderedVisibleSessionIDs
            .dropFirst()
            .sink { orderedVisibleSnapshots.append($0) }
            .store(in: &cancellables)

        sessionState.$session
            .dropFirst()
            .sink { sessionSnapshots.append($0) }
            .store(in: &cancellables)

        store.replaceInteractions(sessionID: session.id, questions: [], permissions: [permission])

        XCTAssertTrue(orderedVisibleSnapshots.isEmpty)
        XCTAssertEqual(sessionSnapshots.count, 1)
        XCTAssertEqual(sessionSnapshots.last??.hasPendingPermission, true)
        XCTAssertEqual(store.sessionDisplay(for: session.id)?.indicator.tint, .permission)
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

    func testBufferedStreamingWritesReturnImmediatelyBeforeExplicitFlush() async throws {
        let directory = "/tmp/project"
        let session = makeSession(id: "session-1", directory: directory)
        let persistence = PersistenceController(inMemory: true)
        let repository = PersistenceRepository(persistence: persistence)

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

        let beforeFlushContext = persistence.newBackgroundContext()
        let beforeFlushCount = beforeFlushContext.performAndWait { () -> Int in
            let request = MessageEntity.fetchRequest()
            request.predicate = NSPredicate(format: "sessionID == %@", session.id)
            return ((try? beforeFlushContext.fetch(request)) ?? []).count
        }
        XCTAssertEqual(beforeFlushCount, 0)

        await repository.flushBufferedStreamMutations()

        let afterFlushContext = persistence.newBackgroundContext()
        let afterFlushCount = afterFlushContext.performAndWait { () -> Int in
            let request = MessageEntity.fetchRequest()
            request.predicate = NSPredicate(format: "sessionID == %@", session.id)
            return ((try? afterFlushContext.fetch(request)) ?? []).count
        }
        XCTAssertEqual(afterFlushCount, 1)
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
        let agent: String?
        let model: ModelReference?
        let variant: String?
    }

    struct CommandCall: Equatable {
        let directory: String
        let sessionID: String
        let command: String
        let arguments: String
        let agent: String?
        let model: ModelReference?
    }

    struct SessionCall: Equatable {
        let directory: String
        let sessionID: String
    }

    struct RenameSessionCall: Equatable {
        let directory: String
        let sessionID: String
        let title: String
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
    var renameSessionResult: OpenCodeSession
    var archiveSessionResult: OpenCodeSession
    var commandCatalogResult: CommandCatalog
    var loadSessionsResult: [OpenCodeSession]
    var messagesResult: [String: [MessageEnvelope]]
    var todosResult: [String: [SessionTodo]]
    var statusesResult: [String: SessionStatus]
    var agentCatalogResult: AgentCatalog
    var modelContextLimitsResult: [ModelContextKey: Int]
    var modelCatalogResult: ModelCatalog
    var loadWorkspaceError: Error?
    var loadWorkspaceDelay: Duration?
    var sendMessageError: Error?
    var permissionReplyError: Error?
    var questionReplyError: Error?
    var rejectQuestionError: Error?

    private(set) var loadWorkspaceDirectories: [String] = []
    private(set) var loadInteractionsDirectories: [String] = []
    private(set) var createSessionCalls: [CreateSessionCall] = []
    private(set) var renameSessionCalls: [RenameSessionCall] = []
    private(set) var archiveSessionCalls: [SessionCall] = []
    private(set) var stopSessionCalls: [SessionCall] = []
    private(set) var executeCommandCalls: [CommandCall] = []
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
        renameSessionResult: OpenCodeSession = makeSession(id: "renamed-session"),
        archiveSessionResult: OpenCodeSession = makeSession(id: "archived-session"),
        commandCatalogResult: CommandCatalog = .init(commands: []),
        loadSessionsResult: [OpenCodeSession] = [],
        messagesResult: [String: [MessageEnvelope]] = [:],
        todosResult: [String: [SessionTodo]] = [:],
        statusesResult: [String: SessionStatus] = [:],
        agentCatalogResult: AgentCatalog = .init(agents: []),
        modelContextLimitsResult: [ModelContextKey: Int] = [:],
        modelCatalogResult: ModelCatalog = .init(providers: [], defaultModels: [:], connectedProviderIDs: [])
    ) {
        self.workspaceSnapshotResult = workspaceSnapshotResult
        self.interactionSnapshotResult = interactionSnapshotResult
        self.createSessionResult = createSessionResult
        self.renameSessionResult = renameSessionResult
        self.archiveSessionResult = archiveSessionResult
        self.commandCatalogResult = commandCatalogResult
        self.loadSessionsResult = loadSessionsResult
        self.messagesResult = messagesResult
        self.todosResult = todosResult
        self.statusesResult = statusesResult
        self.agentCatalogResult = agentCatalogResult
        self.modelContextLimitsResult = modelContextLimitsResult
        self.modelCatalogResult = modelCatalogResult
    }

    func loadWorkspace(directory: String) async throws -> WorkspaceSnapshot {
        record { loadWorkspaceDirectories.append(directory) }
        if let loadWorkspaceDelay {
            try? await Task.sleep(for: loadWorkspaceDelay)
        }
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

    func renameSession(directory: String, sessionID: String, title: String) async throws -> OpenCodeSession {
        record { renameSessionCalls.append(.init(directory: directory, sessionID: sessionID, title: title)) }
        return renameSessionResult
    }

    func archiveSession(directory: String, sessionID: String) async throws -> OpenCodeSession {
        record { archiveSessionCalls.append(.init(directory: directory, sessionID: sessionID)) }
        return archiveSessionResult
    }

    func stopSession(directory: String, sessionID: String) async throws {
        record { stopSessionCalls.append(.init(directory: directory, sessionID: sessionID)) }
    }

    func loadCommandCatalog() async throws -> CommandCatalog {
        commandCatalogResult
    }

    func executeCommand(directory: String, sessionID: String, command: String, arguments: String, agent: String?, model: ModelReference?) async throws -> MessageEnvelope {
        record {
            executeCommandCalls.append(
                .init(directory: directory, sessionID: sessionID, command: command, arguments: arguments, agent: agent, model: model)
            )
        }
        return makeMessage(sessionID: sessionID)
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

    func loadAgentCatalog() async throws -> AgentCatalog {
        agentCatalogResult
    }

    func loadModelContextLimits() async throws -> [ModelContextKey: Int] {
        modelContextLimitsResult
    }

    func loadModelCatalog() async throws -> ModelCatalog {
        modelCatalogResult
    }

    func sendMessage(directory: String, sessionID: String, text: String, agent: String?, model: ModelReference?, variant: String?) async throws {
        record { sendMessageCalls.append(.init(directory: directory, sessionID: sessionID, text: text, agent: agent, model: model, variant: variant)) }
        if let sendMessageError {
            throw sendMessageError
        }
    }

    func replyToPermission(directory: String, requestID: String, reply: PermissionReply) async throws {
        record { permissionReplyCalls.append(.init(directory: directory, requestID: requestID, reply: reply)) }
        if let permissionReplyError {
            throw permissionReplyError
        }
    }

    func replyToQuestion(directory: String, requestID: String, answers: [[String]]) async throws {
        record { questionReplyCalls.append(.init(directory: directory, requestID: requestID, answers: answers)) }
        if let questionReplyError {
            throw questionReplyError
        }
    }

    func rejectQuestion(directory: String, requestID: String) async throws {
        record { rejectQuestionCalls.append(.init(directory: directory, requestID: requestID)) }
        if let rejectQuestionError {
            throw rejectQuestionError
        }
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
    private(set) var refreshedStatusSessionIDs: [String] = []
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

    func refreshStatus(sessionID: String) async {
        refreshedStatusSessionIDs.append(sessionID)
    }

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

    func refreshedStatusSessionIDsSnapshot() -> [String] {
        refreshedStatusSessionIDs
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
    private let storeInstance: WorkspaceLiveStore?

    init(coordinator: any WorkspaceSyncCoordinating, store: WorkspaceLiveStore? = nil) {
        coordinatorInstance = coordinator
        storeInstance = store
    }

    func coordinator(for connection: WorkspaceConnection) -> any WorkspaceSyncCoordinating {
        coordinatorInstance
    }

    func store(for connection: WorkspaceConnection) async -> WorkspaceLiveStore {
        if let storeInstance {
            return storeInstance
        }

        return await MainActor.run {
            WorkspaceLiveStore(connection: connection)
        }
    }
}

private final class PreferenceRecorder: @unchecked Sendable {
    var value: ModelReference?
}

private final class MockWorkspaceEventNotifier: WorkspaceEventNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [WorkspaceEventNotification] = []

    func notify(_ event: WorkspaceEventNotification) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func eventsSnapshot() -> [WorkspaceEventNotification] {
        lock.lock()
        let snapshot = events
        lock.unlock()
        return snapshot
    }
}

private final class MockOpenCodeAPIClient: OpenCodeAPIClientProtocol, @unchecked Sendable {
    struct RenameSessionCall: Equatable {
        let directory: String
        let sessionID: String
        let title: String
    }

    let sessionsResult: [OpenCodeSession]
    let statusesResult: [String: SessionStatus]
    let questionsResult: [QuestionRequest]
    let permissionsResult: [PermissionRequest]
    let healthResult: OpenCodeServerHealth
    let projectsResult: [OpenCodeProject]
    let commandsResult: CommandCatalog
    let agentCatalogResult: AgentCatalog
    let renamedSessionResult: OpenCodeSession

    private let lock = NSLock()
    private(set) var recordedDirectories: [String] = []
    private(set) var healthCallCount = 0
    private(set) var projectsCallCount = 0
    private(set) var abortSessionCalls: [MockWorkspaceService.SessionCall] = []
    private(set) var renameSessionCalls: [RenameSessionCall] = []

    init(
        sessions: [OpenCodeSession] = [],
        statuses: [String: SessionStatus] = [:],
        questions: [QuestionRequest] = [],
        permissions: [PermissionRequest] = [],
        health: OpenCodeServerHealth = .init(healthy: true, version: "1.0.0"),
        projects: [OpenCodeProject] = [],
        commands: CommandCatalog = .init(commands: []),
        agentCatalog: AgentCatalog = .init(agents: []),
        renamedSessionResult: OpenCodeSession = makeSession(id: "renamed-session")
    ) {
        sessionsResult = sessions
        statusesResult = statuses
        questionsResult = questions
        permissionsResult = permissions
        healthResult = health
        projectsResult = projects
        commandsResult = commands
        agentCatalogResult = agentCatalog
        self.renamedSessionResult = renamedSessionResult
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

    func commands() async throws -> CommandCatalog {
        commandsResult
    }

    func agentCatalog() async throws -> AgentCatalog {
        agentCatalogResult
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

    func renameSession(directory: String, sessionID: String, title: String) async throws -> OpenCodeSession {
        recordSync {
            recordedDirectories.append(directory)
            renameSessionCalls.append(.init(directory: directory, sessionID: sessionID, title: title))
        }
        return renamedSessionResult
    }

    func archiveSession(directory: String, sessionID: String, archivedAtMS: Double) async throws -> OpenCodeSession {
        record(directory)
        throw TestError.unimplemented
    }

    func abortSession(directory: String, sessionID: String) async throws {
        recordSync {
            recordedDirectories.append(directory)
            abortSessionCalls.append(.init(directory: directory, sessionID: sessionID))
        }
    }

    func executeCommand(directory: String, sessionID: String, command: String, arguments: String, agent: String?, model: ModelReference?) async throws -> MessageEnvelope {
        record(directory)
        return makeMessage(sessionID: sessionID)
    }

    func sendMessage(directory: String, sessionID: String, text: String, agent: String?, model: ModelReference?, variant: String?) async throws {
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

private final class SynchronizedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        let currentValue = value
        lock.unlock()
        return currentValue
    }
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

private func makeSessionDisplay(
    id: String,
    status: SessionStatus?,
    parentID: String? = nil,
    createdAtMS: Double = 1_000,
    updatedAtMS: Double = 2_000
) -> SessionDisplay {
    SessionDisplay(
        id: id,
        title: "Session \(id)",
        createdAtMS: createdAtMS,
        updatedAtMS: updatedAtMS,
        hydratedMessageUpdatedAtMS: nil,
        parentID: parentID,
        status: status,
        hasPendingPermission: false,
        todoProgress: nil,
        contextUsageText: nil,
        isArchived: false
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
    title: String? = nil,
    attachments: [MessagePart.FileAttachment]? = nil
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
            attachments: attachments
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

private func durationMilliseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000 + Int64(components.attoseconds / 1_000_000_000_000_000)
}
