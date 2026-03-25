import AppKit
import Combine
import SwiftUI

struct WorkspaceCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var commandCenter = WorkspaceCommandCenter.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: "workspace-root")
            }
            .keyboardShortcut("n")

            Button("New Session") {
                commandCenter.createSession()
            }
            .keyboardShortcut("t")
            .disabled(!commandCenter.canCreateSession)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Constants {
        static let thinkingMenuItemTag = 9_001
        static let viewSeparatorTag = 9_002
        static let previousPaneMenuItemTag = 9_003
        static let nextPaneMenuItemTag = 9_004
        static let workspaceMenuTag = 9_010
        static let resyncMenuItemTag = 9_011
        static let messagesMenuTag = 9_020
        static let refreshMessagesMenuItemTag = 9_021
        static let fileNewWindowMenuItemTag = 9_030
        static let fileNewSessionMenuItemTag = 9_031
        static let fileCloseSessionMenuItemTag = 9_032
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.installCustomMenus()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.installCustomMenus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LocalServerLauncher.shutdownAll()
    }

    @objc private func toggleThinkingVisibility() {
        ThinkingVisibilityPreferences.setShowsThinking(!showsThinking)
        updateThinkingMenuItemTitle()
    }

    @objc private func focusPreviousPane() {
        WorkspaceCommandCenter.shared.focusPreviousPane()
    }

    @objc private func focusNextPane() {
        WorkspaceCommandCenter.shared.focusNextPane()
    }

    @objc private func refreshFocusedMessages() {
        WorkspaceCommandCenter.shared.refreshFocusedSession()
    }

    @objc private func resyncSessions() {
        WorkspaceCommandCenter.shared.refreshAll()
    }

    @objc private func createSessionFromMenu() {
        WorkspaceCommandCenter.shared.createSession()
    }

    @objc private func closeSessionFromMenu() {
        WorkspaceCommandCenter.shared.closeFocusedSession()
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
        case Constants.fileNewSessionMenuItemTag:
            return WorkspaceCommandCenter.shared.canCreateSession
        case Constants.fileCloseSessionMenuItemTag:
            return WorkspaceCommandCenter.shared.canCloseFocusedSession
        case Constants.thinkingMenuItemTag:
            menuItem.title = thinkingMenuItemTitle
            return true
        case Constants.previousPaneMenuItemTag:
            return WorkspaceCommandCenter.shared.canFocusPreviousPane
        case Constants.nextPaneMenuItemTag:
            return WorkspaceCommandCenter.shared.canFocusNextPane
        case Constants.resyncMenuItemTag:
            return WorkspaceCommandCenter.shared.canRefresh
        case Constants.refreshMessagesMenuItemTag:
            return WorkspaceCommandCenter.shared.canRefreshFocusedSession
        default:
            return true
        }
    }

    private func installCustomMenus() {
        installFileMenuItems()
        installViewMenuItems()
        installWorkspaceMenuItems()
        installMessagesMenuItems()
    }

    private func installFileMenuItems() {
        guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu else { return }
        fileMenu.delegate = self

        if let closeWindowItem = fileMenu.items.first(where: { item in
            item.action == #selector(NSWindow.performClose(_:))
        }) {
            closeWindowItem.keyEquivalent = ""
            closeWindowItem.keyEquivalentModifierMask = []
        }

        if let windowItem = fileMenu.item(withTag: Constants.fileNewWindowMenuItemTag),
           let sessionItem = fileMenu.item(withTag: Constants.fileNewSessionMenuItemTag),
           let closeSessionItem = fileMenu.item(withTag: Constants.fileCloseSessionMenuItemTag) {
            windowItem.title = "New Window"
            windowItem.keyEquivalent = "n"
            windowItem.keyEquivalentModifierMask = [.command]

            sessionItem.title = "New Session"
            sessionItem.action = #selector(createSessionFromMenu)
            sessionItem.target = self
            sessionItem.keyEquivalent = "t"
            sessionItem.keyEquivalentModifierMask = [.command]

            closeSessionItem.title = "Close Session"
            closeSessionItem.action = #selector(closeSessionFromMenu)
            closeSessionItem.target = self
            closeSessionItem.keyEquivalent = "w"
            closeSessionItem.keyEquivalentModifierMask = [.command]

            if let newMenuIndex = fileMenu.items.firstIndex(where: { $0.title == "New" && $0.submenu != nil }) {
                fileMenu.removeItem(at: newMenuIndex)
            }
            return
        }

        guard let newMenuIndex = fileMenu.items.firstIndex(where: { $0.title == "New" && $0.submenu != nil }),
              let newSubmenu = fileMenu.items[newMenuIndex].submenu else {
            return
        }

        let newMenuItems = newSubmenu.items.filter { !$0.isSeparatorItem }
        guard !newMenuItems.isEmpty else { return }

        let windowTemplate = newMenuItems.first(where: { $0.title.localizedCaseInsensitiveContains("window") })
            ?? newMenuItems.first(where: { !$0.title.localizedCaseInsensitiveContains("session") })
            ?? newMenuItems[0]

        if windowTemplate.menu === newSubmenu {
            newSubmenu.removeItem(windowTemplate)
        }

        fileMenu.removeItem(at: newMenuIndex)

        windowTemplate.title = "New Window"
        windowTemplate.tag = Constants.fileNewWindowMenuItemTag
        windowTemplate.keyEquivalent = "n"
        windowTemplate.keyEquivalentModifierMask = [.command]
        fileMenu.insertItem(windowTemplate, at: newMenuIndex)

        let sessionItem = NSMenuItem(title: "New Session", action: #selector(createSessionFromMenu), keyEquivalent: "t")
        sessionItem.target = self
        sessionItem.tag = Constants.fileNewSessionMenuItemTag
        sessionItem.keyEquivalentModifierMask = [.command]
        fileMenu.insertItem(sessionItem, at: newMenuIndex + 1)

        let closeSessionItem = NSMenuItem(title: "Close Session", action: #selector(closeSessionFromMenu), keyEquivalent: "w")
        closeSessionItem.target = self
        closeSessionItem.tag = Constants.fileCloseSessionMenuItemTag
        closeSessionItem.keyEquivalentModifierMask = [.command]

        let insertionIndex = fileMenu.items.firstIndex(where: { $0.action == #selector(NSWindow.performClose(_:)) }) ?? fileMenu.items.count
        fileMenu.insertItem(closeSessionItem, at: insertionIndex)
    }

    private func installViewMenuItems() {
        guard let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu else { return }
        viewMenu.delegate = self

        removeItems(
            withTags: [
                Constants.thinkingMenuItemTag,
                Constants.viewSeparatorTag,
                Constants.previousPaneMenuItemTag,
                Constants.nextPaneMenuItemTag
            ],
            from: viewMenu
        )

        let thinkingItem = NSMenuItem(title: thinkingMenuItemTitle, action: #selector(toggleThinkingVisibility), keyEquivalent: "")
        thinkingItem.target = self
        thinkingItem.tag = Constants.thinkingMenuItemTag
        thinkingItem.keyEquivalent = "."
        thinkingItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.insertItem(thinkingItem, at: 0)

        let separator = NSMenuItem.separator()
        separator.tag = Constants.viewSeparatorTag
        viewMenu.insertItem(separator, at: 1)

        let previousPaneItem = NSMenuItem(title: "Focus Previous Pane", action: #selector(focusPreviousPane), keyEquivalent: "[")
        previousPaneItem.target = self
        previousPaneItem.tag = Constants.previousPaneMenuItemTag
        previousPaneItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.insertItem(previousPaneItem, at: 2)

        let nextPaneItem = NSMenuItem(title: "Focus Next Pane", action: #selector(focusNextPane), keyEquivalent: "]")
        nextPaneItem.target = self
        nextPaneItem.tag = Constants.nextPaneMenuItemTag
        nextPaneItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.insertItem(nextPaneItem, at: 3)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu.title {
        case "File":
            installFileMenuItems()
        case "View":
            installViewMenuItems()
        case "Workspace":
            installWorkspaceMenuItems()
        case "Messages":
            installMessagesMenuItems()
        default:
            break
        }
    }

    private func installWorkspaceMenuItems() {
        guard let workspaceMenu = ensureTopLevelMenu(title: "Workspace", tag: Constants.workspaceMenuTag, beforeMenuTitled: "Window") else {
            return
        }

        removeItems(withTags: [Constants.resyncMenuItemTag], from: workspaceMenu)

        let resyncItem = NSMenuItem(title: "Resync Sessions", action: #selector(resyncSessions), keyEquivalent: "r")
        resyncItem.target = self
        resyncItem.tag = Constants.resyncMenuItemTag
        workspaceMenu.insertItem(resyncItem, at: 0)
    }

    private func installMessagesMenuItems() {
        guard let messagesMenu = ensureTopLevelMenu(title: "Messages", tag: Constants.messagesMenuTag, beforeMenuTitled: "Window") else {
            return
        }

        removeItems(withTags: [Constants.refreshMessagesMenuItemTag], from: messagesMenu)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFocusedMessages), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.tag = Constants.refreshMessagesMenuItemTag
        refreshItem.keyEquivalentModifierMask = [.command, .shift]
        messagesMenu.insertItem(refreshItem, at: 0)
    }

    private func updateThinkingMenuItemTitle() {
        guard let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu,
              let item = viewMenu.item(withTag: Constants.thinkingMenuItemTag) else { return }

        item.title = thinkingMenuItemTitle
    }

    private func ensureTopLevelMenu(title: String, tag: Int, beforeMenuTitled beforeMenuTitle: String) -> NSMenu? {
        guard let mainMenu = NSApp.mainMenu else { return nil }

        if let existingItem = mainMenu.items.first(where: { $0.tag == tag || $0.title == title }) {
            if existingItem.submenu == nil {
                existingItem.submenu = NSMenu(title: title)
            }
            existingItem.title = title
            existingItem.tag = tag
            return existingItem.submenu
        }

        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.tag = tag
        menuItem.submenu = NSMenu(title: title)

        let insertionIndex = mainMenu.items.firstIndex(where: { $0.title == beforeMenuTitle }) ?? mainMenu.items.count
        mainMenu.insertItem(menuItem, at: insertionIndex)
        return menuItem.submenu
    }

    private func removeItems(withTags tags: [Int], from menu: NSMenu) {
        for tag in tags.reversed() {
            if let item = menu.item(withTag: tag) {
                menu.removeItem(item)
            }
        }
    }

    private var thinkingMenuItemTitle: String {
        showsThinking ? "Hide Thinking" : "Show Thinking"
    }

    private var showsThinking: Bool {
        ThinkingVisibilityPreferences.showsThinking()
    }
}

@MainActor
final class WorkspaceCommandCenter: ObservableObject {
    static let shared = WorkspaceCommandCenter()

    private final class WorkspaceWindowBinding {
        let appState: OpenCodeAppModel
        var windowNumber: Int?
        var cancellables: Set<AnyCancellable> = []

        init(appState: OpenCodeAppModel) {
            self.appState = appState
        }
    }

    @Published private(set) var canCreateSession = false
    @Published private(set) var canRefresh = false
    @Published private(set) var canRefreshFocusedSession = false
    @Published private(set) var canFocusPreviousPane = false
    @Published private(set) var canFocusNextPane = false
    @Published private(set) var canCloseFocusedSession = false

    @Published private(set) var currentConnection: WorkspaceConnection?

    private weak var fallbackAppState: OpenCodeAppModel?
    private var workspaceBindings: [ObjectIdentifier: WorkspaceWindowBinding] = [:]
    private var sessionWindowStates: [String: OpenCodeAppModel] = [:]
    private var sessionWindowsByNumber: [Int: String] = [:]
    private var windowObservationCancellables: Set<AnyCancellable> = []

    var currentWindowNumberProvider: () -> Int? = {
        if let keyWindow = NSApp.keyWindow {
            return keyWindow.windowNumber
        }

        return NSApp.mainWindow?.windowNumber
    }

    var currentWindowProvider: () -> NSWindow? = {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    private init() {
        let notificationCenter = NotificationCenter.default

        notificationCenter.publisher(for: NSWindow.didBecomeKeyNotification)
            .merge(with: notificationCenter.publisher(for: NSWindow.didResignKeyNotification))
            .merge(with: notificationCenter.publisher(for: NSWindow.didBecomeMainNotification))
            .merge(with: notificationCenter.publisher(for: NSWindow.didResignMainNotification))
            .sink { [weak self] _ in
                self?.refreshAvailabilityForCurrentWindow()
            }
            .store(in: &windowObservationCancellables)
    }

    func bind(appState: OpenCodeAppModel) {
        fallbackAppState = appState
        _ = ensureWorkspaceBinding(for: appState)
        refreshAvailabilityForCurrentWindow()
    }

    func bindSessionWindow(appState: OpenCodeAppModel, sessionID: String) {
        sessionWindowStates[sessionID] = appState
        refreshAvailabilityForCurrentWindow()
    }

    func registerWorkspaceWindow(_ window: NSWindow?, appState: OpenCodeAppModel) {
        fallbackAppState = appState
        registerWorkspaceWindowNumber(window?.windowNumber, appState: appState)
    }

    func registerWorkspaceWindowNumber(_ windowNumber: Int?, appState: OpenCodeAppModel) {
        let identifier = ObjectIdentifier(appState)
        let binding = ensureWorkspaceBinding(for: appState)
        binding.windowNumber = windowNumber

        if windowNumber == nil {
            workspaceBindings.removeValue(forKey: identifier)
        }

        refreshAvailabilityForCurrentWindow()
    }

    func registerSessionWindow(_ window: NSWindow?, sessionID: String) {
        if let existingNumber = sessionWindowsByNumber.first(where: { $0.value == sessionID })?.key,
           window?.windowNumber != existingNumber {
            sessionWindowsByNumber.removeValue(forKey: existingNumber)
        }

        if let window {
            sessionWindowsByNumber[window.windowNumber] = sessionID
        } else {
            sessionWindowStates.removeValue(forKey: sessionID)
        }
    }

    func closeFocusedSession() {
        guard let target = closeTarget() else { return }

        switch target {
        case let .workspace(appState, sessionID):
            appState.closeSession(sessionID)
        case let .sessionWindow(appState, sessionID, windowNumber):
            appState.closeSession(sessionID)
            if let window = currentWindow(), window.windowNumber == windowNumber {
                window.close()
            }
            sessionWindowStates.removeValue(forKey: sessionID)
            sessionWindowsByNumber.removeValue(forKey: windowNumber)
        }

        refreshAvailabilityForCurrentWindow()
    }

    func createSession() {
        createTargetAppState()?.createSession()
        refreshAvailabilityForCurrentWindow()
    }

    func refreshAll() {
        currentWorkspaceAppState()?.refreshAll()
        refreshAvailabilityForCurrentWindow()
    }

    func refreshFocusedSession() {
        currentWorkspaceAppState()?.refreshFocusedSessionMessages()
        refreshAvailabilityForCurrentWindow()
    }

    func focusPreviousPane() {
        currentWorkspaceAppState()?.focusPreviousPane()
        refreshAvailabilityForCurrentWindow()
    }

    func focusNextPane() {
        currentWorkspaceAppState()?.focusNextPane()
        refreshAvailabilityForCurrentWindow()
    }

    func updateAvailability(selectedDirectory: String?, focusedSessionID: String?, openSessionIDs: [String]) {
        canCreateSession = selectedDirectory != nil
        canRefresh = selectedDirectory != nil
        canRefreshFocusedSession = selectedDirectory != nil && focusedSessionID != nil
        let hasFocusedPane = focusedSessionID.map(openSessionIDs.contains) ?? false
        canFocusPreviousPane = hasFocusedPane
        canFocusNextPane = hasFocusedPane
        canCloseFocusedSession = currentSessionWindowAppState() != nil || (
            selectedDirectory != nil &&
                focusedSessionID.map(openSessionIDs.contains) == true
        )
    }

    private enum CloseTarget {
        case workspace(OpenCodeAppModel, String)
        case sessionWindow(OpenCodeAppModel, String, Int)
    }

    private func closeTarget(
        selectedDirectory: String? = nil,
        focusedSessionID: String? = nil,
        openSessionIDs: [String]? = nil
    ) -> CloseTarget? {
        if let currentWindowNumber,
           let sessionID = sessionWindowsByNumber[currentWindowNumber],
           let appState = sessionWindowStates[sessionID] {
            return .sessionWindow(appState, sessionID, currentWindowNumber)
        }

        let workspaceAppState = currentWorkspaceAppState() ?? fallbackAppState

        guard let workspaceAppState,
              selectedDirectory ?? workspaceAppState.selectedDirectory != nil,
              let focusedSessionID = focusedSessionID ?? workspaceAppState.focusedSessionID,
              (openSessionIDs ?? workspaceAppState.openSessionIDs).contains(focusedSessionID) else {
            return nil
        }

        return .workspace(workspaceAppState, focusedSessionID)
    }

    private func ensureWorkspaceBinding(for appState: OpenCodeAppModel) -> WorkspaceWindowBinding {
        let identifier = ObjectIdentifier(appState)
        if let binding = workspaceBindings[identifier] {
            return binding
        }

        let binding = WorkspaceWindowBinding(appState: appState)
        Publishers.CombineLatest4(appState.$selectedDirectory, appState.$focusedSessionID, appState.$openSessionIDs, appState.$serverURL)
            .sink { [weak self] _, _, _, _ in
                guard let self else { return }
                self.refreshAvailabilityForCurrentWindow()
            }
            .store(in: &binding.cancellables)
        workspaceBindings[identifier] = binding
        return binding
    }

    private func refreshAvailabilityForCurrentWindow() {
        let workspaceAppState = currentWorkspaceAppState() ?? fallbackAppState
        currentConnection = workspaceAppState?.workspaceConnection
        updateAvailability(
            selectedDirectory: workspaceAppState?.selectedDirectory,
            focusedSessionID: workspaceAppState?.focusedSessionID,
            openSessionIDs: workspaceAppState?.openSessionIDs ?? []
        )
    }

    private func currentWorkspaceAppState() -> OpenCodeAppModel? {
        guard let currentWindowNumber else { return nil }
        return workspaceBindings.values.first(where: { $0.windowNumber == currentWindowNumber })?.appState
    }

    private func currentSessionWindowAppState() -> OpenCodeAppModel? {
        guard let currentWindowNumber,
              let sessionID = sessionWindowsByNumber[currentWindowNumber] else {
            return nil
        }

        return sessionWindowStates[sessionID]
    }

    private func createTargetAppState() -> OpenCodeAppModel? {
        currentWorkspaceAppState() ?? fallbackAppState
    }

    private var currentWindowNumber: Int? {
        currentWindowNumberProvider()
    }

    private func currentWindow() -> NSWindow? {
        currentWindowProvider()
    }

    func resetForTesting() {
        fallbackAppState = nil
        workspaceBindings.removeAll()
        sessionWindowStates.removeAll()
        sessionWindowsByNumber.removeAll()
        currentConnection = nil
        canCreateSession = false
        canRefresh = false
        canRefreshFocusedSession = false
        canFocusPreviousPane = false
        canFocusNextPane = false
        canCloseFocusedSession = false
        currentWindowNumberProvider = {
            if let keyWindow = NSApp.keyWindow {
                return keyWindow.windowNumber
            }

            return NSApp.mainWindow?.windowNumber
        }
        currentWindowProvider = {
            NSApp.keyWindow ?? NSApp.mainWindow
        }
    }
}
