import AppKit
import SwiftUI

@main
struct OpenCodeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("OpenCode", id: "workspace-root") {
            WorkspaceRootContainer()
        }
        .defaultSize(width: 1440, height: 920)

        WindowGroup("Session", id: "session-window", for: SessionWindowContext.self) { $context in
            SessionWindowContainer(context: context)
        }
        .defaultSize(width: 760, height: 920)
    }

    var commands: some Commands {
        WorkspaceCommands()
    }
}

private struct WorkspaceRootContainer: View {
    @StateObject private var appState: OpenCodeAppState

    init() {
        _appState = StateObject(
            wrappedValue: OpenCodeAppState(
                restoresLastSelectedDirectory: false
            )
        )
    }

    var body: some View {
        RootView()
            .environmentObject(appState)
            .task {
                WorkspaceCommandCenter.shared.bind(appState: appState)
                await appState.bootstrapIfNeeded()
            }
    }
}

private struct WorkspaceCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: "workspace-root")
            }
            .keyboardShortcut("n")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Constants {
        static let showsThinkingKey = "showsThinking"
        static let thinkingMenuItemTag = 9_001
        static let viewSeparatorTag = 9_002
        static let previousPaneMenuItemTag = 9_003
        static let nextPaneMenuItemTag = 9_004
        static let workspaceMenuTag = 9_010
        static let resyncMenuItemTag = 9_011
        static let messagesMenuTag = 9_020
        static let refreshMessagesMenuItemTag = 9_021
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

    @objc private func toggleThinkingVisibility() {
        UserDefaults.standard.set(!showsThinking, forKey: Constants.showsThinkingKey)
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

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
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
        installViewMenuItems()
        installWorkspaceMenuItems()
        installMessagesMenuItems()
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
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Constants.showsThinkingKey) != nil else { return true }
        return defaults.bool(forKey: Constants.showsThinkingKey)
    }
}

private struct SessionWindowContainer: View {
    let context: SessionWindowContext?
    @StateObject private var appState: OpenCodeAppState

    init(context: SessionWindowContext?) {
        self.context = context
        _appState = StateObject(
            wrappedValue: OpenCodeAppState(
                persistsWorkspacePaneState: false,
                initialDirectory: context?.directory,
                initialOpenSessionIDs: context.map { [$0.sessionID] } ?? []
            )
        )
    }

    var body: some View {
        SessionWindowView(sessionID: context?.sessionID ?? "")
            .environmentObject(appState)
            .task {
                await appState.bootstrapIfNeeded()
            }
    }
}

@MainActor
final class WorkspaceCommandCenter: ObservableObject {
    static let shared = WorkspaceCommandCenter()

    @Published private(set) var canRefresh = false
    @Published private(set) var canRefreshFocusedSession = false
    @Published private(set) var canFocusPreviousPane = false
    @Published private(set) var canFocusNextPane = false

    private weak var appState: OpenCodeAppState?

    private init() {}

    func bind(appState: OpenCodeAppState) {
        self.appState = appState
        updateAvailability(
            selectedDirectory: appState.selectedDirectory,
            focusedSessionID: appState.focusedSessionID,
            openSessionIDs: appState.openSessionIDs
        )
    }

    func refreshAll() {
        appState?.refreshAll()
        updateAvailability(
            selectedDirectory: appState?.selectedDirectory,
            focusedSessionID: appState?.focusedSessionID,
            openSessionIDs: appState?.openSessionIDs ?? []
        )
    }

    func refreshFocusedSession() {
        appState?.refreshFocusedSessionMessages()
        updateAvailability(
            selectedDirectory: appState?.selectedDirectory,
            focusedSessionID: appState?.focusedSessionID,
            openSessionIDs: appState?.openSessionIDs ?? []
        )
    }

    func focusPreviousPane() {
        appState?.focusPreviousPane()
        updateAvailability(
            selectedDirectory: appState?.selectedDirectory,
            focusedSessionID: appState?.focusedSessionID,
            openSessionIDs: appState?.openSessionIDs ?? []
        )
    }

    func focusNextPane() {
        appState?.focusNextPane()
        updateAvailability(
            selectedDirectory: appState?.selectedDirectory,
            focusedSessionID: appState?.focusedSessionID,
            openSessionIDs: appState?.openSessionIDs ?? []
        )
    }

    func updateAvailability(selectedDirectory: String?, focusedSessionID: String?, openSessionIDs: [String]) {
        canRefresh = selectedDirectory != nil
        canRefreshFocusedSession = selectedDirectory != nil && focusedSessionID != nil
        if let focusedSessionID, let focusedIndex = openSessionIDs.firstIndex(of: focusedSessionID) {
            canFocusPreviousPane = openSessionIDs.indices.contains(focusedIndex - 1)
            canFocusNextPane = openSessionIDs.indices.contains(focusedIndex + 1)
        } else {
            canFocusPreviousPane = false
            canFocusNextPane = false
        }
    }
}
