import Combine
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class OpenCodeAppModel: ObservableObject {
    static let defaultThinkingLevel = "__default__"
    static let defaultServerURL = URL(string: "http://127.0.0.1:4096")!
    private static let localCommandOptions: [CommandOption] = [
        .init(id: "local:archive", name: "archive", description: "Archive the current session"),
        .init(id: "local:close", name: "close", description: "Close the current session"),
        .init(id: "local:new", name: "new", description: "Create a new session and focus it")
    ]

    enum LaunchStage: Equatable {
        case checkingLocalServer
        case chooseServerMode
        case localFolderSelection
        case remoteServerEntry
        case remoteDirectoryEntry
    }

    @Published var selectedDirectory: String?
    @Published var serverURL: URL
    @Published var openSessionIDs: [String] = []
    @Published var focusedSessionID: String?
    @Published var drafts: [String: String] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var launchStage: LaunchStage = .checkingLocalServer
    @Published var remoteServerURLText: String = ""
    @Published var remoteDirectoryText: String = ""
    @Published private(set) var remoteProjectSuggestions: [String] = []
    @Published private(set) var isStartingLocalServer = false
    @Published private(set) var isValidatingRemoteServer = false
    @Published private(set) var promptFocusRequest: SessionPromptFocusRequest?
    @Published private(set) var paneWidths: [String: CGFloat] = [:]
    @Published private(set) var commandCatalog = CommandCatalog(commands: [])
    @Published private(set) var agentCatalog = AgentCatalog(agents: [])
    @Published private(set) var modelCatalog = ModelCatalog(providers: [], defaultModels: [:], connectedProviderIDs: [])
    @Published private(set) var selectedAgentBySession: [String: String] = [:]
    @Published private(set) var preferredDefaultModelReference: ModelReference?
    @Published private(set) var selectedModelBySession: [String: ModelReference] = [:]
    @Published private(set) var selectedThinkingLevelBySession: [String: String] = [:]
    @Published private(set) var liveStore: WorkspaceLiveStore?
    @Published private(set) var snapshot: PersistenceSnapshot = .empty
    @Published private(set) var dismissedPermissionRequestIDs: Set<String> = []
    @Published private(set) var dismissedQuestionRequestIDs: Set<String> = []

    private let logger = Logger(subsystem: "ai.opencode.app", category: "workspace")
    private let repository: PersistenceRepository
    private let syncRegistry: any WorkspaceSyncRegistryProtocol
    private let serverController: WorkspaceServerController
    private let persistsWorkspacePaneState: Bool
    private let restoresLastSelectedDirectory: Bool
    private let apiClientProvider: @Sendable (URL) -> any OpenCodeAPIClientProtocol
    private let workspaceServiceProvider: @Sendable (URL) -> any WorkspaceServiceProtocol
    var directoryChooser: @MainActor () -> Void
    private var preferredDefaultModelReferenceProvider: () -> ModelReference?
    private var preferredDefaultModelReferenceSetter: (ModelReference?) -> Void

    private let initialServerURL: URL
    private let initialDirectory: String?
    private let initialOpenSessionIDs: [String]
    private var bootstrapRestoredConnection: WorkspaceConnection?
    private var hasBootstrapped = false
    private var modelContextLimits: [ModelContextKey: Int] = [:]
    private var localServerHandle: LocalServerLaunchHandle?
    private var loadSequence = 0

    let defaultPaneWidth: CGFloat = 720
    let minPaneWidth: CGFloat = 360
    let maxPaneWidth: CGFloat = 960

    init(
        client: (any OpenCodeAPIClientProtocol)? = nil,
        workspaceService: (any WorkspaceServiceProtocol)? = nil,
        repository: PersistenceRepository = .shared,
        syncRegistry: any WorkspaceSyncRegistryProtocol = WorkspaceSyncRegistry.shared,
        persistsWorkspacePaneState: Bool = true,
        restoresLastSelectedDirectory: Bool = false,
        initialServerURL: URL = OpenCodeAppModel.defaultServerURL,
        initialDirectory: String? = nil,
        initialOpenSessionIDs: [String] = [],
        localServerStarter: (@Sendable (String) throws -> LocalServerLaunchHandle)? = nil,
        localServerExecutablePathProvider: (@Sendable () -> String)? = nil,
        apiClientProviderOverride: (@Sendable (URL) -> any OpenCodeAPIClientProtocol)? = nil,
        workspaceServiceProviderOverride: (@Sendable (URL) -> any WorkspaceServiceProtocol)? = nil,
        preferredDefaultModelReferenceProvider: @escaping () -> ModelReference? = { nil },
        preferredDefaultModelReferenceSetter: @escaping (ModelReference?) -> Void = { _ in },
        directoryChooser: @escaping @MainActor () -> Void = {},
        serverWaiter: (@Sendable (URL, Duration) async -> ServerStartupWaitResult)? = nil
    ) {
        self.repository = repository
        self.syncRegistry = syncRegistry
        self.persistsWorkspacePaneState = persistsWorkspacePaneState
        self.restoresLastSelectedDirectory = restoresLastSelectedDirectory
        self.initialServerURL = initialServerURL
        self.serverURL = initialServerURL
        self.initialDirectory = initialDirectory
        self.initialOpenSessionIDs = initialOpenSessionIDs

        if let apiClientProviderOverride {
            apiClientProvider = apiClientProviderOverride
        } else if let client {
            apiClientProvider = { (_: URL) in client }
        } else {
            apiClientProvider = { (url: URL) in OpenCodeAPIClient(baseURL: url) }
        }

        if let workspaceServiceProviderOverride {
            workspaceServiceProvider = workspaceServiceProviderOverride
        } else if let workspaceService {
            workspaceServiceProvider = { (_: URL) in workspaceService }
        } else {
            let clientProvider = apiClientProvider
            workspaceServiceProvider = { (url: URL) in
                WorkspaceService(client: clientProvider(url))
            }
        }

        let resolvedLocalServerExecutablePathProvider = localServerExecutablePathProvider ?? {
            NSString(string: LocalServerPreferencesController.loadOpencodeExecutablePath()).expandingTildeInPath
        }
        let resolvedLocalServerStarter = localServerStarter ?? { [logger] executablePath in
            try LocalServerLauncher.launch(opencodePath: executablePath, logger: logger)
        }
        serverController = WorkspaceServerController(
            apiClientProvider: apiClientProvider,
            localServerStarter: resolvedLocalServerStarter,
            localServerExecutablePathProvider: resolvedLocalServerExecutablePathProvider,
            serverWaiter: serverWaiter
        )
        self.preferredDefaultModelReferenceProvider = preferredDefaultModelReferenceProvider
        self.preferredDefaultModelReferenceSetter = preferredDefaultModelReferenceSetter
        preferredDefaultModelReference = preferredDefaultModelReferenceProvider()
        self.directoryChooser = directoryChooser
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

    var isUsingLocalServer: Bool {
        serverURL == Self.defaultServerURL
    }

    var serverDisplayText: String {
        serverURL.absoluteString
    }

    var workspaceConnection: WorkspaceConnection? {
        guard let selectedDirectory else { return nil }
        return WorkspaceConnection(serverURL: serverURL, directory: selectedDirectory)
    }

    var messagesBySession: [String: [MessageEnvelope]] {
        liveStore?.allMessagesBySession(for: openSessionIDs) ?? [:]
    }

    func availableModelOptions() -> [ModelOption] {
        buildModelOptions(recentModel: nil)
    }

    func availableAgentOptions() -> [AgentOption] {
        buildAgentOptions(recentAgentID: nil)
    }

    func availableCommandOptions() -> [CommandOption] {
        buildCommandOptions()
    }

    func configurePreferredDefaultModelPersistence(
        provider: @escaping () -> ModelReference?,
        setter: @escaping (ModelReference?) -> Void
    ) {
        preferredDefaultModelReferenceProvider = provider
        preferredDefaultModelReferenceSetter = setter
        preferredDefaultModelReference = provider()
        reconcileModelSelections()
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        if !initialOpenSessionIDs.isEmpty {
            openSessionIDs = initialOpenSessionIDs
            focusedSessionID = initialOpenSessionIDs.first
        }

        if let bootstrapConnection = preferredBootstrapConnection() {
            serverURL = bootstrapConnection.serverURL
            launchStage = bootstrapConnection.serverURL == Self.defaultServerURL ? .localFolderSelection : .remoteDirectoryEntry
            await load(directory: bootstrapConnection.directory)
            return
        }

        if restoresLastSelectedDirectory {
            let bootstrapDirectory = await repository.loadLastSelectedDirectory()
            if let bootstrapDirectory,
               FileManager.default.fileExists(atPath: bootstrapDirectory) {
                launchStage = initialServerURL == Self.defaultServerURL ? .localFolderSelection : .remoteDirectoryEntry
                Task {
                    await load(directory: bootstrapDirectory)
                }
                return
            }
        }

        launchStage = initialServerURL == Self.defaultServerURL ? .chooseServerMode : .remoteServerEntry
    }

    func configureBootstrapRestoredConnection(_ connection: WorkspaceConnection?) {
        guard !hasBootstrapped else { return }
        bootstrapRestoredConnection = connection
    }

    func chooseDirectory() {
        directoryChooser()
    }

    private func preferredBootstrapConnection() -> WorkspaceConnection? {
        if let bootstrapRestoredConnection,
           canRestoreWorkspaceConnection(bootstrapRestoredConnection) {
            return bootstrapRestoredConnection
        }

        if let initialDirectory {
            let initialConnection = WorkspaceConnection(serverURL: initialServerURL, directory: initialDirectory)
            if canRestoreWorkspaceConnection(initialConnection) {
                return initialConnection
            }
        }

        return nil
    }

    private func canRestoreWorkspaceConnection(_ connection: WorkspaceConnection) -> Bool {
        guard !connection.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if connection.serverURL == Self.defaultServerURL {
            return FileManager.default.fileExists(atPath: connection.directory)
        }

        return true
    }

    func updatePreferencesConnection(_ connection: WorkspaceConnection) async {
        guard serverURL != connection.serverURL || selectedDirectory != connection.directory else { return }
        serverURL = connection.serverURL
        await load(directory: connection.directory)
    }

    func setDirectoryChooser(_ chooser: @escaping @MainActor () -> Void) {
        directoryChooser = chooser
    }

    func showRemoteServerEntry() {
        clearWorkspaceSelection()
        remoteServerURLText = remoteServerURLText.isEmpty ? "https://" : remoteServerURLText
        launchStage = .remoteServerEntry
    }

    func openLocalDirectory() {
        guard !isStartingLocalServer else { return }

        Task {
            isStartingLocalServer = true
            errorMessage = nil

            do {
                localServerHandle = try await serverController.startLocalServerIfNeeded(at: Self.defaultServerURL) ?? localServerHandle
                serverURL = Self.defaultServerURL
                chooseDirectory()
            } catch {
                errorMessage = error.localizedDescription
            }

            isStartingLocalServer = false
        }
    }

    func connectToRemoteServer() {
        guard !isValidatingRemoteServer else { return }

        Task {
            isValidatingRemoteServer = true
            errorMessage = nil

            do {
                let connection = try await serverController.connectToRemoteServer(from: remoteServerURLText)
                serverURL = connection.serverURL
                remoteServerURLText = connection.normalizedURLText
                launchStage = .remoteDirectoryEntry
                remoteProjectSuggestions = connection.projectSuggestions
            } catch {
                errorMessage = error.localizedDescription
            }

            isValidatingRemoteServer = false
        }
    }

    func refreshRemoteProjectSuggestions() async {
        remoteProjectSuggestions = await serverController.refreshRemoteProjectSuggestions(serverURL: serverURL)
    }

    func chooseRemoteProjectSuggestion(_ path: String) {
        remoteDirectoryText = path
    }

    func connectToRemoteDirectory() {
        let trimmedPath = remoteDirectoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        Task {
            await load(directory: trimmedPath)
        }
    }

    func resetServerSelection() {
        clearWorkspaceSelection()
        serverURL = Self.defaultServerURL
        remoteProjectSuggestions = []
        remoteDirectoryText = ""
        launchStage = .chooseServerMode
    }

    func load(directory: String) async {
        guard !directory.isEmpty else { return }

        let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDirectory.isEmpty else { return }

        let previousDirectory = selectedDirectory
        let previousLiveStore = liveStore
        let previousSnapshot = snapshot
        let workspaceService = workspaceServiceProvider(serverURL)
        let connection = WorkspaceConnection(serverURL: serverURL, directory: trimmedDirectory)
        loadSequence += 1
        let loadID = loadSequence
        let loadStart = PerformanceInstrumentation.begin(
            "workspace-load",
            details: "loadID=\(loadID) directory=\(trimmedDirectory) server=\(self.serverURL.absoluteString)"
        )

        logger.info("Loading directory: \(trimmedDirectory, privacy: .public) server=\(self.serverURL.absoluteString, privacy: .public)")
        selectedDirectory = trimmedDirectory
        isLoading = true
        errorMessage = nil

        let liveStoreLookupStart = PerformanceInstrumentation.begin(
            "workspace-load-live-store",
            details: "loadID=\(loadID) directory=\(trimmedDirectory)"
        )
        let liveStore = await syncRegistry.store(for: connection)
        PerformanceInstrumentation.end(
            "workspace-load-live-store",
            from: liveStoreLookupStart,
            details: "loadID=\(loadID) directory=\(trimmedDirectory)",
            thresholdMS: 1
        )

        let bindLiveStoreStart = PerformanceInstrumentation.begin(
            "workspace-load-bind-live-store",
            details: "loadID=\(loadID) directory=\(trimmedDirectory)"
        )
        bindLiveStore(liveStore)
        PerformanceInstrumentation.end(
            "workspace-load-bind-live-store",
            from: bindLiveStoreStart,
            details: "loadID=\(loadID) directory=\(trimmedDirectory)",
            thresholdMS: 1
        )

        do {
            let snapshotLoadStart = PerformanceInstrumentation.begin(
                "workspace-load-persistence-snapshot",
                details: "loadID=\(loadID) directory=\(trimmedDirectory)"
            )
            let preferredSnapshotSessionIDs = Set(initialOpenSessionIDs)
                .union(openSessionIDs)
                .union(snapshot.paneStates.values.filter { !$0.isHidden }.map(\.sessionID))
            let persistedSnapshot = await repository.loadSnapshot(
                directory: trimmedDirectory,
                preferredMessageSessionIDs: preferredSnapshotSessionIDs,
                decodeOnlyPreferredSessions: true
            )
            PerformanceInstrumentation.end(
                "workspace-load-persistence-snapshot",
                from: snapshotLoadStart,
                details: "loadID=\(loadID) directory=\(trimmedDirectory) sessions=\(persistedSnapshot.sessions.count) messageSessions=\(persistedSnapshot.messagesBySession.count)",
                thresholdMS: 1
            )
            snapshot = persistedSnapshot

            let applyPersistenceStart = PerformanceInstrumentation.begin(
                "workspace-load-apply-persistence",
                details: "loadID=\(loadID) directory=\(trimmedDirectory)"
            )
            liveStore.replacePaneStates(persistedSnapshot.paneStates)
            liveStore.applyPersistenceSnapshot(persistedSnapshot)
            applyLoadedWorkspaceState(for: trimmedDirectory)
            PerformanceInstrumentation.end(
                "workspace-load-apply-persistence",
                from: applyPersistenceStart,
                details: "loadID=\(loadID) directory=\(trimmedDirectory) openSessions=\(openSessionIDs.count)",
                thresholdMS: 1
            )

            if persistsWorkspacePaneState {
                Task {
                    await self.repository.selectWorkspace(directory: trimmedDirectory)
                }
            }

            let hasCachedWorkspaceContent = !persistedSnapshot.sessions.isEmpty

            if hasCachedWorkspaceContent {
                PerformanceInstrumentation.log(
                    "workspace-load-using-cached-content loadID=\(loadID) directory=\(trimmedDirectory) sessions=\(persistedSnapshot.sessions.count)"
                )
                isLoading = false
                launchStage = isUsingLocalServer ? .localFolderSelection : .remoteDirectoryEntry
                PerformanceInstrumentation.end(
                    "workspace-load",
                    from: loadStart,
                    details: "loadID=\(loadID) directory=\(trimmedDirectory) cached=true",
                    thresholdMS: 1
                )
                Task {
                    let loadedModelContextLimits = await refreshModelMetadata(
                        loadID: loadID,
                        connection: connection,
                        workspaceService: workspaceService,
                        liveStore: liveStore
                    )
                    guard isCurrentLoad(loadID, for: connection), self.liveStore === liveStore else { return }
                    reconcileModelSelections()
                    await refreshOpenSessionHistories(connection: connection)

                    await refreshWorkspaceInBackground(
                        loadID: loadID,
                        directory: trimmedDirectory,
                        connection: connection,
                        workspaceService: workspaceService,
                        liveStore: liveStore,
                        reportErrorsToUser: true,
                        loadedModelContextLimits: loadedModelContextLimits
                    )
                }
                return
            }

            let loadedModelContextLimits = await refreshModelMetadata(
                loadID: loadID,
                connection: connection,
                workspaceService: workspaceService,
                liveStore: liveStore
            )

            try await refreshWorkspaceContents(
                loadID: loadID,
                directory: trimmedDirectory,
                connection: connection,
                workspaceService: workspaceService,
                liveStore: liveStore,
                reportErrorsToUser: false,
                loadedModelContextLimits: loadedModelContextLimits
            )
            launchStage = isUsingLocalServer ? .localFolderSelection : .remoteDirectoryEntry
            await refreshOpenSessionHistories(connection: connection)
        } catch {
            logger.error("Load failed: \(error.localizedDescription, privacy: .public)")
            PerformanceInstrumentation.log(
                "workspace-load-failed loadID=\(loadID) directory=\(trimmedDirectory) error=\(error.localizedDescription)"
            )
            errorMessage = error.localizedDescription
            selectedDirectory = previousDirectory
            snapshot = previousSnapshot
            self.liveStore = previousLiveStore
        }

        isLoading = false
        PerformanceInstrumentation.end(
            "workspace-load",
            from: loadStart,
            details: "loadID=\(loadID) directory=\(trimmedDirectory) cached=false",
            thresholdMS: 1
        )
    }

    private func refreshWorkspaceInBackground(
        loadID: Int,
        directory: String,
        connection: WorkspaceConnection,
        workspaceService: any WorkspaceServiceProtocol,
        liveStore: WorkspaceLiveStore,
        reportErrorsToUser: Bool,
        loadedModelContextLimits: [ModelContextKey: Int]? = nil
    ) async {
        do {
            let resolvedModelContextLimits: [ModelContextKey: Int]
            if let loadedModelContextLimits {
                resolvedModelContextLimits = loadedModelContextLimits
            } else {
                resolvedModelContextLimits = await refreshModelMetadata(
                    loadID: loadID,
                    connection: connection,
                    workspaceService: workspaceService,
                    liveStore: liveStore
                )
            }

            try await refreshWorkspaceContents(
                loadID: loadID,
                directory: directory,
                connection: connection,
                workspaceService: workspaceService,
                liveStore: liveStore,
                reportErrorsToUser: reportErrorsToUser,
                loadedModelContextLimits: resolvedModelContextLimits
            )
        } catch {
            logger.error("Background refresh failed: \(error.localizedDescription, privacy: .public)")
            guard reportErrorsToUser, isCurrentLoad(loadID, for: connection), self.liveStore === liveStore else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func refreshWorkspaceContents(
        loadID: Int,
        directory: String,
        connection: WorkspaceConnection,
        workspaceService: any WorkspaceServiceProtocol,
        liveStore: WorkspaceLiveStore,
        reportErrorsToUser: Bool,
        loadedModelContextLimits: [ModelContextKey: Int]
    ) async throws {
        let refreshStart = PerformanceInstrumentation.begin(
            "workspace-refresh-contents",
            details: "loadID=\(loadID) directory=\(directory)"
        )
        let workspaceSnapshot = try await workspaceService.loadWorkspace(directory: directory)

        await repository.applyWorkspaceSnapshot(
            directory: directory,
            snapshot: workspaceSnapshot,
            modelContextLimits: loadedModelContextLimits,
            openSessionIDs: openSessionIDs
        )

        guard isCurrentLoad(loadID, for: connection), self.liveStore === liveStore else { return }

        liveStore.applyWorkspaceSnapshot(workspaceSnapshot)
        applyLoadedWorkspaceState(for: directory)

        let coordinator = await syncRegistry.coordinator(for: connection)
        await coordinator.updateModelContextLimits(loadedModelContextLimits)
        await coordinator.updateOpenSessionIDs(openSessionIDs)
        try await coordinator.start(modelContextLimits: loadedModelContextLimits, openSessionIDs: openSessionIDs, performInitialSync: false)

        for sessionID in openSessionIDs {
            await coordinator.refreshTodos(sessionID: sessionID)
            await coordinator.refreshMessages(sessionID: sessionID)
        }

        if reportErrorsToUser {
            errorMessage = nil
        }

        PerformanceInstrumentation.end(
            "workspace-refresh-contents",
            from: refreshStart,
            details: "loadID=\(loadID) directory=\(directory) sessions=\(workspaceSnapshot.sessions.count) statuses=\(workspaceSnapshot.statuses.count) questions=\(workspaceSnapshot.questions.count) permissions=\(workspaceSnapshot.permissions.count)",
            thresholdMS: 1
        )
    }

    private func refreshModelMetadata(
        loadID: Int,
        connection: WorkspaceConnection,
        workspaceService: any WorkspaceServiceProtocol,
        liveStore: WorkspaceLiveStore
    ) async -> [ModelContextKey: Int] {
        let metadataStart = PerformanceInstrumentation.begin(
            "workspace-refresh-model-metadata",
            details: "loadID=\(loadID) directory=\(connection.directory)"
        )
        async let commandCatalogTask = workspaceService.loadCommandCatalog()
        async let modelCatalogTask = workspaceService.loadModelCatalog()
        async let agentCatalogTask = workspaceService.loadAgentCatalog()
        async let modelContextLimitTask = workspaceService.loadModelContextLimits()
        var loadedModelContextLimits = modelContextLimits

        do {
            let catalog = try await commandCatalogTask
            guard isCurrentLoad(loadID, for: connection), self.liveStore === liveStore else { return loadedModelContextLimits }
            commandCatalog = catalog
        } catch {
            logger.error("Command catalog load failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let catalog = try await agentCatalogTask
            guard isCurrentLoad(loadID, for: connection), self.liveStore === liveStore else { return loadedModelContextLimits }
            agentCatalog = catalog
        } catch {
            logger.error("Agent catalog load failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let catalog = try await modelCatalogTask
            guard isCurrentLoad(loadID, for: connection), self.liveStore === liveStore else { return loadedModelContextLimits }
            modelCatalog = catalog
        } catch {
            logger.error("Model catalog load failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let limits = try await modelContextLimitTask
            loadedModelContextLimits = limits
            if isCurrentLoad(loadID, for: connection), self.liveStore === liveStore {
                modelContextLimits = limits
                liveStore.setModelContextLimits(limits)
            }
        } catch {
            logger.error("Model context limit load failed: \(error.localizedDescription, privacy: .public)")
        }

        PerformanceInstrumentation.end(
            "workspace-refresh-model-metadata",
            from: metadataStart,
            details: "loadID=\(loadID) directory=\(connection.directory) commands=\(commandCatalog.commands.count) agents=\(agentCatalog.agents.count) providers=\(modelCatalog.providers.count) limits=\(loadedModelContextLimits.count)",
            thresholdMS: 1
        )
        return loadedModelContextLimits
    }

    private func applyLoadedWorkspaceState(for directory: String) {
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

        reconcileModelSelections()
    }

    private func isCurrentLoad(_ loadID: Int, for connection: WorkspaceConnection) -> Bool {
        loadID == loadSequence && workspaceConnection == connection
    }

    func refreshAll() {
        guard let selectedDirectory else { return }
        Task {
            await load(directory: selectedDirectory)
        }
    }

    private func refreshOpenSessionHistories(connection: WorkspaceConnection) async {
        guard !openSessionIDs.isEmpty else { return }
        let coordinator = await syncRegistry.coordinator(for: connection)
        PerformanceInstrumentation.log(
            "refresh-open-session-histories directory=\(connection.directory) sessionCount=\(openSessionIDs.count) sessions=\(openSessionIDs.joined(separator: ","))"
        )
        for sessionID in openSessionIDs {
            await coordinator.refreshMessages(sessionID: sessionID)
        }
    }

    func openSession(_ sessionID: String, focusPrompt: Bool = false) {
        if !openSessionIDs.contains(sessionID) {
            openSessionIDs.append(sessionID)
            persistPaneStateIfPossible()
        }
        focusedSessionID = sessionID
        reconcileModelSelection(for: sessionID)
        if focusPrompt {
            requestPromptFocus(for: sessionID)
        }

        Task {
            await syncOpenSessions()
            if let workspaceConnection {
                PerformanceInstrumentation.log(
                    "open-session-refresh sessionID=\(sessionID) directory=\(workspaceConnection.directory)"
                )
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await coordinator.refreshTodos(sessionID: sessionID)
                await coordinator.refreshMessages(sessionID: sessionID)
            }
        }
    }

    func focusSession(_ sessionID: String, focusPrompt: Bool = false) {
        guard openSessionIDs.contains(sessionID) else {
            openSession(sessionID, focusPrompt: focusPrompt)
            return
        }

        focusedSessionID = sessionID
        if focusPrompt {
            requestPromptFocus(for: sessionID)
        }
    }

    func focusPreviousPane() {
        focusAdjacentPane(offset: -1)
    }

    func focusNextPane() {
        focusAdjacentPane(offset: 1)
    }

    func closeSession(_ sessionID: String) {
        let closingFocusedSession = focusedSessionID == sessionID
        let closingIndex = openSessionIDs.firstIndex(of: sessionID)
        openSessionIDs.removeAll { $0 == sessionID }
        paneWidths.removeValue(forKey: sessionID)
        if closingFocusedSession {
            focusedSessionID = sessionIDToFocusAfterClosingSession(at: closingIndex)
            if let focusedSessionID {
                requestPromptFocus(for: focusedSessionID)
            }
        }
        persistPaneStateIfPossible()

        Task {
            await syncOpenSessions()
        }
    }

    func moveOpenSession(
        _ sessionID: String,
        before targetSessionID: String? = nil,
        persist: Bool = true,
        sync: Bool = true
    ) {
        guard let sourceIndex = openSessionIDs.firstIndex(of: sessionID) else { return }

        var reorderedSessionIDs = openSessionIDs
        reorderedSessionIDs.remove(at: sourceIndex)

        if let targetSessionID {
            guard sessionID != targetSessionID,
                  let targetIndex = reorderedSessionIDs.firstIndex(of: targetSessionID) else {
                return
            }
            reorderedSessionIDs.insert(sessionID, at: targetIndex)
        } else {
            reorderedSessionIDs.append(sessionID)
        }

        guard reorderedSessionIDs != openSessionIDs else { return }

        openSessionIDs = reorderedSessionIDs
        if persist {
            persistPaneStateIfPossible()
        }

        if sync {
            Task {
                await syncOpenSessions()
            }
        }
    }

    func commitOpenSessionOrder() {
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
                logger.notice("Create session started directory=\(selectedDirectory, privacy: .public)")
                let workspaceService = workspaceServiceProvider(serverURL)
                let session = try await workspaceService.createSession(directory: selectedDirectory, title: nil, parentID: nil)
                logger.notice("Create session created directory=\(selectedDirectory, privacy: .public) sessionID=\(session.id, privacy: .public)")
                guard let workspaceConnection else { return }
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await repository.applySessionLifecycle(
                    directory: selectedDirectory,
                    session: session,
                    lifecycle: .created,
                    modelContextLimits: modelContextLimits
                )
                liveStore?.applySessionLifecycle(session: session, lifecycle: .created)
                await coordinator.refreshTodos(sessionID: session.id)
                logger.notice(
                    "Create session applied local lifecycle directory=\(selectedDirectory, privacy: .public) sessionID=\(session.id, privacy: .public) visibleSessions=\(self.visibleSessions.count, privacy: .public)"
                )
                openSession(session.id, focusPrompt: true)
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
                let workspaceService = workspaceServiceProvider(serverURL)
                let session = try await workspaceService.archiveSession(directory: selectedDirectory, sessionID: sessionID)
                guard let workspaceConnection else { return }
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
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

    func stopSession(_ sessionID: String) {
        guard let selectedDirectory else { return }
        guard sessions.contains(where: { $0.id == sessionID }) else { return }

        Task {
            do {
                let workspaceService = workspaceServiceProvider(serverURL)
                try await workspaceService.stopSession(directory: selectedDirectory, sessionID: sessionID)
                guard let workspaceConnection else { return }
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await coordinator.refreshStatus(sessionID: sessionID)
                await coordinator.refreshMessages(sessionID: sessionID)
                await coordinator.refreshInteractions(sessionID: sessionID)
            } catch {
                logger.error("Stop session failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshMessages(for sessionID: String) {
        guard workspaceConnection != nil else { return }
        Task {
            guard let workspaceConnection else { return }
            let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
            await coordinator.refreshMessages(sessionID: sessionID)
        }
    }

    func refreshFocusedSessionMessages() {
        guard let focusedSessionID else { return }
        refreshMessages(for: focusedSessionID)
    }

    func todoProgress(for sessionID: String) -> TodoProgress? {
        liveStore?.sessionDisplay(for: sessionID)?.todoProgress
    }

    func contextUsageText(for sessionID: String) -> String? {
        liveStore?.sessionDisplay(for: sessionID)?.contextUsageText
    }

    func modelOptions(for sessionID: String) -> [ModelOption] {
        let recentModel = recentModelReference(for: sessionID)
        return buildModelOptions(recentModel: recentModel)
    }

    func agentOptions(for sessionID: String) -> [AgentOption] {
        let recentAgentID = recentAgentID(for: sessionID)
        return buildAgentOptions(recentAgentID: recentAgentID)
    }

    func selectedAgentOption(for sessionID: String) -> AgentOption? {
        guard let selected = selectedAgentBySession[sessionID] else { return nil }
        return agentOptions(for: sessionID).first { $0.id == selected }
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

    func setSelectedModel(_ referenceKey: String, for sessionID: String, updateDefault: Bool = false) {
        guard let option = modelOptions(for: sessionID).first(where: { $0.id == referenceKey }) else { return }
        selectedModelBySession[sessionID] = option.reference
        normalizeThinkingLevel(for: sessionID, option: option)

        if updateDefault {
            setPreferredDefaultModel(option.reference)
        }
    }

    func setSelectedAgent(_ agentID: String, for sessionID: String) {
        guard agentOptions(for: sessionID).contains(where: { $0.id == agentID }) else { return }
        selectedAgentBySession[sessionID] = agentID
    }

    func setPreferredDefaultModel(_ reference: ModelReference?) {
        guard preferredDefaultModelReference != reference else { return }
        preferredDefaultModelReference = reference
        preferredDefaultModelReferenceSetter(reference)
        reconcileModelSelections()
    }

    func setSelectedThinkingLevel(_ level: String, for sessionID: String) {
        guard let option = selectedModelOption(for: sessionID) else { return }
        guard level == Self.defaultThinkingLevel || option.thinkingLevels.contains(level) else { return }
        selectedThinkingLevelBySession[sessionID] = level
    }

    func slashCommandSuggestions(for sessionID: String, cursorLocation: Int = 0) -> [CommandOption] {
        guard focusedSessionID == sessionID || openSessionIDs.contains(sessionID) else { return [] }
        let draft = drafts[sessionID, default: ""]
        return CommandAutocomplete.suggestions(for: draft, cursorLocation: cursorLocation, commands: availableCommandOptions())
    }

    func applySlashCommandSuggestion(_ option: CommandOption, for sessionID: String) {
        let draft = drafts[sessionID, default: ""]
        guard let updatedDraft = CommandAutocomplete.applying(option, to: draft) else { return }
        setDraft(updatedDraft, for: sessionID)
    }

    @discardableResult
    func sendMessage(sessionID: String) -> Bool {
        guard let selectedDirectory else { return false }
        let draft = drafts[sessionID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return false }

        reconcileModelSelection(for: sessionID)
        reconcileAgentSelection(for: sessionID)
        let selectedAgent = selectedAgentBySession[sessionID]
        let selectedModel = selectedModelBySession[sessionID]
        let selectedVariant = selectedThinkingLevel(for: sessionID) == Self.defaultThinkingLevel
            ? nil
            : selectedThinkingLevel(for: sessionID)

        if let command = CommandInvocation(draft: draft) {
            setDraft("", for: sessionID)

            if handleLocalSlashCommand(command, sessionID: sessionID) {
                return true
            }

            Task {
                do {
                    logger.notice(
                        "Execute slash command started directory=\(selectedDirectory, privacy: .public) sessionID=\(sessionID, privacy: .public) command=\(command.name, privacy: .public) argsBytes=\(command.arguments.utf8.count, privacy: .public)"
                    )
                    let workspaceService = workspaceServiceProvider(serverURL)
                    _ = try await workspaceService.executeCommand(
                        directory: selectedDirectory,
                        sessionID: sessionID,
                        command: command.name,
                        arguments: command.arguments,
                        agent: selectedAgent,
                        model: selectedModel
                    )
                    logger.notice(
                        "Execute slash command completed directory=\(selectedDirectory, privacy: .public) sessionID=\(sessionID, privacy: .public) command=\(command.name, privacy: .public)"
                    )
                    guard let workspaceConnection else { return }
                    let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                    await coordinator.refreshMessages(sessionID: sessionID)
                } catch {
                    setDraft(draft, for: sessionID)
                    logger.error("Execute slash command failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    errorMessage = error.localizedDescription
                }
            }

            return true
        }

        setDraft("", for: sessionID)

        Task {
            do {
                logger.notice(
                    "Send message started directory=\(selectedDirectory, privacy: .public) sessionID=\(sessionID, privacy: .public) textBytes=\(draft.utf8.count, privacy: .public)"
                )
                let workspaceService = workspaceServiceProvider(serverURL)
                try await workspaceService.sendMessage(
                    directory: selectedDirectory,
                    sessionID: sessionID,
                    text: draft,
                    agent: selectedAgent,
                    model: selectedModel,
                    variant: selectedVariant
                )
                logger.notice(
                    "Send message request completed directory=\(selectedDirectory, privacy: .public) sessionID=\(sessionID, privacy: .public)"
                )
                guard let workspaceConnection else { return }
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await coordinator.refreshMessages(sessionID: sessionID)
                logger.notice(
                    "Send message forced refresh completed directory=\(selectedDirectory, privacy: .public) sessionID=\(sessionID, privacy: .public)"
                )
            } catch {
                setDraft(draft, for: sessionID)
                logger.error("Send failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }

        return true
    }

    func setDraft(_ draft: String, for sessionID: String) {
        var updatedDrafts = drafts
        updatedDrafts[sessionID] = draft
        drafts = updatedDrafts
    }

    func answerPermission(_ request: PermissionRequest, reply: PermissionReply) {
        guard let selectedDirectory else { return }
        dismissedPermissionRequestIDs.insert(request.id)
        focusSession(request.sessionID, focusPrompt: true)
        guard let workspaceConnection else {
            dismissedPermissionRequestIDs.remove(request.id)
            return
        }
        Task {
            do {
                let workspaceService = workspaceServiceProvider(serverURL)
                try await workspaceService.replyToPermission(directory: selectedDirectory, requestID: request.id, reply: reply)
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await coordinator.refreshInteractions(sessionID: request.sessionID)
                await coordinator.refreshStatus(sessionID: request.sessionID)
                await coordinator.refreshMessages(sessionID: request.sessionID)
            } catch {
                dismissedPermissionRequestIDs.remove(request.id)
                errorMessage = error.localizedDescription
            }
        }
    }

    func answerQuestion(_ request: QuestionRequest, answers: [[String]]) {
        guard let selectedDirectory else { return }
        dismissedQuestionRequestIDs.insert(request.id)
        Task {
            do {
                let workspaceService = workspaceServiceProvider(serverURL)
                try await workspaceService.replyToQuestion(directory: selectedDirectory, requestID: request.id, answers: answers)
                guard let workspaceConnection else { return }
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await coordinator.refreshInteractions(sessionID: request.sessionID)
            } catch {
                dismissedQuestionRequestIDs.remove(request.id)
                errorMessage = error.localizedDescription
            }
        }
    }

    func rejectQuestion(_ request: QuestionRequest) {
        guard let selectedDirectory else { return }
        dismissedQuestionRequestIDs.insert(request.id)
        Task {
            do {
                let workspaceService = workspaceServiceProvider(serverURL)
                try await workspaceService.rejectQuestion(directory: selectedDirectory, requestID: request.id)
                guard let workspaceConnection else { return }
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await coordinator.refreshInteractions(sessionID: request.sessionID)
            } catch {
                dismissedQuestionRequestIDs.remove(request.id)
                errorMessage = error.localizedDescription
            }
        }
    }

    func questionForSession(_ sessionID: String) -> [QuestionRequest] {
        (liveStore?.existingSessionState(for: sessionID)?.questions ?? []).filter { request in
            !dismissedQuestionRequestIDs.contains(request.id)
        }
    }

    func isQuestionDismissed(_ request: QuestionRequest) -> Bool {
        dismissedQuestionRequestIDs.contains(request.id)
    }

    func permissionForSession(_ sessionID: String) -> [PermissionRequest] {
        var seenKeys = Set<PermissionPresentationKey>()
        return (liveStore?.existingSessionState(for: sessionID)?.permissions ?? []).filter { request in
            guard !dismissedPermissionRequestIDs.contains(request.id) else { return false }
            let key = PermissionPresentationKey(request: request)
            return seenKeys.insert(key).inserted
        }
    }

    func isPermissionDismissed(_ request: PermissionRequest) -> Bool {
        dismissedPermissionRequestIDs.contains(request.id)
    }

    func sessionIndicator(for sessionID: String) -> SessionIndicator {
        liveStore?.sessionDisplay(for: sessionID)?.indicator ?? SessionIndicator.resolve(status: nil, hasPendingPermission: false)
    }

    private func syncOpenSessions() async {
        guard let workspaceConnection else { return }
        let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
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
        logger.notice(
            "Reloaded snapshot directory=\((resolvedDirectory ?? loadedSnapshot.selectedDirectory ?? "nil"), privacy: .public) sessions=\(loadedSnapshot.sessions.count, privacy: .public) messageSessions=\(loadedSnapshot.messagesBySession.count, privacy: .public) messages=\(totalMessages, privacy: .public) focusedSession=\(focusedSession, privacy: .public) focusedMessages=\(focusedMessageCount, privacy: .public) loadMS=\(loadMS, privacy: .public) publishMS=\(publishMS, privacy: .public) totalMS=\(totalMS, privacy: .public)"
        )
    }

    private func durationMilliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000 + Int64(components.attoseconds / 1_000_000_000_000_000)
    }

    func bindLiveStore(_ liveStore: WorkspaceLiveStore) {
        PerformanceInstrumentation.log(
            "workspace-bind-live-store directory=\(liveStore.directory) currentSessions=\(liveStore.sessions.count)"
        )
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

    private func recentAgentID(for sessionID: String) -> String? {
        messagesBySession[sessionID, default: []]
            .reversed()
            .compactMap { agentIdentifier(from: $0.info.agent) }
            .first
    }

    private func reconcileModelSelections() {
        for session in sessions {
            reconcileAgentSelection(for: session.id)
            reconcileModelSelection(for: session.id)
        }
    }

    private func reconcileAgentSelection(for sessionID: String) {
        let options = agentOptions(for: sessionID)

        guard !options.isEmpty else {
            selectedAgentBySession.removeValue(forKey: sessionID)
            return
        }

        if let selected = selectedAgentBySession[sessionID], options.contains(where: { $0.id == selected }) {
            return
        }

        if let recent = recentAgentID(for: sessionID), options.contains(where: { $0.id == recent }) {
            selectedAgentBySession[sessionID] = recent
            return
        }

        selectedAgentBySession[sessionID] = options.first?.id
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

        if let preferredDefaultModelReference,
           let option = options.first(where: { $0.reference == preferredDefaultModelReference }) {
            return option
        }

        if let option = options.first(where: \.isServerDefault) {
            return option
        }

        return options.first
    }

    private func buildModelOptions(recentModel: ModelReference?) -> [ModelOption] {
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
                        let reference = ModelReference(providerID: provider.id, modelID: model.id)
                        return ModelOption(
                            providerID: provider.id,
                            providerName: provider.name ?? provider.id,
                            modelID: model.id,
                            modelName: model.name,
                            supportsReasoning: model.capabilities?.reasoning == true && !thinkingLevels.isEmpty,
                            thinkingLevels: thinkingLevels,
                            isServerDefault: modelCatalog.defaultModels[provider.id] == model.id,
                            isPreferredDefault: preferredDefaultModelReference == reference,
                            isRecent: recentModel == reference
                        )
                    }
            }
            .sorted { lhs, rhs in
                if lhs.isRecent != rhs.isRecent { return lhs.isRecent }
                if lhs.isPreferredDefault != rhs.isPreferredDefault { return lhs.isPreferredDefault }
                if lhs.isServerDefault != rhs.isServerDefault { return lhs.isServerDefault }
                if lhs.providerName != rhs.providerName {
                    return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
                }
                return lhs.modelName.localizedCaseInsensitiveCompare(rhs.modelName) == .orderedAscending
            }
    }

    private func buildAgentOptions(recentAgentID: String?) -> [AgentOption] {
        agentCatalog.agents
            .filter { !$0.hidden }
            .map { definition in
                AgentOption(
                    id: definition.id,
                    name: definition.displayName,
                    description: definition.description,
                    isRecent: recentAgentID == definition.id
                )
            }
            .sorted { lhs, rhs in
                if lhs.isRecent != rhs.isRecent { return lhs.isRecent }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func buildCommandOptions() -> [CommandOption] {
        let remoteOptions = commandCatalog.commands.map { definition in
            CommandOption(
                id: definition.id,
                name: definition.name,
                description: definition.description
            )
        }

        var optionsBySlashName: [String: CommandOption] = [:]
        for option in Self.localCommandOptions + remoteOptions {
            let key = option.slashName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if optionsBySlashName[key] == nil {
                optionsBySlashName[key] = option
            }
        }

        return optionsBySlashName.values
            .sorted { lhs, rhs in
                lhs.slashName.localizedCaseInsensitiveCompare(rhs.slashName) == .orderedAscending
            }
    }

    private func handleLocalSlashCommand(_ command: CommandInvocation, sessionID: String) -> Bool {
        guard let selectedDirectory else { return false }

        switch command.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "new":
            logger.notice(
                "Execute local slash command directory=\(selectedDirectory, privacy: .public) sessionID=\(sessionID, privacy: .public) command=new"
            )
            createSession()
            return true
        case "close":
            logger.notice(
                "Execute local slash command directory=\(selectedDirectory, privacy: .public) sessionID=\(sessionID, privacy: .public) command=close"
            )
            closeSession(sessionID)
            return true
        case "archive":
            logger.notice(
                "Execute local slash command directory=\(selectedDirectory, privacy: .public) sessionID=\(sessionID, privacy: .public) command=archive"
            )
            archiveSession(sessionID)
            return true
        default:
            return false
        }
    }

    private func agentIdentifier(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func sessionIDToFocusAfterClosingSession(at closingIndex: Int?) -> String? {
        guard let closingIndex else { return nil }

        if openSessionIDs.indices.contains(closingIndex) {
            return openSessionIDs[closingIndex]
        }

        let leftIndex = closingIndex - 1
        guard openSessionIDs.indices.contains(leftIndex) else { return nil }
        return openSessionIDs[leftIndex]
    }

    private func requestPromptFocus(for sessionID: String) {
        promptFocusRequest = SessionPromptFocusRequest(sessionID: sessionID)
    }

    private func clearWorkspaceSelection() {
        selectedDirectory = nil
        openSessionIDs = []
        focusedSessionID = nil
        liveStore = nil
        paneWidths = [:]
        commandCatalog = CommandCatalog(commands: [])
        agentCatalog = AgentCatalog(agents: [])
        modelCatalog = ModelCatalog(providers: [], defaultModels: [:], connectedProviderIDs: [])
        preferredDefaultModelReference = preferredDefaultModelReferenceProvider()
        selectedAgentBySession = [:]
        selectedModelBySession = [:]
        selectedThinkingLevelBySession = [:]
        dismissedPermissionRequestIDs = []
        dismissedQuestionRequestIDs = []
    }

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
