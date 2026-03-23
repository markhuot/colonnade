import SwiftUI

struct SessionWindowView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let sessionID: String

    var body: some View {
        Group {
            if sessionID.isEmpty {
                ContentUnavailableView("No Session", systemImage: "bubble.left.and.text.bubble.right")
            } else if let liveStore = appState.liveStore {
                SessionColumnView(sessionState: liveStore.sessionState(for: sessionID), sessionID: sessionID)
                    .padding(20)
                    .background(theme.windowBackground)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(theme.primaryText)
        .background(theme.windowBackground)
        .themedWindow(theme)
        .background(
            FocusedSessionTimelineKeyHandler { direction in
                appState.scrollFocusedSessionTimeline(to: direction)
            }
        )
    }
}
