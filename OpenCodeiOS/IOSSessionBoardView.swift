import SwiftUI

struct IOSSessionBoardView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let initialSessionID: String
    let activeComposerSessionID: String?
    let bottomOverlayClearance: CGFloat
    let draftRegistry: SessionDraftRegistry
    let onDeactivateComposer: () -> Void
    let onActivateComposer: (String) -> Void

    @State private var selectedPageSessionID: String?

    init(
        initialSessionID: String,
        activeComposerSessionID: String? = nil,
        bottomOverlayClearance: CGFloat = 0,
        draftRegistry: SessionDraftRegistry,
        onDeactivateComposer: @escaping () -> Void = {},
        onActivateComposer: @escaping (String) -> Void = { _ in }
    ) {
        self.initialSessionID = initialSessionID
        self.activeComposerSessionID = activeComposerSessionID
        self.bottomOverlayClearance = bottomOverlayClearance
        self.draftRegistry = draftRegistry
        self.onDeactivateComposer = onDeactivateComposer
        self.onActivateComposer = onActivateComposer
        _selectedPageSessionID = State(initialValue: initialSessionID)
    }

    var body: some View {
        Group {
            if appState.openSessionIDs.isEmpty {
                ContentUnavailableView(
                    "No Open Sessions",
                    systemImage: "rectangle.split.3x1",
                    description: Text("Choose a session from the session picker or create a new one.")
                )
            } else if let liveStore = appState.liveStore {
                GeometryReader { geometry in
                    let cardWidth = max(geometry.size.width * 0.9, 320)
                    let cardHeight = max(geometry.size.height - bottomOverlayClearance, 320)
                    let horizontalInset = max((geometry.size.width - cardWidth) / 2, 0)

                    sessionScroller(
                        liveStore: liveStore,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        horizontalInset: horizontalInset
                    )
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.windowBackground)
        .themedWindow(theme)
        .onAppear {
            openInitialSessionIfNeeded()
        }
    }

    private var currentSelectedSessionID: String {
        if let focusedSessionID = appState.focusedSessionID, appState.openSessionIDs.contains(focusedSessionID) {
            return focusedSessionID
        }

        if appState.openSessionIDs.contains(initialSessionID) {
            return initialSessionID
        }

        return appState.openSessionIDs.first ?? initialSessionID
    }
    private func openInitialSessionIfNeeded() {
        guard !initialSessionID.isEmpty else { return }
        appState.openSession(initialSessionID)
        appState.focusSession(currentSelectedSessionID)
    }

    private func sessionScroller(
        liveStore: WorkspaceLiveStore,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        horizontalInset: CGFloat
    ) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 9) {
                ForEach(appState.openSessionIDs, id: \.self) { sessionID in
                    let sessionState = liveStore.sessionState(for: sessionID)
                    let draftState = draftRegistry.state(for: sessionID)
                    let isComposerActive = activeComposerSessionID == sessionID

                    IOSSessionColumnView(
                        sessionState: sessionState,
                        draftState: draftState,
                        sessionID: sessionID,
                        isComposerActive: isComposerActive,
                        onActivateComposer: onActivateComposer
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .id(sessionID)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 12)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedPageSessionID, anchor: .center)
        .scrollIndicators(.hidden)
        .onAppear {
            openInitialSessionIfNeeded()
            selectedPageSessionID = currentSelectedSessionID
        }
        .onChange(of: appState.focusedSessionID) { _, newValue in
            guard let newValue, appState.openSessionIDs.contains(newValue) else { return }
            selectedPageSessionID = newValue
        }
        .onChange(of: selectedPageSessionID) { _, newValue in
            guard let newValue, appState.openSessionIDs.contains(newValue) else { return }
            if activeComposerSessionID != nil {
                onDeactivateComposer()
            }
            appState.focusSession(newValue)
        }
        .onChange(of: appState.openSessionIDs) { _, newValue in
            guard !newValue.isEmpty else { return }
            if let selectedPageSessionID, newValue.contains(selectedPageSessionID) {
                return
            }

            selectedPageSessionID = currentSelectedSessionID
        }
        .onChange(of: appState.sessionCenterRequest) { _, newValue in
            guard let newValue, appState.openSessionIDs.contains(newValue.sessionID) else { return }
            selectedPageSessionID = newValue.sessionID
            appState.clearSessionCenterRequest(newValue.id)
        }
    }
}
