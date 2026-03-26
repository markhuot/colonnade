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
    @Published var serverURL: URL {
        didSet {
            guard oldValue != serverURL else { return }
            recentProjectDirectories = RecentProjectDirectoriesPreferences.load(
                for: serverURL,
                from: recentProjectDirectoriesDefaults
            )
        }
    }
    @Published var openSessionIDs: [String] = []
    @Published var focusedSessionID: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var launchStage: LaunchStage = .checkingLocalServer
    @Published var remoteServerURLText: String = ""
    @Published var remoteDirectoryText: String = ""
    @Published var remoteProjectSuggestions: [String] = []
    @Published private(set) var recentRemoteConnections: [String] = []
    @Published private(set) var recentProjectDirectories: [String] = []
    @Published private(set) var isStartingLocalServer = false
    @Published private(set) var isValidatingRemoteServer = false
    @Published private(set) var promptFocusRequest: SessionPromptFocusRequest?
    @Published private(set) var sessionCenterRequest: SessionCenterRequest?
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
    private let recentRemoteConnectionsDefaults: UserDefaults
    private let recentProjectDirectoriesDefaults: UserDefaults
    private let persistsWorkspacePaneState: Bool
    private let restoresLastSelectedDirectory: Bool
    private let supportsLocalServer: Bool
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
    private var cachedBaseModelOptionsKey: BaseModelOptionsCacheKey?
    private var cachedBaseModelOptions: [ModelOption] = []
    private var cachedModelOptionsBySession: [String: SessionModelOptionsCacheEntry] = [:]
    private var shouldResyncOpenSessionsOnForeground = false

    let defaultPaneWidth: CGFloat = 720
    let minPaneWidth: CGFloat = 360
    let maxPaneWidth: CGFloat = 960

    private struct BaseModelOptionsCacheKey: Hashable {
        let modelCatalog: ModelCatalog
        let preferredDefaultModelReference: ModelReference?
    }

    private struct SessionModelOptionsCacheEntry {
        let baseKey: BaseModelOptionsCacheKey
        let recentModel: ModelReference?
        let options: [ModelOption]
    }

    init(
        client: (any OpenCodeAPIClientProtocol)? = nil,
        workspaceService: (any WorkspaceServiceProtocol)? = nil,
        repository: PersistenceRepository = .shared,
        syncRegistry: any WorkspaceSyncRegistryProtocol = WorkspaceSyncRegistry.shared,
        persistsWorkspacePaneState: Bool = true,
        restoresLastSelectedDirectory: Bool = false,
        supportsLocalServer: Bool = true,
        initialServerURL: URL = OpenCodeAppModel.defaultServerURL,
        initialDirectory: String? = nil,
        initialOpenSessionIDs: [String] = [],
        localServerStarter: (@Sendable (String) throws -> LocalServerLaunchHandle)? = nil,
        localServerExecutablePathProvider: (@Sendable () -> String)? = nil,
        apiClientProviderOverride: (@Sendable (URL) -> any OpenCodeAPIClientProtocol)? = nil,
        workspaceServiceProviderOverride: (@Sendable (URL) -> any WorkspaceServiceProtocol)? = nil,
        preferredDefaultModelReferenceProvider: @escaping () -> ModelReference? = { nil },
        preferredDefaultModelReferenceSetter: @escaping (ModelReference?) -> Void = { _ in },
        recentRemoteConnectionsDefaults: UserDefaults = .standard,
        recentProjectDirectoriesDefaults: UserDefaults = .standard,
        directoryChooser: @escaping @MainActor () -> Void = {},
        serverWaiter: (@Sendable (URL, Duration) async -> ServerStartupWaitResult)? = nil
    ) {
        self.repository = repository
        self.syncRegistry = syncRegistry
        self.persistsWorkspacePaneState = persistsWorkspacePaneState
        self.restoresLastSelectedDirectory = restoresLastSelectedDirectory
        self.supportsLocalServer = supportsLocalServer
        self.recentRemoteConnectionsDefaults = recentRemoteConnectionsDefaults
        self.recentProjectDirectoriesDefaults = recentProjectDirectoriesDefaults
        self.initialServerURL = initialServerURL
        self.serverURL = initialServerURL
        self.initialDirectory = initialDirectory
        self.initialOpenSessionIDs = initialOpenSessionIDs
        recentRemoteConnections = RecentRemoteConnectionsPreferences.load(from: recentRemoteConnectionsDefaults)
        recentProjectDirectories = RecentProjectDirectoriesPreferences.load(
            for: initialServerURL,
            from: recentProjectDirectoriesDefaults
        )

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
        liveStore?.visibleSessions ?? []
    }

    var projectName: String? {
        selectedDirectory.map { ($0 as NSString).lastPathComponent }
    }

    var isUsingLocalServer: Bool {
        serverURL == Self.defaultServerURL
    }

    var supportsLocalServerSelection: Bool {
        supportsLocalServer
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

    private func messages(for sessionID: String) -> [MessageEnvelope] {
        liveStore?.existingSessionState(for: sessionID)?.messages ?? []
    }

    func availableModelOptions() -> [ModelOption] {
        let baseKey = BaseModelOptionsCacheKey(
            modelCatalog: modelCatalog,
            preferredDefaultModelReference: preferredDefaultModelReference
        )
        return buildModelOptions(recentModel: nil, baseKey: baseKey)
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
            launchStage = connectedLaunchStage(for: bootstrapConnection.serverURL)
            await load(directory: bootstrapConnection.directory)
            return
        }

        if restoresLastSelectedDirectory {
            let bootstrapDirectory = await repository.loadLastSelectedDirectory()
            if let bootstrapDirectory,
               FileManager.default.fileExists(atPath: bootstrapDirectory) {
                launchStage = connectedLaunchStage(for: initialServerURL)
                Task {
                    await load(directory: bootstrapDirectory)
                }
                return
            }
        }

        launchStage = initialLaunchStage()
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
            guard supportsLocalServer else { return false }
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

    func returnToProjectChooser() {
        let previousDirectory = selectedDirectory
        let previousLaunchStage = launchStage
        clearWorkspaceSelection()

        if let previousDirectory, previousLaunchStage == .remoteDirectoryEntry {
            remoteDirectoryText = previousDirectory
        }

        launchStage = connectedLaunchStage(for: serverURL)
    }

    func openLocalDirectory() {
        guard supportsLocalServer else {
            errorMessage = "Local workspaces aren't available on iOS. Connect to a remote opencode server instead."
            return
        }
        guard !isStartingLocalServer else { return }

        Task {
            isStartingLocalServer = true
            errorMessage = nil

            do {
                try await startLocalServerIfNeeded()
                serverURL = Self.defaultServerURL
                chooseDirectory()
            } catch {
                errorMessage = error.localizedDescription
            }

            isStartingLocalServer = false
        }
    }

    func connectToLocalDirectory(_ directory: String) {
        guard supportsLocalServer else {
            errorMessage = "Local workspaces aren't available on iOS. Connect to a remote opencode server instead."
            return
        }
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDirectory.isEmpty else { return }
        guard !isStartingLocalServer else { return }

        Task {
            isStartingLocalServer = true
            errorMessage = nil

            do {
                try await startLocalServerIfNeeded()
                serverURL = Self.defaultServerURL
                await load(directory: trimmedDirectory)
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
                recentRemoteConnections = RecentRemoteConnectionsPreferences.remember(
                    connection.normalizedURLText,
                    defaults: recentRemoteConnectionsDefaults
                )
                recentProjectDirectories = RecentProjectDirectoriesPreferences.load(
                    for: connection.serverURL,
                    from: recentProjectDirectoriesDefaults
                )
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

    func connectToRecentRemoteServer(_ urlText: String) {
        remoteServerURLText = urlText
        connectToRemoteServer()
    }

    func connectToRecentProjectDirectory(_ directory: String) {
        if serverURL == Self.defaultServerURL {
            connectToLocalDirectory(directory)
            return
        }

        remoteDirectoryText = directory
        connectToRemoteDirectory()
    }

    func remoteDirectorySuggestionOptions(limit: Int = 8) -> [CommandOption] {
        PathAutocomplete.suggestions(for: remoteDirectoryText, paths: remoteProjectSuggestions, limit: limit)
            .map { path in
                CommandOption(id: "remote-project:\(path)", name: path, description: nil)
            }
    }

    func applyRemoteDirectorySuggestion(_ option: CommandOption) {
        remoteDirectoryText = option.name
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
        launchStage = initialLaunchStage()
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

        DebugLogging.info(logger, "Loading directory: \(trimmedDirectory) server=\(self.serverURL.absoluteString)")
        selectedDirectory = trimmedDirectory
        isLoading = true
        errorMessage = nil
        shouldResyncOpenSessionsOnForeground = false

        let liveStore = await syncRegistry.store(for: connection)

        bindLiveStore(liveStore)

        do {
            let preferredSnapshotSessionIDs = Set(initialOpenSessionIDs)
                .union(openSessionIDs)
                .union(snapshot.paneStates.values.filter { !$0.isHidden }.map(\.sessionID))
            let persistedSnapshot = await repository.loadSnapshot(
                directory: trimmedDirectory,
                preferredMessageSessionIDs: preferredSnapshotSessionIDs,
                decodeOnlyPreferredSessions: true
            )
            snapshot = persistedSnapshot

            liveStore.replacePaneStates(persistedSnapshot.paneStates)
            liveStore.applyPersistenceSnapshot(persistedSnapshot)
            applyLoadedWorkspaceState(for: trimmedDirectory)

            if persistsWorkspacePaneState {
                Task {
                    await self.repository.selectWorkspace(directory: trimmedDirectory)
                }
            }

            let hasCachedWorkspaceContent = !persistedSnapshot.sessions.isEmpty

            if hasCachedWorkspaceContent {
                isLoading = false
                launchStage = connectedLaunchStage(for: serverURL)
                rememberRecentProjectDirectory(trimmedDirectory)
                Task {
                    let loadedModelContextLimits = await refreshModelMetadata(
                        loadID: loadID,
                        connection: connection,
                        workspaceService: workspaceService,
                        liveStore: liveStore
                    )
                    guard isCurrentLoad(loadID, for: connection), self.liveStore === liveStore else { return }
                    reconcileModelSelections()

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
            rememberRecentProjectDirectory(trimmedDirectory)
            launchStage = connectedLaunchStage(for: serverURL)
        } catch {
            logger.error("Load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            selectedDirectory = previousDirectory
            snapshot = previousSnapshot
            self.liveStore = previousLiveStore
        }

        isLoading = false
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
        }

        if reportErrorsToUser {
            errorMessage = nil
        }
    }

    private func refreshModelMetadata(
        loadID: Int,
        connection: WorkspaceConnection,
        workspaceService: any WorkspaceServiceProtocol,
        liveStore: WorkspaceLiveStore
    ) async -> [ModelContextKey: Int] {
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
            invalidateModelOptionCache()
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

    func noteAppDidEnterBackground() {
        shouldResyncOpenSessionsOnForeground = workspaceConnection != nil && !openSessionIDs.isEmpty
    }

    func noteAppDidBecomeActive() {
        guard shouldResyncOpenSessionsOnForeground else { return }
        shouldResyncOpenSessionsOnForeground = false

        let sessionIDs = openSessionIDs
        guard !sessionIDs.isEmpty else { return }

        Task {
            await syncOpenSessions()
            guard let workspaceConnection else { return }
            let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
            await refreshOpenSessions(sessionIDs, using: coordinator)
        }
    }

    private func shouldRefreshMessages(for sessionID: String) -> Bool {
        guard let session = liveStore?.sessionDisplay(for: sessionID) else { return true }
        return session.hydratedMessageUpdatedAtMS != session.updatedAtMS
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
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await coordinator.refreshTodos(sessionID: sessionID)
                if shouldRefreshMessages(for: sessionID) {
                    await coordinator.refreshMessages(sessionID: sessionID)
                }
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
                DebugLogging.notice(logger, "Create session started directory=\(selectedDirectory)")
                let workspaceService = workspaceServiceProvider(serverURL)
                let session = try await workspaceService.createSession(directory: selectedDirectory, title: nil, parentID: nil)
                DebugLogging.notice(logger, "Create session created directory=\(selectedDirectory) sessionID=\(session.id)")
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
                DebugLogging.notice(logger,
                    "Create session applied local lifecycle directory=\(selectedDirectory) sessionID=\(session.id) visibleSessions=\(self.visibleSessions.count)"
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

    func renameSession(_ sessionID: String, title: String) {
        guard let selectedDirectory else { return }
        guard let existingSession = sessions.first(where: { $0.id == sessionID }) else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, trimmedTitle != existingSession.title else { return }

        Task {
            do {
                let workspaceService = workspaceServiceProvider(serverURL)
                let session = try await workspaceService.renameSession(directory: selectedDirectory, sessionID: sessionID, title: trimmedTitle)
                await repository.applySessionLifecycle(
                    directory: selectedDirectory,
                    session: session,
                    lifecycle: .updated,
                    modelContextLimits: modelContextLimits
                )
                liveStore?.applySessionLifecycle(session: session, lifecycle: .updated)
            } catch {
                logger.error("Rename session failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
        return cachedModelOptions(for: sessionID, recentModel: recentModel)
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
        invalidateModelOptionCache()
        reconcileModelSelections()
    }

    func setSelectedThinkingLevel(_ level: String, for sessionID: String) {
        guard let option = selectedModelOption(for: sessionID) else { return }
        guard level == Self.defaultThinkingLevel || option.thinkingLevels.contains(level) else { return }
        selectedThinkingLevelBySession[sessionID] = level
    }

    func slashCommandSuggestions(for draft: String, sessionID: String, cursorLocation: Int = 0) -> [CommandOption] {
        guard focusedSessionID == sessionID || openSessionIDs.contains(sessionID) else { return [] }
        return CommandAutocomplete.suggestions(for: draft, cursorLocation: cursorLocation, commands: availableCommandOptions())
    }

    func applyingSlashCommandSuggestion(_ option: CommandOption, to draft: String, sessionID: String) -> String? {
        guard focusedSessionID == sessionID || openSessionIDs.contains(sessionID) else { return nil }
        return CommandAutocomplete.applying(option, to: draft)
    }

    @discardableResult
    func sendMessage(sessionID: String, text: String) -> Bool {
        guard let selectedDirectory else { return false }
        let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return false }

        reconcileModelSelection(for: sessionID)
        reconcileAgentSelection(for: sessionID)
        let selectedAgent = selectedAgentBySession[sessionID]
        let selectedModel = selectedModelBySession[sessionID]
        let selectedVariant = selectedThinkingLevel(for: sessionID) == Self.defaultThinkingLevel
            ? nil
            : selectedThinkingLevel(for: sessionID)

        if let command = CommandInvocation(draft: draft) {
            if handleLocalSlashCommand(command, sessionID: sessionID) {
                return true
            }

            Task {
                do {
                    DebugLogging.notice(logger,
                        "Execute slash command started directory=\(selectedDirectory) sessionID=\(sessionID) command=\(command.name) argsBytes=\(command.arguments.utf8.count)"
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
                    DebugLogging.notice(logger,
                        "Execute slash command completed directory=\(selectedDirectory) sessionID=\(sessionID) command=\(command.name)"
                    )
                    guard let workspaceConnection else { return }
                    let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                    await coordinator.refreshMessages(sessionID: sessionID)
                } catch {
                    logger.error("Execute slash command failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    errorMessage = error.localizedDescription
                }
            }

            return true
        }

        Task {
            do {
                DebugLogging.notice(logger,
                    "Send message started directory=\(selectedDirectory) sessionID=\(sessionID) textBytes=\(draft.utf8.count)"
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
                DebugLogging.notice(logger,
                    "Send message request completed directory=\(selectedDirectory) sessionID=\(sessionID)"
                )
                guard let workspaceConnection else { return }
                let coordinator = await syncRegistry.coordinator(for: workspaceConnection)
                await coordinator.refreshMessages(sessionID: sessionID)
                DebugLogging.notice(logger,
                    "Send message forced refresh completed directory=\(selectedDirectory) sessionID=\(sessionID)"
                )
            } catch {
                logger.error("Send failed for \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }

        return true
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

    private func refreshOpenSessions(_ sessionIDs: [String], using coordinator: any WorkspaceSyncCoordinating) async {
        for sessionID in sessionIDs {
            await coordinator.refreshTodos(sessionID: sessionID)
            if shouldRefreshMessages(for: sessionID) {
                await coordinator.refreshMessages(sessionID: sessionID)
            }
        }
    }

    private func initialLaunchStage() -> LaunchStage {
        supportsLocalServer ? .chooseServerMode : .remoteServerEntry
    }

    private func connectedLaunchStage(for serverURL: URL) -> LaunchStage {
        if serverURL == Self.defaultServerURL, supportsLocalServer {
            return .localFolderSelection
        }

        return .remoteDirectoryEntry
    }

    private func startLocalServerIfNeeded() async throws {
        #if os(iOS)
            localServerHandle = nil
        #else
            localServerHandle = try await serverController.startLocalServerIfNeeded(at: Self.defaultServerURL) ?? localServerHandle
        #endif
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
        DebugLogging.notice(logger,
            "Reloaded snapshot directory=\(resolvedDirectory ?? loadedSnapshot.selectedDirectory ?? "nil") sessions=\(loadedSnapshot.sessions.count) messageSessions=\(loadedSnapshot.messagesBySession.count) messages=\(totalMessages) focusedSession=\(focusedSession) focusedMessages=\(focusedMessageCount) loadMS=\(loadMS) publishMS=\(publishMS) totalMS=\(totalMS)"
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
        messages(for: sessionID)
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
        messages(for: sessionID)
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

    private func cachedModelOptions(for sessionID: String, recentModel: ModelReference?) -> [ModelOption] {
        let baseKey = BaseModelOptionsCacheKey(
            modelCatalog: modelCatalog,
            preferredDefaultModelReference: preferredDefaultModelReference
        )

        if let entry = cachedModelOptionsBySession[sessionID],
           entry.baseKey == baseKey,
           entry.recentModel == recentModel {
            return entry.options
        }

        let options = buildModelOptions(recentModel: recentModel, baseKey: baseKey)
        cachedModelOptionsBySession[sessionID] = SessionModelOptionsCacheEntry(
            baseKey: baseKey,
            recentModel: recentModel,
            options: options
        )
        return options
    }

    private func invalidateModelOptionCache() {
        cachedBaseModelOptionsKey = nil
        cachedBaseModelOptions = []
        cachedModelOptionsBySession = [:]
    }

    private func buildModelOptions(recentModel: ModelReference?, baseKey: BaseModelOptionsCacheKey) -> [ModelOption] {
        let baseOptions = cachedBaseModelOptions(for: baseKey)
            .map { option in
                ModelOption(
                    providerID: option.providerID,
                    providerName: option.providerName,
                    modelID: option.modelID,
                    modelName: option.modelName,
                    supportsReasoning: option.supportsReasoning,
                    thinkingLevels: option.thinkingLevels,
                    isServerDefault: option.isServerDefault,
                    isPreferredDefault: option.isPreferredDefault,
                    isRecent: recentModel == option.reference
                )
            }

        return sortModelOptions(baseOptions)
    }

    private func cachedBaseModelOptions(for key: BaseModelOptionsCacheKey) -> [ModelOption] {
        if cachedBaseModelOptionsKey == key {
            return cachedBaseModelOptions
        }

        let connectedProviderIDs = Set(key.modelCatalog.connectedProviderIDs)
        let options = key.modelCatalog.providers
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
                            isServerDefault: key.modelCatalog.defaultModels[provider.id] == model.id,
                            isPreferredDefault: key.preferredDefaultModelReference == reference,
                            isRecent: false
                        )
                    }
            }

        cachedBaseModelOptionsKey = key
        cachedBaseModelOptions = sortModelOptions(options)
        return cachedBaseModelOptions
    }

    private func sortModelOptions(_ options: [ModelOption]) -> [ModelOption] {
        options.sorted { lhs, rhs in
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
            DebugLogging.notice(logger,
                "Execute local slash command directory=\(selectedDirectory) sessionID=\(sessionID) command=new"
            )
            createSession()
            return true
        case "close":
            DebugLogging.notice(logger,
                "Execute local slash command directory=\(selectedDirectory) sessionID=\(sessionID) command=close"
            )
            closeSession(sessionID)
            return true
        case "archive":
            DebugLogging.notice(logger,
                "Execute local slash command directory=\(selectedDirectory) sessionID=\(sessionID) command=archive"
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

    func requestSessionCenter(for sessionID: String) {
        sessionCenterRequest = SessionCenterRequest(sessionID: sessionID)
    }

    func clearSessionCenterRequest(_ requestID: UUID) {
        guard sessionCenterRequest?.id == requestID else { return }
        sessionCenterRequest = nil
    }

    private func clearWorkspaceSelection() {
        shouldResyncOpenSessionsOnForeground = false
        selectedDirectory = nil
        openSessionIDs = []
        focusedSessionID = nil
        sessionCenterRequest = nil
        liveStore = nil
        paneWidths = [:]
        commandCatalog = CommandCatalog(commands: [])
        agentCatalog = AgentCatalog(agents: [])
        invalidateModelOptionCache()
        modelCatalog = ModelCatalog(providers: [], defaultModels: [:], connectedProviderIDs: [])
        preferredDefaultModelReference = preferredDefaultModelReferenceProvider()
        selectedAgentBySession = [:]
        selectedModelBySession = [:]
        selectedThinkingLevelBySession = [:]
        dismissedPermissionRequestIDs = []
        dismissedQuestionRequestIDs = []
    }

    private func rememberRecentProjectDirectory(_ directory: String) {
        recentProjectDirectories = RecentProjectDirectoriesPreferences.remember(
            directory,
            for: serverURL,
            defaults: recentProjectDirectoriesDefaults
        )
    }

}

struct SessionPromptFocusRequest: Equatable {
    let id = UUID()
    let sessionID: String
}

struct SessionCenterRequest: Equatable {
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
