import SwiftUI

private enum IOSSessionDrawerPosition {
    case collapsed
    case expanded
}

struct IOSRootView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    @State private var sessionDrawerPosition: IOSSessionDrawerPosition = .expanded
    @State private var isPresentingPreferences = false
    @State private var activeComposerSessionID: String?

    private var hasSelectedDirectory: Bool {
        appState.selectedDirectory != nil
    }

    private var resolvedComposerSessionID: String? {
        guard let activeComposerSessionID,
              appState.openSessionIDs.contains(activeComposerSessionID) else {
            return nil
        }

        return activeComposerSessionID
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.windowBackground
                .ignoresSafeArea()

            rootContentView
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasSelectedDirectory {
                if let sessionID = resolvedComposerSessionID {
                    IOSActivePromptComposerView(sessionID: sessionID) {
                        activeComposerSessionID = nil
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                } else {
                    Color.clear.frame(height: 24)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if hasSelectedDirectory, resolvedComposerSessionID == nil {
                IOSPersistentSessionDrawer(
                    position: $sessionDrawerPosition,
                    onShowPreferences: {
                        isPresentingPreferences = true
                    },
                    onCreateSession: {
                        appState.createSession()
                        sessionDrawerPosition = .collapsed
                    },
                    onSessionSelected: { session in
                        sessionDrawerPosition = .collapsed
                        if appState.openSessionIDs.contains(session.id) {
                            appState.focusSession(session.id)
                            appState.requestSessionCenter(for: session.id)
                        } else {
                            appState.openSession(session.id)
                        }
                    }
                )
            }
        }
        .tint(theme.accent)
        .foregroundStyle(theme.primaryText)
        .alert("Colonnade Error", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .sheet(isPresented: $isPresentingPreferences) {
            IOSPreferencesView()
        }
        .onChange(of: appState.selectedDirectory) { _, newValue in
            sessionDrawerPosition = newValue == nil ? .expanded : .collapsed
            if newValue == nil {
                activeComposerSessionID = nil
            }
        }
        .onChange(of: appState.promptFocusRequest) { _, newValue in
            guard let sessionID = newValue?.sessionID else { return }
            activateComposer(for: sessionID)
        }
        .onChange(of: appState.openSessionIDs) { _, newValue in
            guard let activeComposerSessionID, !newValue.contains(activeComposerSessionID) else { return }
            self.activeComposerSessionID = appState.focusedSessionID.flatMap { newValue.contains($0) ? $0 : nil }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: resolvedComposerSessionID)
    }

    @ViewBuilder
    private var rootContentView: some View {
        if hasSelectedDirectory {
            IOSSessionBoardContainerView(
                activeComposerSessionID: resolvedComposerSessionID,
                onDeactivateComposer: {
                    activeComposerSessionID = nil
                },
                onActivateComposer: activateComposer(for:)
            )
        } else {
            IOSProjectSelectorView()
        }
    }

    private func activateComposer(for sessionID: String) {
        guard hasSelectedDirectory else { return }
        appState.focusSession(sessionID)
        sessionDrawerPosition = .collapsed
        activeComposerSessionID = sessionID
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appState.errorMessage = nil
                }
            }
        )
    }
}

private struct IOSPersistentSessionDrawer: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    @Binding var position: IOSSessionDrawerPosition

    let onShowPreferences: () -> Void
    let onCreateSession: () -> Void
    let onSessionSelected: (SessionDisplay) -> Void

    @State private var dragTranslation: CGFloat = 0

    private let collapsedHeight: CGFloat = 100
    private let drawerCornerRadius: CGFloat = 22

    private var activeSessionCount: Int {
        let openSessionIDSet = Set(appState.openSessionIDs)
        return (appState.liveStore?.orderedVisibleSessionStates() ?? []).filter {
            guard let session = $0.session else { return false }
            return openSessionIDSet.contains(session.id) && session.status?.isThinkingActive == true
        }.count
    }

    private var collapsedStatusText: String {
        if activeSessionCount == 0 {
            return "No active sessions"
        }

        return activeSessionCount == 1 ? "1 active session" : "\(activeSessionCount) active sessions"
    }

    private var collapsedStatusColor: Color {
        activeSessionCount == 0 ? .green : .yellow
    }

    var body: some View {
        GeometryReader { geometry in
            let expandedHeight = min(max(geometry.size.height * 0.9, 320), geometry.size.height)
            let displayedHeight = drawerHeight(expandedHeight: expandedHeight)
            let showsExpandedContent = displayedHeight > collapsedHeight + 32

            VStack(spacing: 0) {
                Capsule()
                    .fill(theme.secondaryText.opacity(0.4))
                    .frame(width: 44, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, showsExpandedContent ? 10 : 8)

                if showsExpandedContent {
                    HStack {
                        Button {
                            onShowPreferences()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.body.weight(.semibold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            onCreateSession()
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    Divider()

                    if let liveStore = appState.liveStore {
                        IOSSourcesListView(
                            liveStore: liveStore,
                            onCreateSession: onCreateSession,
                            onSessionSelected: onSessionSelected
                        )
                    }
                } else {
                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        SessionStatusIcon(color: collapsedStatusColor)
                        Text(collapsedStatusText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: displayedHeight, alignment: .top)
            .background {
                if showsExpandedContent {
                    RoundedRectangle(cornerRadius: drawerCornerRadius, style: .continuous)
                        .fill(theme.opaqueMutedSurfaceBackground)
                } else {
                    RoundedRectangle(cornerRadius: drawerCornerRadius, style: .continuous)
                        .fill(theme.opaqueMutedSurfaceBackground.opacity(0.9))
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: drawerCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: drawerCornerRadius, style: .continuous)
                    .stroke(theme.secondaryText.opacity(showsExpandedContent ? 0.12 : 0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 18, y: -4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .gesture(dragGesture(expandedHeight: expandedHeight))
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: position)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.88), value: dragTranslation)
        }
    }

    private func drawerHeight(expandedHeight: CGFloat) -> CGFloat {
        let baseHeight = position == .expanded ? expandedHeight : collapsedHeight
        let height = baseHeight - dragTranslation
        return min(max(height, collapsedHeight), expandedHeight)
    }

    private func dragGesture(expandedHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                let projectedHeight = projectedDrawerHeight(expandedHeight: expandedHeight, value: value)
                let midpoint = (collapsedHeight + expandedHeight) / 2
                position = projectedHeight > midpoint ? .expanded : .collapsed
                dragTranslation = 0
            }
    }

    private func projectedDrawerHeight(expandedHeight: CGFloat, value: DragGesture.Value) -> CGFloat {
        let baseHeight = position == .expanded ? expandedHeight : collapsedHeight
        let projectedHeight = baseHeight - value.predictedEndTranslation.height
        return min(max(projectedHeight, collapsedHeight), expandedHeight)
    }
}

private struct IOSSessionBoardContainerView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel

    let activeComposerSessionID: String?
    let onDeactivateComposer: () -> Void
    let onActivateComposer: (String) -> Void

    var body: some View {
        IOSSessionBoardView(
            initialSessionID: initialSessionID,
            activeComposerSessionID: activeComposerSessionID,
            onDeactivateComposer: onDeactivateComposer,
            onActivateComposer: onActivateComposer
        )
    }

    private var initialSessionID: String {
        if let focusedSessionID = appState.focusedSessionID {
            return focusedSessionID
        }

        if let openSessionID = appState.openSessionIDs.first {
            return openSessionID
        }

        if let visibleSessionID = appState.visibleSessions.first?.id {
            return visibleSessionID
        }

        return ""
    }
}
