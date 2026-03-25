import AppKit
import SwiftUI

struct WorkspaceRootContainer: View {
    @EnvironmentObject private var modelPreferencesController: ModelPreferencesController
    @Environment(\.openCodeTheme) private var theme
    @StateObject private var appState: OpenCodeAppModel
    @State private var workspaceWindow: NSWindow?
    @SceneStorage("workspace-root-restored-server-url") private var restoredServerURLText = ""
    @SceneStorage("workspace-root-restored-directory") private var restoredDirectory = ""
    @State private var bootstrapStart: ContinuousClock.Instant?

    init() {
        _appState = StateObject(
            wrappedValue: OpenCodeAppModelFactory.makeRootAppModel()
        )
    }

    var body: some View {
        RootView()
            .environmentObject(appState)
            .performanceLayoutProbe("WorkspaceRootContainer") {
                "project=\(appState.projectName ?? "nil") selectedDirectory=\(appState.selectedDirectory ?? "nil") isLoading=\(appState.isLoading)"
            }
            .task {
                let start = PerformanceInstrumentation.begin(
                    "workspace-bootstrap",
                    details: "restoredDirectory=\(restoredDirectory.isEmpty ? "nil" : restoredDirectory)"
                )
                bootstrapStart = start
                let restoredConnection = restoredWorkspaceConnection
                appState.configureBootstrapRestoredConnection(restoredConnection)
                if let restoredConnection {
                    restoredServerURLText = restoredConnection.serverURL.absoluteString
                    restoredDirectory = restoredConnection.directory
                }
                appState.configurePreferredDefaultModelPersistence(
                    provider: { modelPreferencesController.preferredDefaultModelReference },
                    setter: { modelPreferencesController.setPreferredDefaultModelReference($0) }
                )
                WorkspaceCommandCenter.shared.bind(appState: appState)
                await appState.bootstrapIfNeeded()
                PerformanceInstrumentation.end(
                    "workspace-bootstrap",
                    from: start,
                    details: "selectedDirectory=\(appState.selectedDirectory ?? "nil") openSessions=\(appState.openSessionIDs.count)",
                    thresholdMS: 1
                )
            }
            .onChange(of: appState.isLoading) { oldValue, newValue in
                guard oldValue, !newValue, let bootstrapStart else { return }
                PerformanceInstrumentation.end(
                    "workspace-first-visible-content",
                    from: bootstrapStart,
                    details: "selectedDirectory=\(appState.selectedDirectory ?? "nil") openSessions=\(appState.openSessionIDs.count)",
                    thresholdMS: 1
                )
                self.bootstrapStart = nil
            }
            .onChange(of: appState.workspaceConnection) { _, newConnection in
                restoredServerURLText = newConnection?.serverURL.absoluteString ?? ""
                restoredDirectory = newConnection?.directory ?? ""
            }
            .onChange(of: appState.projectName) { _, _ in
                configureWindow(workspaceWindow)
            }
            .onChange(of: theme.id) { _, _ in
                configureWindow(workspaceWindow)
            }
            .background(
                WindowObserver(notifyOnUpdate: false) { window in
                    workspaceWindow = window
                    configureWindow(window)
                    WorkspaceCommandCenter.shared.registerWorkspaceWindow(window, appState: appState)
                }
            )
    }

    private var restoredWorkspaceConnection: WorkspaceConnection? {
        let trimmedDirectory = restoredDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDirectory.isEmpty else { return nil }

        let trimmedServerURLText = restoredServerURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverURL = URL(string: trimmedServerURLText) ?? OpenCodeAppModel.defaultServerURL
        return WorkspaceConnection(serverURL: serverURL, directory: trimmedDirectory)
    }

    private func configureWindow(_ window: NSWindow?) {
        guard let window else { return }

        window.title = appState.projectName ?? "Choose Project"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = theme.windowBackgroundColor
    }
}

struct SessionWindowContainer: View {
    @EnvironmentObject private var modelPreferencesController: ModelPreferencesController
    @Environment(\.openCodeTheme) private var theme
    let context: SessionWindowContext
    @StateObject private var appState: OpenCodeAppModel
    @State private var titlebarAccessoryController = SessionWindowTitlebarAccessoryController()
    @State private var bootstrapStart: ContinuousClock.Instant?

    private static let toolbarIdentifier = NSToolbar.Identifier("ai.opencode.session-window-toolbar")

    init(context: SessionWindowContext) {
        self.context = context
        _appState = StateObject(
            wrappedValue: OpenCodeAppModelFactory.makeSessionWindowAppModel(context: context)
        )
    }

    var body: some View {
        SessionWindowView(sessionID: context.sessionID)
            .environmentObject(appState)
            .defaultScrollAnchor(.bottom)
            .performanceLayoutProbe("SessionWindowContainer") {
                "sessionID=\(context.sessionID) selectedDirectory=\(appState.selectedDirectory ?? "nil") isLoading=\(appState.isLoading)"
            }
            .task {
                let start = PerformanceInstrumentation.begin(
                    "session-window-bootstrap",
                    details: "sessionID=\(context.sessionID) directory=\(context.connection.directory)"
                )
                bootstrapStart = start
                appState.configurePreferredDefaultModelPersistence(
                    provider: { modelPreferencesController.preferredDefaultModelReference },
                    setter: { modelPreferencesController.setPreferredDefaultModelReference($0) }
                )
                WorkspaceCommandCenter.shared.bindSessionWindow(appState: appState, sessionID: context.sessionID)
                await appState.bootstrapIfNeeded()
                PerformanceInstrumentation.end(
                    "session-window-bootstrap",
                    from: start,
                    details: "sessionID=\(context.sessionID) selectedDirectory=\(appState.selectedDirectory ?? "nil")",
                    thresholdMS: 1
                )
            }
            .onChange(of: appState.isLoading) { oldValue, newValue in
                guard oldValue, !newValue, let bootstrapStart else { return }
                PerformanceInstrumentation.end(
                    "session-window-first-visible-content",
                    from: bootstrapStart,
                    details: "sessionID=\(context.sessionID)",
                    thresholdMS: 1
                )
                self.bootstrapStart = nil
            }
            .background(
                WindowObserver { window in
                    configureWindow(window, session: session)
                    WorkspaceCommandCenter.shared.registerSessionWindow(window, sessionID: context.sessionID)
                }
            )
    }

    private var session: SessionDisplay? {
        appState.liveStore?.sessionState(for: context.sessionID).session
    }

    private func configureWindow(_ window: NSWindow?, session: SessionDisplay?) {
        guard let window else { return }

        titlebarAccessoryController.attach(to: window, identifier: Self.toolbarIdentifier)
        titlebarAccessoryController.update(title: session?.title ?? context.sessionID, contextUsageText: session?.contextUsageText)

        window.title = session?.title ?? context.sessionID
        window.subtitle = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = theme.windowBackgroundColor
    }
}

private struct SessionWindowToolbarContent: View {
    let title: String
    let contextUsageText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)

            Text(contextUsageText ?? "No context usage yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.leading)
        .frame(minWidth: 220, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

@MainActor
private final class SessionWindowTitlebarAccessoryController {
    private let hostingView = NSHostingView(rootView: SessionWindowToolbarContent(title: "", contextUsageText: nil))
    private lazy var heightConstraint = hostingView.heightAnchor.constraint(equalToConstant: 30)
    private let accessoryViewController = NSTitlebarAccessoryViewController()
    private var toolbar: NSToolbar?
    private weak var window: NSWindow?

    init() {
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightConstraint])
        accessoryViewController.view = hostingView
        accessoryViewController.layoutAttribute = .bottom
        accessoryViewController.automaticallyAdjustsSize = false
    }

    func attach(to window: NSWindow, identifier: NSToolbar.Identifier) {
        if self.window === window {
            return
        }

        if let existingWindow = self.window,
           let index = existingWindow.titlebarAccessoryViewControllers.firstIndex(of: accessoryViewController) {
            existingWindow.removeTitlebarAccessoryViewController(at: index)
        }

        self.window = window
        let toolbar = self.toolbar ?? {
            let toolbar = NSToolbar(identifier: identifier)
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            self.toolbar = toolbar
            return toolbar
        }()
        window.toolbar = toolbar
        window.addTitlebarAccessoryViewController(accessoryViewController)
    }

    func update(title: String, contextUsageText: String?) {
        hostingView.rootView = SessionWindowToolbarContent(title: title, contextUsageText: contextUsageText)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let height = max(fittingSize.height, 30)

        heightConstraint.constant = height
    }
}

struct WindowObserver: NSViewRepresentable {
    let notifyOnUpdate: Bool
    let onWindowChange: (NSWindow?) -> Void

    init(notifyOnUpdate: Bool = true, onWindowChange: @escaping (NSWindow?) -> Void) {
        self.notifyOnUpdate = notifyOnUpdate
        self.onWindowChange = onWindowChange
    }

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        nsView.onWindowChange = onWindowChange
        if notifyOnUpdate {
            nsView.notifyWindowChange()
        }
    }
}

final class WindowObserverView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifyWindowChange()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        onWindowChange?(newWindow)
        super.viewWillMove(toWindow: newWindow)
    }

    func notifyWindowChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onWindowChange?(self.window)
        }
    }
}

struct InvalidSessionWindowView: NSViewRepresentable {
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
