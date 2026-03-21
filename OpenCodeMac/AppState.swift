import AppKit
import Combine
import CoreData
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class OpenCodeAppState: ObservableObject {
    static let defaultThinkingLevel = "__default__"

    @Published var selectedDirectory: String?
    @Published var openSessionIDs: [String] = []
    @Published var focusedSessionID: String?
    @Published var drafts: [String: String] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var focusedSessionScrollRequest: SessionTimelineScrollRequest?
    @Published private(set) var promptFocusRequest: SessionPromptFocusRequest?
    @Published private(set) var paneWidths: [String: CGFloat] = [:]
    @Published private(set) var modelCatalog = ModelCatalog(providers: [], defaultModels: [:], connectedProviderIDs: [])
    @Published private(set) var selectedModelBySession: [String: ModelReference] = [:]
    @Published private(set) var selectedThinkingLevelBySession: [String: String] = [:]
    @Published private(set) var liveStore: WorkspaceLiveStore?
    @Published private(set) var snapshot: PersistenceSnapshot = .empty

    private let logger = Logger(subsystem: "ai.opencode.mac", category: "workspace")
    private let uiSyncLogger = Logger(subsystem: "ai.opencode.mac", category: "ui-sync")
    private let workspaceService: any WorkspaceServiceProtocol
    private let repository: PersistenceRepository
    private let persistence: PersistenceController
    private let syncRegistry: any WorkspaceSyncRegistryProtocol
    private let storeRegistry: WorkspaceLiveStoreRegistry
    private let persistsWorkspacePaneState: Bool
    private let restoresLastSelectedDirectory: Bool

    private let initialDirectory: String?
    private let initialOpenSessionIDs: [String]
    private var hasBootstrapped = false
    private var modelContextLimits: [ModelContextKey: Int] = [:]

    let defaultPaneWidth: CGFloat = 720
    let minPaneWidth: CGFloat = 360
    let maxPaneWidth: CGFloat = 960

    init(
        client: any OpenCodeAPIClientProtocol = OpenCodeAPIClient(),
        workspaceService: (any WorkspaceServiceProtocol)? = nil,
        repository: PersistenceRepository = .shared,
        persistence: PersistenceController = .shared,
        syncRegistry: any WorkspaceSyncRegistryProtocol = WorkspaceSyncRegistry.shared,
        storeRegistry: WorkspaceLiveStoreRegistry = .shared,
        persistsWorkspacePaneState: Bool = true,
        restoresLastSelectedDirectory: Bool = false,
        initialDirectory: String? = nil,
        initialOpenSessionIDs: [String] = []
    ) {
        self.workspaceService = workspaceService ?? WorkspaceService(client: client)
        self.repository = repository
        self.persistence = persistence
        self.syncRegistry = syncRegistry
        self.storeRegistry = storeRegistry
        self.persistsWorkspacePaneState = persistsWorkspacePaneState
        self.restoresLastSelectedDirectory = restoresLastSelectedDirectory
        self.initialDirectory = initialDirectory
        self.initialOpenSessionIDs = initialOpenSessionIDs
    }

    var sessions: [SessionDisplay] {
        liveStore?.sessions ?? []
    }

    var visibleSessions: [SessionDisplay] {
        sessions.filter { !$0.isArchived && !$0.isSubagentSession }
    }

    var projectName: String? {
        selectedDirectory.map { ($0 as NSString).lastPathComponent }
    }

    var messagesBySession: [String: [MessageEnvelope]] {
        liveStore?.allMessagesBySession(for: openSessionIDs) ?? [:]
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        if restoresLastSelectedDirectory, initialDirectory == nil {
            selectedDirectory = await repository.loadLastSelectedDirectory()
        }

        await reloadSnapshot()

        if !initialOpenSessionIDs.isEmpty {
            openSessionIDs = initialOpenSessionIDs
            focusedSessionID = initialOpenSessionIDs.first
            WorkspaceCommandCenter.shared.updateAvailability(
                selectedDirectory: selectedDirectory,
                focusedSessionID: focusedSessionID,
                openSessionIDs: openSessionIDs
            )
        }

        let bootstrapDirectory = initialDirectory ?? selectedDirectory
        if let bootstrapDirectory,
           FileManager.default.fileExists(atPath: bootstrapDirectory) {
            await load(directory: bootstrapDirectory)
        }
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.message = "Choose a project folder for opencode sessions"
        panel.prompt = "Open Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await load(directory: url.path)
        }
    }

    func load(directory: String) async {
        guard !directory.isEmpty else { return }

        logger.info("Loading directory: \(directory, privacy: .public)")
        selectedDirectory = directory
        isLoading = true
        errorMessage = nil
        WorkspaceCommandCenter.shared.bind(appState: self)

        let liveStore = await storeRegistry.store(for: directory)
        bindLiveStore(liveStore)

        if persistsWorkspacePaneState {
            await repository.selectWorkspace(directory: directory)
        }

        do {
            let persistedSnapshot = await repository.loadSnapshot(directory: directory)
            snapshot = persistedSnapshot
            liveStore.replacePaneStates(persistedSnapshot.paneStates)
            liveStore.applyPersistenceSnapshot(persistedSnapshot)

            async let workspaceSnapshotTask = workspaceService.loadWorkspace(directory: directory)
            async let modelCatalogTask = workspaceService.loadModelCatalog()
            async let modelContextLimitTask = workspaceService.loadModelContextLimits()

            let workspaceSnapshot = try await workspaceSnapshotTask

            do {
                modelCatalog = try await modelCatalogTask
            } catch {
                logger.error("Model catalog load failed: \(error.localizedDescription, privacy: .public)")
            }

            do {
                modelContextLimits = try await modelContextLimitTask
                liveStore.setModelContextLimits(modelContextLimits)
            } catch {
                logger.error("Model context limit load failed: \(error.localizedDescription, privacy: .public)")
            }

            await repository.applyWorkspaceSnapshot(
                directory: directory,
                snapshot: workspaceSnapshot,
                modelContextLimits: modelContextLimits,
                openSessionIDs: openSessionIDs
            )
            liveStore.applyWorkspaceSnapshot(workspaceSnapshot)

            if persistsWorkspacePaneState {
                restorePaneState(for: directory)
            }

            if openSessionIDs.isEmpty, let mostRecent = visibleSessions.first {
                openSessionIDs = [mostRecent.id]
                persistPaneStateIfPossible()
            }

            if let focusedSessionID, openSessionIDs.contains(focusedSessionID) {
                self.focusedSessionID = focusedSessionID
            } else {
                self.focusedSessionID = openSessionIDs.first
            }

            WorkspaceCommandCenter.shared.updateAvailability(
                selectedDirectory: selectedDirectory,
                focusedSessionID: focusedSessionID,
                openSessionIDs: openSessionIDs
            )

            reconcileModelSelections()

            let coordinator = await syncRegistry.coordinator(for: directory)
            await coordinator.updateModelContextLimits(modelContextLimits)
            await coordinator.updateOpenSessionIDs(openSessionIDs)
            try await coordinator.start(modelContextLimits: modelContextLimits, openSessionIDs: openSessionIDs, performInitialSync: false)

            for sessionID in openSessionIDs {
                await coordinator.refreshTodos(sessionID: sessionID)
                await coordinator.refreshMessages(sessionID: sessionID)
            }
        } catch {
            logger.error("Load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshAll() {
        guard let selectedDirectory else { return }
        WorkspaceCommandCenter.shared.updateAvailability(
            selectedDirectory: selectedDirectory,
            focusedSessionID: focusedSessionID,
            openSessionIDs: openSessionIDs
        )
        Task {
            await load(directory: selectedDirectory)
        }
    }

    func openSession(_ sessionID: String) {
        if !openSessionIDs.contains(sessionID) {
            openSessionIDs.append(sessionID)
            persistPaneStateIfPossible()
        }
        focusedSessionID = sessionID
        WorkspaceCommandCenter.shared.updateAvailability(
            selectedDirectory: selectedDirectory,
            focusedSessionID: focusedSessionID,
            openSessionIDs: openSessionIDs
        )
        reconcileModelSelection(for: sessionID)

        Task {
            await syncOpenSessions()
            if let selectedDirectory {
                let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
                await coordinator.refreshTodos(sessionID: sessionID)
                await coordinator.refreshMessages(sessionID: sessionID)
            }
        }
    }

    func focusSession(_ sessionID: String, focusPrompt: Bool = false) {
        guard openSessionIDs.contains(sessionID) else {
            openSession(sessionID)
            return
        }

        focusedSessionID = sessionID
        if focusPrompt {
            requestPromptFocus(for: sessionID)
        }
        WorkspaceCommandCenter.shared.updateAvailability(
            selectedDirectory: selectedDirectory,
            focusedSessionID: focusedSessionID,
            openSessionIDs: openSessionIDs
        )
    }

    func focusPreviousPane() {
        focusAdjacentPane(offset: -1)
    }

    func focusNextPane() {
        focusAdjacentPane(offset: 1)
    }

    func closeSession(_ sessionID: String) {
        let closingFocusedSession = focusedSessionID == sessionID
        openSessionIDs.removeAll { $0 == sessionID }
        paneWidths.removeValue(forKey: sessionID)
        if closingFocusedSession {
            focusedSessionID = openSessionIDs.last
        }
        WorkspaceCommandCenter.shared.updateAvailability(
            selectedDirectory: selectedDirectory,
            focusedSessionID: focusedSessionID,
            openSessionIDs: openSessionIDs
        )
        persistPaneStateIfPossible()

        Task {
            await syncOpenSessions()
        }
    }

    func paneWidth(for sessionID: String) -> CGFloat {
        paneWidths[sessionID] ?? defaultPaneWidth
    }

    func setPaneWidth(sessionID: String, width: CGFloat, equalizeAll: Bool, persist: Bool = true) {
        let updatedWidth = clampedPaneWidth(width)
        var didChange = false

        if equalizeAll {
            for openSessionID in openSessionIDs where paneWidth(for: openSessionID) != updatedWidth {
                paneWidths[openSessionID] = updatedWidth
                didChange = true
            }
        } else if paneWidth(for: sessionID) != updatedWidth {
            paneWidths[sessionID] = updatedWidth
            didChange = true
        }

        if didChange, persist {
            persistPaneStateIfPossible()
        }
    }

    func createSession() {
        guard let selectedDirectory else { return }
        Task {
            do {
                let session = try await workspaceService.createSession(directory: selectedDirectory, title: nil, parentID: nil)
                let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
                await repository.applySessionLifecycle(
                    directory: selectedDirectory,
                    session: session,
                    lifecycle: .created,
                    modelContextLimits: modelContextLimits
                )
                liveStore?.applySessionLifecycle(session: session, lifecycle: .created)
                await coordinator.refreshTodos(sessionID: session.id)
                openSession(session.id)
            } catch {
                logger.error("Create session failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func archiveSession(_ sessionID: String) {
        guard let selectedDirectory else { return }
        guard sessions.contains(where: { $0.id == sessionID }) else { return }

        Task {
            do {
                let session = try await workspaceService.archiveSession(directory: selectedDirectory, sessionID: sessionID)
                let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
                await repository.applySessionLifecycle(
                    directory: selectedDirectory,
                    session: session,
                    lifecycle: .updated,
                    modelContextLimits: modelContextLimits
                )
                liveStore?.applySessionLifecycle(session: session, lifecycle: .updated)

                closeSession(sessionID)
                await coordinator.updateOpenSessionIDs(openSessionIDs)
            } catch {
                logger.error("Archive session failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshMessages(for sessionID: String) {
        guard let selectedDirectory else { return }
        Task {
            let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
            await coordinator.refreshMessages(sessionID: sessionID)
        }
    }

    func refreshFocusedSessionMessages() {
        guard let focusedSessionID else { return }
        refreshMessages(for: focusedSessionID)
    }

    func scrollFocusedSessionTimeline(to direction: SessionTimelineScrollDirection) {
        guard let focusedSessionID else { return }
        focusedSessionScrollRequest = SessionTimelineScrollRequest(sessionID: focusedSessionID, direction: direction)
    }

    func todoProgress(for sessionID: String) -> TodoProgress? {
        liveStore?.sessionDisplay(for: sessionID)?.todoProgress
    }

    func contextUsageText(for sessionID: String) -> String? {
        liveStore?.sessionDisplay(for: sessionID)?.contextUsageText
    }

    func modelOptions(for sessionID: String) -> [ModelOption] {
        let recentModel = recentModelReference(for: sessionID)
        let connectedProviderIDs = Set(modelCatalog.connectedProviderIDs)

        return modelCatalog.providers
            .filter { connectedProviderIDs.contains($0.id) }
            .sorted { ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id) == .orderedAscending }
            .flatMap { provider in
                provider.models.values
                    .filter { model in
                        let status = model.status ?? "active"
                        guard status != "deprecated" else { return false }
                        guard model.capabilities?.toolcall != false else { return false }
                        guard model.capabilities?.input?.text != false else { return false }
                        guard model.capabilities?.output?.text != false else { return false }
                        return true
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    .map { model in
                        let thinkingLevels = model.variants.keys.sorted(by: thinkingLevelSort)
                        return ModelOption(
                            providerID: provider.id,
                            providerName: provider.name ?? provider.id,
                            modelID: model.id,
                            modelName: model.name,
                            supportsReasoning: model.capabilities?.reasoning == true && !thinkingLevels.isEmpty,
                            thinkingLevels: thinkingLevels,
                            isDefault: modelCatalog.defaultModels[provider.id] == model.id,
                            isRecent: recentModel == ModelReference(providerID: provider.id, modelID: model.id)
                        )
                    }
            }
            .sorted { lhs, rhs in
                if lhs.isRecent != rhs.isRecent { return lhs.isRecent }
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                if lhs.providerName != rhs.providerName {
                    return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
                }
                return lhs.modelName.localizedCaseInsensitiveCompare(rhs.modelName) == .orderedAscending
            }
    }

    func selectedModelOption(for sessionID: String) -> ModelOption? {
        guard let selected = selectedModelBySession[sessionID] else { return nil }
        return modelOptions(for: sessionID).first { $0.reference == selected }
    }

    func selectedThinkingLevel(for sessionID: String) -> String? {
        guard let option = selectedModelOption(for: sessionID), option.supportsReasoning else { return nil }
        if let selectedLevel = selectedThinkingLevelBySession[sessionID],
           selectedLevel == Self.defaultThinkingLevel || option.thinkingLevels.contains(selectedLevel) {
            return selectedLevel
        }
        return Self.defaultThinkingLevel
    }

    func setSelectedModel(_ referenceKey: String, for sessionID: String) {
        guard let option = modelOptions(for: sessionID).first(where: { $0.id == referenceKey }) else { return }
        selectedModelBySession[sessionID] = option.reference
        normalizeThinkingLevel(for: sessionID, option: option)
    }

    func setSelectedThinkingLevel(_ level: String, for sessionID: String) {
        guard let option = selectedModelOption(for: sessionID) else { return }
        guard level == Self.defaultThinkingLevel || option.thinkingLevels.contains(level) else { return }
        selectedThinkingLevelBySession[sessionID] = level
    }

    func sendMessage(sessionID: String) {
        guard let selectedDirectory else { return }
        let draft = drafts[sessionID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }

        reconcileModelSelection(for: sessionID)
        let selectedModel = selectedModelBySession[sessionID]
        let selectedVariant = selectedThinkingLevel(for: sessionID) == Self.defaultThinkingLevel
            ? nil
            : selectedThinkingLevel(for: sessionID)

        drafts[sessionID] = ""

        Task {
            do {
                try await workspaceService.sendMessage(
                    directory: selectedDirectory,
                    sessionID: sessionID,
                    text: draft,
                    model: selectedModel,
                    variant: selectedVariant
                )
                let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
                await coordinator.refreshMessages(sessionID: sessionID)
            } catch {
                drafts[sessionID] = draft
                logger.error("Send failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func answerPermission(_ request: PermissionRequest, reply: PermissionReply) {
        guard let selectedDirectory else { return }
        Task {
            do {
                try await workspaceService.replyToPermission(directory: selectedDirectory, requestID: request.id, reply: reply)
                let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
                await coordinator.refreshInteractions(sessionID: request.sessionID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func answerQuestion(_ request: QuestionRequest, answers: [[String]]) {
        guard let selectedDirectory else { return }
        Task {
            do {
                try await workspaceService.replyToQuestion(directory: selectedDirectory, requestID: request.id, answers: answers)
                let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
                await coordinator.refreshInteractions(sessionID: request.sessionID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func rejectQuestion(_ request: QuestionRequest) {
        guard let selectedDirectory else { return }
        Task {
            do {
                try await workspaceService.rejectQuestion(directory: selectedDirectory, requestID: request.id)
                let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
                await coordinator.refreshInteractions(sessionID: request.sessionID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func questionForSession(_ sessionID: String) -> [QuestionRequest] {
        liveStore?.existingSessionState(for: sessionID)?.questions ?? []
    }

    func permissionForSession(_ sessionID: String) -> [PermissionRequest] {
        var seenKeys = Set<PermissionPresentationKey>()
        return (liveStore?.existingSessionState(for: sessionID)?.permissions ?? []).filter { request in
            let key = PermissionPresentationKey(request: request)
            return seenKeys.insert(key).inserted
        }
    }

    func sessionIndicator(for sessionID: String) -> SessionIndicator {
        liveStore?.sessionDisplay(for: sessionID)?.indicator ?? SessionIndicator.resolve(status: nil, hasPendingPermission: false)
    }

    private func syncOpenSessions() async {
        guard let selectedDirectory else { return }
        let coordinator = await syncRegistry.coordinator(for: selectedDirectory)
        await coordinator.updateOpenSessionIDs(openSessionIDs)
    }

    private func reloadSnapshot(for directory: String? = nil) async {
        let startedAt = ContinuousClock.now
        let resolvedDirectory = directory ?? selectedDirectory
        let loadedSnapshot = await repository.loadSnapshot(directory: resolvedDirectory)
        let loadedAt = ContinuousClock.now
        snapshot = loadedSnapshot
        if let liveStore {
            liveStore.replacePaneStates(loadedSnapshot.paneStates)
            liveStore.applyPersistenceSnapshot(loadedSnapshot)
        }
        let publishedAt = ContinuousClock.now

        let totalMessages = loadedSnapshot.messagesBySession.values.reduce(0) { $0 + $1.count }
        let focusedSession = focusedSessionID ?? "nil"
        let focusedMessageCount = focusedSessionID.flatMap { loadedSnapshot.messagesBySession[$0]?.count } ?? 0
        let loadMS = durationMilliseconds(startedAt.duration(to: loadedAt))
        let publishMS = durationMilliseconds(loadedAt.duration(to: publishedAt))
        let totalMS = durationMilliseconds(startedAt.duration(to: publishedAt))
        uiSyncLogger.notice(
            "Reloaded snapshot directory=\((resolvedDirectory ?? loadedSnapshot.selectedDirectory ?? "nil"), privacy: .public) sessions=\(loadedSnapshot.sessions.count, privacy: .public) messageSessions=\(loadedSnapshot.messagesBySession.count, privacy: .public) messages=\(totalMessages, privacy: .public) focusedSession=\(focusedSession, privacy: .public) focusedMessages=\(focusedMessageCount, privacy: .public) loadMS=\(loadMS, privacy: .public) publishMS=\(publishMS, privacy: .public) totalMS=\(totalMS, privacy: .public)"
        )
    }

    private func durationMilliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000 + Int64(components.attoseconds / 1_000_000_000_000_000)
    }

    func bindLiveStore(_ liveStore: WorkspaceLiveStore) {
        self.liveStore = liveStore
    }

    private func clampedPaneWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minPaneWidth), maxPaneWidth)
    }

    private func recentModelReference(for sessionID: String) -> ModelReference? {
        messagesBySession[sessionID, default: []]
            .reversed()
            .compactMap { message -> ModelReference? in
                guard let providerID = message.info.providerID ?? message.info.model?.providerID,
                      let modelID = message.info.modelID ?? message.info.model?.modelID else {
                    return nil
                }
                return ModelReference(providerID: providerID, modelID: modelID)
            }
            .first
    }

    private func reconcileModelSelections() {
        for session in sessions {
            reconcileModelSelection(for: session.id)
        }
    }

    private func reconcileModelSelection(for sessionID: String) {
        let options = modelOptions(for: sessionID)

        guard !options.isEmpty else {
            selectedModelBySession.removeValue(forKey: sessionID)
            selectedThinkingLevelBySession.removeValue(forKey: sessionID)
            return
        }

        if let selected = selectedModelBySession[sessionID],
           let selectedOption = options.first(where: { $0.reference == selected }) {
            normalizeThinkingLevel(for: sessionID, option: selectedOption)
            return
        }

        let fallback = preferredModelOption(for: sessionID, options: options) ?? options.first
        if let fallback {
            selectedModelBySession[sessionID] = fallback.reference
            normalizeThinkingLevel(for: sessionID, option: fallback)
        }
    }

    private func preferredModelOption(for sessionID: String, options: [ModelOption]) -> ModelOption? {
        if let recent = recentModelReference(for: sessionID),
           let option = options.first(where: { $0.reference == recent }) {
            return option
        }

        if let option = options.first(where: \.isDefault) {
            return option
        }

        return options.first
    }

    private func normalizeThinkingLevel(for sessionID: String, option: ModelOption) {
        guard option.supportsReasoning else {
            selectedThinkingLevelBySession.removeValue(forKey: sessionID)
            return
        }

        if let selected = selectedThinkingLevelBySession[sessionID],
           selected == Self.defaultThinkingLevel || option.thinkingLevels.contains(selected) {
            return
        }

        selectedThinkingLevelBySession[sessionID] = Self.defaultThinkingLevel
    }

    private func thinkingLevelSort(_ lhs: String, _ rhs: String) -> Bool {
        let rank: [String: Int] = ["low": 0, "medium": 1, "high": 2, "xhigh": 3]
        let lhsRank = rank[lhs.lowercased()] ?? Int.max
        let rhsRank = rank[rhs.lowercased()] ?? Int.max

        if lhsRank == rhsRank {
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        return lhsRank < rhsRank
    }

    private func restorePaneState(for _: String) {
        let availableSessionIDs = Set(sessions.map(\.id))
        let visiblePanes = (liveStore?.paneStates ?? snapshot.paneStates).values
            .filter { !$0.isHidden && availableSessionIDs.contains($0.sessionID) }
            .sorted { lhs, rhs in
                if lhs.position == rhs.position {
                    return lhs.sessionID < rhs.sessionID
                }
                return lhs.position < rhs.position
            }

        if !visiblePanes.isEmpty {
            openSessionIDs = visiblePanes.map(\.sessionID)
            focusedSessionID = openSessionIDs.first
            WorkspaceCommandCenter.shared.updateAvailability(
                selectedDirectory: selectedDirectory,
                focusedSessionID: focusedSessionID,
                openSessionIDs: openSessionIDs
            )
        }

        paneWidths = visiblePanes.reduce(into: [String: CGFloat]()) { result, pane in
            result[pane.sessionID] = clampedPaneWidth(CGFloat(pane.width))
        }
    }

    private func persistPaneStateIfPossible() {
        guard persistsWorkspacePaneState, let selectedDirectory else { return }

        let panes = openSessionIDs.enumerated().map { index, sessionID in
            SessionPaneState(
                sessionID: sessionID,
                position: index,
                width: Double(paneWidth(for: sessionID)),
                isHidden: false
            )
        }

        Task {
            await repository.savePanes(directory: selectedDirectory, panes: panes)
        }
    }

    private func focusAdjacentPane(offset: Int) {
        guard let focusedSessionID,
              let currentIndex = openSessionIDs.firstIndex(of: focusedSessionID)
        else { return }

        let targetIndex = currentIndex + offset
        guard openSessionIDs.indices.contains(targetIndex) else { return }

        focusSession(openSessionIDs[targetIndex], focusPrompt: true)
    }

    private func requestPromptFocus(for sessionID: String) {
        promptFocusRequest = SessionPromptFocusRequest(sessionID: sessionID)
    }
}

struct SessionTimelineScrollRequest: Equatable {
    let id = UUID()
    let sessionID: String
    let direction: SessionTimelineScrollDirection
}

struct SessionPromptFocusRequest: Equatable {
    let id = UUID()
    let sessionID: String
}

private struct PermissionPresentationKey: Hashable {
    let sessionID: String
    let permission: String
    let patterns: [String]
    let always: [String]
    let toolMessageID: String?
    let toolCallID: String?

    init(request: PermissionRequest) {
        sessionID = request.sessionID
        permission = request.permission
        patterns = request.patterns
        always = request.always
        toolMessageID = request.tool?.messageID
        toolCallID = request.tool?.callID
    }
}
