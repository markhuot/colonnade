import SwiftUI

struct IOSSourcesListView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @ObservedObject var liveStore: WorkspaceLiveStore

    let onBack: () -> Void
    let onSessionSelected: (SessionDisplay) -> Void

    @State private var sessionPendingArchive: SessionDisplay?
    @State private var sessionPendingStop: SessionDisplay?

    private var openSessionIDSet: Set<String> {
        Set(appState.openSessionIDs)
    }

    private var visibleSessionStates: [SessionLiveState] {
        liveStore.orderedVisibleSessionStates()
    }

    private var openSessionStates: [SessionLiveState] {
        visibleSessionStates.filter { openSessionIDSet.contains($0.id) }
    }

    private var remainingSessionStates: [SessionLiveState] {
        visibleSessionStates.filter { !openSessionIDSet.contains($0.id) }
    }

    var body: some View {
        List {
            if appState.selectedDirectory != nil {
                Section {
                    Button {
                        onBack()
                    } label: {
                        Label("Back to Projects", systemImage: "chevron.backward")
                    }
                }

                section(title: "Open Sessions", sessionStates: openSessionStates, emptyText: "No open sessions")
                section(title: "All Sessions", sessionStates: remainingSessionStates, emptyText: visibleSessionStates.isEmpty ? "No sessions yet" : "No other sessions")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.mutedSurfaceBackground)
        .alert(
            "Stop Session?",
            isPresented: Binding(
                get: { sessionPendingStop != nil },
                set: { if !$0 { sessionPendingStop = nil } }
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
                set: { if !$0 { sessionPendingArchive = nil } }
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

    @ViewBuilder
    private func section(title: String, sessionStates: [SessionLiveState], emptyText: String) -> some View {
        Section(title) {
            if sessionStates.isEmpty {
                Text(emptyText)
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(sessionStates) { sessionState in
                    let session = sessionState.session
                    Button {
                        guard let session else { return }
                        onSessionSelected(session)
                    } label: {
                        IOSSessionRow(sessionState: sessionState)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let session {
                            if openSessionIDSet.contains(session.id) {
                                Button("Close") {
                                    appState.closeSession(session.id)
                                }
                                .tint(.gray)
                            }

                            Button("Archive", role: .destructive) {
                                sessionPendingArchive = session
                            }

                            if session.status?.isThinkingActive == true {
                                Button("Stop", role: .destructive) {
                                    sessionPendingStop = session
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct IOSSessionRow: View {
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
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

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
        }
        .padding(.vertical, 4)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
