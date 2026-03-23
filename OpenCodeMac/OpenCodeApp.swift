import AppKit
import Combine
import SwiftUI

@main
struct OpenCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var themeController = ThemeController()

    var body: some Scene {
        WindowGroup("OpenCode", id: "workspace-root") {
            WorkspaceRootContainer()
                .environmentObject(themeController)
                .environment(\.openCodeTheme, themeController.selectedTheme)
                .preferredColorScheme(themeController.selectedTheme.preferredColorScheme)
        }
        .defaultSize(width: 1440, height: 920)

        WindowGroup("Session", id: "session-window", for: SessionWindowContext.self) { $context in
            if let context {
                SessionWindowContainer(context: context)
                    .environmentObject(themeController)
                    .environment(\.openCodeTheme, themeController.selectedTheme)
                    .preferredColorScheme(themeController.selectedTheme.preferredColorScheme)
            } else {
                InvalidSessionWindowView()
            }
        }
        .defaultSize(width: 760, height: 920)

        Settings {
            PreferencesView()
                .environmentObject(themeController)
                .environment(\.openCodeTheme, themeController.selectedTheme)
                .preferredColorScheme(themeController.selectedTheme.preferredColorScheme)
        }
    }

    var commands: some Commands {
        WorkspaceCommands()
    }
}

private struct PreferencesView: View {
    @EnvironmentObject private var themeController: ThemeController
    @Environment(\.openCodeTheme) private var theme

    var body: some View {
        Form {
            Picker("Theme", selection: Binding(
                get: { themeController.selectedThemeID },
                set: { themeController.selectTheme($0) }
            )) {
                ForEach(OpenCodeThemeID.allCases) { themeID in
                    Text(themeID.displayName)
                        .tag(themeID)
                }
            }
            .pickerStyle(.menu)

            Text("Native keeps the current macOS window and text colors. Shiki themes currently update the window background and text colors.")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 460)
        .background(theme.windowBackground)
        .themedWindow(theme)
    }
}

private struct WorkspaceRootContainer: View {
    @StateObject private var appState: OpenCodeAppModel

    init() {
        _appState = StateObject(
            wrappedValue: OpenCodeAppModelFactory.makeRootAppModel()
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
        static let showsThinkingKey = "showsThinking"
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

    @objc private func createSessionFromMenu() {
        WorkspaceCommandCenter.shared.createSession()
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
        case Constants.fileNewSessionMenuItemTag:
            return WorkspaceCommandCenter.shared.canCreateSession
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

        if let windowItem = fileMenu.item(withTag: Constants.fileNewWindowMenuItemTag),
           let sessionItem = fileMenu.item(withTag: Constants.fileNewSessionMenuItemTag) {
            windowItem.title = "New Window"
            windowItem.keyEquivalent = "n"
            windowItem.keyEquivalentModifierMask = [.command]

            sessionItem.title = "New Session"
            sessionItem.action = #selector(createSessionFromMenu)
            sessionItem.target = self
            sessionItem.keyEquivalent = "t"
            sessionItem.keyEquivalentModifierMask = [.command]

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
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Constants.showsThinkingKey) != nil else { return true }
        return defaults.bool(forKey: Constants.showsThinkingKey)
    }
}

private struct SessionWindowContainer: View {
    let context: SessionWindowContext
    @StateObject private var appState: OpenCodeAppModel

    init(context: SessionWindowContext) {
        self.context = context
        _appState = StateObject(
            wrappedValue: OpenCodeAppModelFactory.makeSessionWindowAppModel(context: context)
        )
    }

    var body: some View {
        SessionWindowView(sessionID: context.sessionID)
            .environmentObject(appState)
            .task {
                await appState.bootstrapIfNeeded()
            }
    }
}

private struct InvalidSessionWindowView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        closeWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        closeWindow(for: nsView)
    }

    private func closeWindow(for view: NSView) {
        DispatchQueue.main.async {
            view.window?.close()
        }
    }
}

@MainActor
final class WorkspaceCommandCenter: ObservableObject {
    static let shared = WorkspaceCommandCenter()

    @Published private(set) var canCreateSession = false
    @Published private(set) var canRefresh = false
    @Published private(set) var canRefreshFocusedSession = false
    @Published private(set) var canFocusPreviousPane = false
    @Published private(set) var canFocusNextPane = false

    private weak var appState: OpenCodeAppModel?
    private var availabilityCancellables: Set<AnyCancellable> = []

    private init() {}

    func bind(appState: OpenCodeAppModel) {
        self.appState = appState
        availabilityCancellables.removeAll()

        Publishers.CombineLatest3(appState.$selectedDirectory, appState.$focusedSessionID, appState.$openSessionIDs)
            .sink { [weak self] selectedDirectory, focusedSessionID, openSessionIDs in
                self?.updateAvailability(
                    selectedDirectory: selectedDirectory,
                    focusedSessionID: focusedSessionID,
                    openSessionIDs: openSessionIDs
                )
            }
            .store(in: &availabilityCancellables)
    }

    func createSession() {
        appState?.createSession()
        updateAvailability(
            selectedDirectory: appState?.selectedDirectory,
            focusedSessionID: appState?.focusedSessionID,
            openSessionIDs: appState?.openSessionIDs ?? []
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
        canCreateSession = selectedDirectory != nil
        canRefresh = selectedDirectory != nil
        canRefreshFocusedSession = selectedDirectory != nil && focusedSessionID != nil
        let hasFocusedPane = focusedSessionID.map(openSessionIDs.contains) ?? false
        canFocusPreviousPane = hasFocusedPane
        canFocusNextPane = hasFocusedPane
    }
}
