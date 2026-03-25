import SwiftUI

struct SessionWindowView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let sessionID: String

    var body: some View {
        let selectedDirectoryText = appState.selectedDirectory ?? "nil"

        Group {
            if sessionID.isEmpty {
                ContentUnavailableView("No Session", systemImage: "bubble.left.and.text.bubble.right")
            } else if let liveStore = appState.liveStore {
                SessionColumnView(
                    sessionState: liveStore.sessionState(for: sessionID),
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
        .background(theme.windowBackground)
        .performanceLayoutProbe("SessionWindowView") {
            "sessionID=\(sessionID) selectedDirectory=\(selectedDirectoryText) isLoading=\(appState.isLoading)"
        }
        .themedWindow(theme)
    }
}
