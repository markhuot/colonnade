import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    var body: some View {
        let openSessionIDs = appState.openSessionIDs

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 310)
        } detail: {
            Group {
                if appState.selectedDirectory == nil {
                    ProjectSelectorView()
                } else {
                    ChatBoardView(sessionIDs: openSessionIDs)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.windowBackground)
        }
        .navigationTitle(appState.projectName ?? "Choose Project")
        .foregroundStyle(theme.primaryText)
        .overlay(alignment: .topTrailing) {
            if let liveStore = appState.liveStore {
                SSEDebugOverlay(liveStore: liveStore)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
            }
        }
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

struct SSEDebugOverlay: View {
    @ObservedObject var liveStore: WorkspaceLiveStore
    @Environment(\.openCodeTheme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(liveStore.rawSSEEvents) { event in
                    Text(verbatim: event.payload)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .defaultScrollAnchor(.bottom)
        .frame(width: 420, height: 260)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surfaceBackground.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 10)
        .padding(.leading, 12)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @State private var sessionPendingArchive: SessionDisplay?
    @State private var sessionPendingStop: SessionDisplay?
    @State private var sessionPendingRename: SessionDisplay?
    @State private var sessionRenameTitle = ""

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
                        onRenameRequest: {
                            sessionPendingRename = $0
                            sessionRenameTitle = $0.title
                        },
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
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.mutedSurfaceBackground.ignoresSafeArea())
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
            "Rename Session",
            isPresented: Binding(
                get: { sessionPendingRename != nil },
                set: { isPresented in
                    if !isPresented {
                        sessionPendingRename = nil
                        sessionRenameTitle = ""
                    }
                }
            ),
            presenting: sessionPendingRename
        ) { session in
            TextField("Session title", text: $sessionRenameTitle)

            Button("Rename") {
                appState.renameSession(session.id, title: sessionRenameTitle)
                sessionPendingRename = nil
                sessionRenameTitle = ""
            }

            Button("Cancel", role: .cancel) {
                sessionPendingRename = nil
                sessionRenameTitle = ""
            }
        } message: { session in
            Text("Enter a new name for \"\(session.title)\".")
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
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let onRenameRequest: (SessionDisplay) -> Void
    let onStopRequest: (SessionDisplay) -> Void
    let onArchiveRequest: (SessionDisplay) -> Void

    private var visibleSessionStates: [SessionLiveState] {
        liveStore.orderedVisibleSessionStates()
    }

    private var openSessionIDSet: Set<String> {
        Set(openSessionIDs)
    }

    private var openSessionStates: [SessionLiveState] {
        visibleSessionStates.filter { openSessionIDSet.contains($0.id) }
    }

    private var remainingSessionStates: [SessionLiveState] {
        visibleSessionStates.filter { !openSessionIDSet.contains($0.id) }
    }

    var body: some View {
        Section("Open Sessions") {
            if openSessionStates.isEmpty {
                Text("No open sessions")
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(openSessionStates) { sessionState in
                    sessionRow(for: sessionState)
                }
            }
        }

        Section("All Sessions") {
            if remainingSessionStates.isEmpty {
                Text(visibleSessionStates.isEmpty ? "No sessions yet" : "No other sessions")
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(remainingSessionStates) { sessionState in
                    sessionRow(for: sessionState)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(for sessionState: SessionLiveState) -> some View {
        SessionRow(
            sessionState: sessionState
        )
        .contextMenu {
            if let session = sessionState.session {
                Button("Rename Session...") {
                    onRenameRequest(session)
                }

                Divider()
            }

            if let session = sessionState.session, openSessionIDSet.contains(session.id) {
                Button("Close Session") {
                    appState.closeSession(session.id)
                }

                Divider()
            }

            if let session = sessionState.session, session.status?.isThinkingActive == true {
                Button("Stop Session...", role: .destructive) {
                    onStopRequest(session)
                }
            }

            if let session = sessionState.session {
                Button("Archive Session...", role: .destructive) {
                    onArchiveRequest(session)
                }
            }
        }
        .tag(sessionState.id)
    }
}

private struct SessionRow: View {
    @Environment(\.openCodeTheme) private var theme
    @ObservedObject var sessionState: SessionLiveState

    var body: some View {
        let session = sessionState.session ?? SessionDisplay(
            id: sessionState.id,
            title: sessionState.sessionTitle,
            createdAtMS: 0,
            updatedAtMS: 0,
            hydratedMessageUpdatedAtMS: nil,
            parentID: nil,
            status: nil,
            hasPendingPermission: false,
            todoProgress: nil,
            contextUsageText: nil,
            isArchived: false
        )
        let indicator = session.indicator
        let todoProgress = session.todoProgress

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
