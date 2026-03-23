import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 310)
        } detail: {
            Group {
                if appState.selectedDirectory == nil {
                    ProjectSelectorView()
                } else {
                    ChatBoardView(sessionIDs: appState.openSessionIDs)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.windowBackground)
        }
        .navigationTitle(appState.projectName ?? "Choose Project")
        .foregroundStyle(theme.primaryText)
        .alert("Colonnade Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appState.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .background(theme.windowBackground)
        .themedWindow(theme)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @State private var sessionPendingArchive: SessionDisplay?
    @State private var sessionPendingStop: SessionDisplay?

    var body: some View {
        List(selection: sessionListSelection) {
            if appState.selectedDirectory == nil {
                Section {
                    switch appState.launchStage {
                    case .localFolderSelection:
                        Button("Choose Project Folder") {
                            appState.chooseDirectory()
                        }
                    case .chooseServerMode:
                        Button("Open Local Directory") {
                            appState.openLocalDirectory()
                        }
                        .disabled(appState.isStartingLocalServer)

                        Button("Open Remote Directory") {
                            appState.showRemoteServerEntry()
                        }
                    case .remoteServerEntry:
                        Button("Back to Server Options") {
                            appState.resetServerSelection()
                        }
                    case .remoteDirectoryEntry:
                        Button("Change Server") {
                            appState.showRemoteServerEntry()
                        }
                    case .checkingLocalServer:
                        ProgressView()
                    }
                }
            }

            if appState.selectedDirectory != nil {
                if let liveStore = appState.liveStore {
                    SessionListSection(
                        liveStore: liveStore,
                        openSessionIDs: appState.openSessionIDs,
                        onStopRequest: { sessionPendingStop = $0 },
                        onArchiveRequest: { sessionPendingArchive = $0 }
                    )
                } else {
                    Section("Open Sessions") {
                        Text("No open sessions")
                            .foregroundStyle(theme.secondaryText)
                    }

                    Section("All Sessions") {
                        Text("No sessions yet")
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
        }
        .background(
            SessionListEscapeKeyHandler {
                requestStopForFocusedSession()
            }
        )
        .overlay {
            if appState.isLoading && appState.selectedDirectory != nil && appState.sessions.isEmpty {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    appState.createSession()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(appState.selectedDirectory == nil)
            }
        }
        .alert(
            "Stop Session?",
            isPresented: Binding(
                get: { sessionPendingStop != nil },
                set: { isPresented in
                    if !isPresented {
                        sessionPendingStop = nil
                    }
                }
            ),
            presenting: sessionPendingStop
        ) { session in
            Button("Stop", role: .destructive) {
                appState.stopSession(session.id)
                sessionPendingStop = nil
            }

            Button("Cancel", role: .cancel) {
                sessionPendingStop = nil
            }
        } message: { session in
            Text("Stop \"\(session.title)\"? The current run will be aborted.")
        }
        .alert(
            "Archive Session?",
            isPresented: Binding(
                get: { sessionPendingArchive != nil },
                set: { isPresented in
                    if !isPresented {
                        sessionPendingArchive = nil
                    }
                }
            ),
            presenting: sessionPendingArchive
        ) { session in
            Button("Archive", role: .destructive) {
                appState.archiveSession(session.id)
                sessionPendingArchive = nil
            }

            Button("Cancel", role: .cancel) {
                sessionPendingArchive = nil
            }
        } message: { session in
            Text("Archive \"\(session.title)\"? The session will be hidden from the sources list.")
        }
    }

    private var sessionListSelection: Binding<String?> {
        Binding(
            get: { appState.focusedSessionID },
            set: { newValue in
                guard let newValue else { return }
                appState.openSession(newValue)
            }
        )
    }

    private func requestStopForFocusedSession() {
        guard let focusedSessionID = appState.focusedSessionID,
              let session = appState.visibleSessions.first(where: { $0.id == focusedSessionID }),
              session.status?.isThinkingActive == true else {
            return
        }

        sessionPendingStop = session
    }
}

private struct SessionListSection: View {
    @ObservedObject var liveStore: WorkspaceLiveStore
    let openSessionIDs: [String]
    @Environment(\.openCodeTheme) private var theme

    let onStopRequest: (SessionDisplay) -> Void
    let onArchiveRequest: (SessionDisplay) -> Void

    private var visibleSessions: [SessionDisplay] {
        liveStore.sessions.filter { !$0.isArchived && !$0.isSubagentSession }
    }

    private var openSessionIDSet: Set<String> {
        Set(openSessionIDs)
    }

    private var openSessions: [SessionDisplay] {
        return visibleSessions.filter { openSessionIDSet.contains($0.id) }
    }

    private var remainingSessions: [SessionDisplay] {
        return visibleSessions.filter { !openSessionIDSet.contains($0.id) }
    }

    var body: some View {
        Section("Open Sessions") {
            if openSessions.isEmpty {
                Text("No open sessions")
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(openSessions) { session in
                    sessionRow(for: session)
                }
            }
        }

        Section("All Sessions") {
            if remainingSessions.isEmpty {
                Text(visibleSessions.isEmpty ? "No sessions yet" : "No other sessions")
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(remainingSessions) { session in
                    sessionRow(for: session)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(for session: SessionDisplay) -> some View {
        SessionRow(
            session: session,
            indicator: session.indicator,
            todoProgress: session.todoProgress
        )
        .contextMenu {
            if session.status?.isThinkingActive == true {
                Button("Stop Session...", role: .destructive) {
                    onStopRequest(session)
                }
            }

            Button("Archive Session...", role: .destructive) {
                onArchiveRequest(session)
            }
        }
        .tag(session.id)
    }
}

struct SessionListEscapeKeyEvent {
    static func shouldRequestStop(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isListFocused: Bool) -> Bool {
        guard isListFocused else { return false }

        let activeModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard activeModifiers.intersection(disallowedModifiers).isEmpty else { return false }

        return keyCode == 53
    }
}

private struct SessionListEscapeKeyHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> SessionListEscapeKeyMonitorView {
        let view = SessionListEscapeKeyMonitorView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: SessionListEscapeKeyMonitorView, context: Context) {
        nsView.onEscape = onEscape
    }
}

private final class SessionListEscapeKeyMonitorView: NSView {
    var onEscape: (() -> Void)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func installMonitor() {
        removeMonitor()

        guard let window else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }

            let shouldRequestStop = SessionListEscapeKeyEvent.shouldRequestStop(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                isListFocused: isListFocused(in: window)
            )

            guard shouldRequestStop else { return event }
            onEscape?()
            return nil
        }
    }

    private func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func isListFocused(in window: NSWindow) -> Bool {
        guard let firstResponder = window.firstResponder as? NSView else { return false }

        if firstResponder is NSTableView || firstResponder is NSOutlineView {
            return true
        }

        return firstResponder.enclosingTableView != nil || firstResponder.enclosingOutlineView != nil
    }
}

private extension NSView {
    var enclosingTableView: NSTableView? {
        sequence(first: self as NSView?, next: { $0?.superview }).first { $0 is NSTableView } as? NSTableView
    }

    var enclosingOutlineView: NSOutlineView? {
        sequence(first: self as NSView?, next: { $0?.superview }).first { $0 is NSOutlineView } as? NSOutlineView
    }
}

private struct SessionRow: View {
    @Environment(\.openCodeTheme) private var theme
    let session: SessionDisplay
    let indicator: SessionIndicator
    let todoProgress: TodoProgress?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SessionStatusIcon(color: indicator.color())
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: session.updatedAtMS / 1000)))
                    if let label = indicator.label {
                        Text(label)
                    }
                    if indicator.showsTodoProgress, let todoProgress {
                        Text(todoProgress.percentageText)
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
