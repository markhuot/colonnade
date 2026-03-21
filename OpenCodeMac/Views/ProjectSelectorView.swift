import SwiftUI

struct ProjectSelectorView: View {
    @EnvironmentObject private var appState: OpenCodeAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Choose a Project Folder")
                .font(.system(size: 44, weight: .semibold, design: .serif))

            VStack(alignment: .leading, spacing: 10) {
                Text("Choose a project folder to scope every opencode request by directory.")
                Text("Server: `http://127.0.0.1:4096`\nTransport: HTTP + SSE\nPrimary model: sessions as chat threads")
                    .foregroundStyle(.secondary)
            }
            .font(.title3)

            Button {
                appState.chooseDirectory()
            } label: {
                Label("Choose Project Folder", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
