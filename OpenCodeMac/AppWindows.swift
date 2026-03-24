import AppKit
import SwiftUI

struct WorkspaceRootContainer: View {
    @EnvironmentObject private var modelPreferencesController: ModelPreferencesController
    @StateObject private var appState: OpenCodeAppModel
    @SceneStorage("workspace-root-restored-server-url") private var restoredServerURLText = ""
    @SceneStorage("workspace-root-restored-directory") private var restoredDirectory = ""

    init() {
        _appState = StateObject(
            wrappedValue: OpenCodeAppModelFactory.makeRootAppModel()
        )
    }

    var body: some View {
        RootView()
            .environmentObject(appState)
            .task {
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
            }
            .onChange(of: appState.workspaceConnection) { _, newConnection in
                restoredServerURLText = newConnection?.serverURL.absoluteString ?? ""
                restoredDirectory = newConnection?.directory ?? ""
            }
            .background(
                WindowObserver { window in
                    WorkspaceCommandCenter.shared.registerWorkspaceWindow(window)
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
}

struct SessionWindowContainer: View {
    @EnvironmentObject private var modelPreferencesController: ModelPreferencesController
    let context: SessionWindowContext
    @StateObject private var appState: OpenCodeAppModel
    @State private var toolbarController = SessionWindowToolbarController()

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
            .task {
                appState.configurePreferredDefaultModelPersistence(
                    provider: { modelPreferencesController.preferredDefaultModelReference },
                    setter: { modelPreferencesController.setPreferredDefaultModelReference($0) }
                )
                WorkspaceCommandCenter.shared.bindSessionWindow(appState: appState, sessionID: context.sessionID)
                await appState.bootstrapIfNeeded()
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

        toolbarController.attach(to: window, identifier: Self.toolbarIdentifier)
        toolbarController.update(title: session?.title ?? context.sessionID, contextUsageText: session?.contextUsageText)

        window.title = session?.title ?? context.sessionID
        window.subtitle = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
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
        .frame(minWidth: 220, maxWidth: 360)
        .padding(.vertical, 2)
    }
}

@MainActor
private final class SessionWindowToolbarController: NSObject, NSToolbarDelegate {
    private static let infoItemIdentifier = NSToolbarItem.Identifier("ai.opencode.session-window-toolbar.info")

    private let hostingView = NSHostingView(rootView: SessionWindowToolbarContent(title: "", contextUsageText: nil))
    private let infoItem = NSToolbarItem(itemIdentifier: infoItemIdentifier)
    private lazy var widthConstraint = hostingView.widthAnchor.constraint(equalToConstant: 220)
    private lazy var heightConstraint = hostingView.heightAnchor.constraint(equalToConstant: 30)
    private var toolbar: NSToolbar?

    override init() {
        super.init()
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        infoItem.view = hostingView
    }

    func attach(to window: NSWindow, identifier: NSToolbar.Identifier) {
        if let toolbar, window.toolbar === toolbar {
            return
        }

        let toolbar = NSToolbar(identifier: identifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false

        self.toolbar = toolbar
        window.toolbar = toolbar
    }

    func update(title: String, contextUsageText: String?) {
        hostingView.rootView = SessionWindowToolbarContent(title: title, contextUsageText: contextUsageText)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let width = min(max(fittingSize.width, 220), 360)
        let height = max(fittingSize.height, 30)

        widthConstraint.constant = width
        heightConstraint.constant = height
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.infoItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.infoItemIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.infoItemIdentifier else { return nil }
        return infoItem
    }
}

struct WindowObserver: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        nsView.onWindowChange = onWindowChange
        nsView.notifyWindowChange()
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
