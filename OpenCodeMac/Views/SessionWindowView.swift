import SwiftUI

struct SessionWindowView: View {
    @EnvironmentObject private var appState: OpenCodeAppState

    let sessionID: String

    var body: some View {
        Group {
            if sessionID.isEmpty {
                ContentUnavailableView("No Session", systemImage: "bubble.left.and.text.bubble.right")
            } else if let liveStore = appState.liveStore {
                SessionColumnView(sessionState: liveStore.sessionState(for: sessionID), sessionID: sessionID)
                    .padding(20)
                    .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            FocusedSessionTimelineKeyHandler { direction in
                appState.scrollFocusedSessionTimeline(to: direction)
            }
        )
    }
}
