import SwiftUI

struct SessionWindowView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @State private var draftRegistry = SessionDraftRegistry()

    let sessionID: String

    var body: some View {
        Group {
            if sessionID.isEmpty {
                ContentUnavailableView("No Session", systemImage: "bubble.left.and.text.bubble.right")
            } else if let liveStore = appState.liveStore {
                SessionColumnView(
                    sessionState: liveStore.sessionState(for: sessionID),
                    draftState: draftRegistry.state(for: sessionID),
                    sessionID: sessionID,
                    chrome: .window
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.windowBackground)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(theme.primaryText)
        .overlay(alignment: .topTrailing) {
            if let liveStore = appState.liveStore {
                SSEDebugOverlay(liveStore: liveStore)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
            }
        }
        .background(theme.windowBackground)
        .themedWindow(theme)
    }
}
