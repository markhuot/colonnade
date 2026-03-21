import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: OpenCodeAppState

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
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(appState.projectName ?? "Choose Project")
        .alert("OpenCode Error", isPresented: Binding(
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
        .background(
            FocusedSessionTimelineKeyHandler { direction in
                appState.scrollFocusedSessionTimeline(to: direction)
            }
        )
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: OpenCodeAppState
    @State private var sessionPendingArchive: SessionDisplay?

    var body: some View {
        List(selection: sessionListSelection) {
            if appState.selectedDirectory == nil {
                Section {
                    Button("Choose Project Folder") {
                        appState.chooseDirectory()
                    }
                }
            }

            if appState.selectedDirectory != nil {
                Section("Sessions") {
                    if let liveStore = appState.liveStore {
                        SessionListSection(
                            liveStore: liveStore,
                            onArchiveRequest: { sessionPendingArchive = $0 }
                        )
                    } else {
                        Text("No sessions yet")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if appState.isLoading {
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
}

private struct SessionListSection: View {
    @ObservedObject var liveStore: WorkspaceLiveStore

    let onArchiveRequest: (SessionDisplay) -> Void

    private var visibleSessions: [SessionDisplay] {
        liveStore.sessions.filter { !$0.isArchived && !$0.isSubagentSession }
    }

    var body: some View {
        if visibleSessions.isEmpty {
            Text("No sessions yet")
                .foregroundStyle(.secondary)
        } else {
            ForEach(visibleSessions) { session in
                SessionRow(
                    session: session,
                    indicator: session.indicator,
                    todoProgress: session.todoProgress
                )
                .contextMenu {
                    Button("Archive Session...", role: .destructive) {
                        onArchiveRequest(session)
                    }
                }
                .tag(session.id)
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionDisplay
    let indicator: SessionIndicator
    let todoProgress: TodoProgress?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SessionStatusIcon(color: indicator.color)
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
                .foregroundStyle(.secondary)
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
