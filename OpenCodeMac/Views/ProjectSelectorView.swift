import SwiftUI

struct ProjectSelectorView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @State private var highlightedRemoteDirectorySuggestionIndex: Int? = 0
    @State private var remoteDirectoryCursorLocation = 0
    @State private var remoteDirectorySuggestionAnchor: CGRect = .zero

    private var remoteDirectorySuggestions: [CommandOption] {
        appState.remoteDirectorySuggestionOptions()
    }

    private var normalizedHighlightedRemoteDirectorySuggestionIndex: Int? {
        guard !remoteDirectorySuggestions.isEmpty else { return nil }
        let candidate = highlightedRemoteDirectorySuggestionIndex ?? 0
        return min(max(candidate, 0), remoteDirectorySuggestions.count - 1)
    }

    private func applyRemoteDirectorySuggestion(_ option: CommandOption) {
        appState.applyRemoteDirectorySuggestion(option)
        highlightedRemoteDirectorySuggestionIndex = nil
    }

    var body: some View {
        Group {
            if appState.launchStage == .chooseServerMode {
                launcherLayout
            } else {
                detailLayout
            }
        }
        .foregroundStyle(theme.primaryText)
        .background(theme.windowBackground)
    }

    private var launcherLayout: some View {
        VStack(spacing: 28) {
            Text(title)
                .font(.system(size: 44, weight: .semibold, design: .serif))

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)

            HStack(alignment: .top, spacing: 24) {
                launcherCard(
                    title: "Open Local Directory",
                    subtitle: "Use the native macOS folder picker after checking or starting your local server.",
                    systemImage: "externaldrive.badge.plus",
                    isLoading: appState.isStartingLocalServer,
                    action: appState.openLocalDirectory
                )
                .disabled(appState.isStartingLocalServer)

                launcherCard(
                    title: "Open Remote Directory",
                    subtitle: "Connect to another opencode server, then type the project path you want to open.",
                    systemImage: "network.badge.shield.half.filled",
                    isLoading: false,
                    action: appState.showRemoteServerEntry
                )
                .disabled(appState.isStartingLocalServer)
            }
            .frame(maxWidth: 920)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var detailLayout: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title)
                .font(.system(size: 44, weight: .semibold, design: .serif))

            VStack(alignment: .leading, spacing: 10) {
                Text(subtitle)
                Text(metadataText)
                    .foregroundStyle(theme.secondaryText)
            }
            .font(.title3)

            content
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch appState.launchStage {
        case .checkingLocalServer:
            EmptyView()
        case .chooseServerMode:
            EmptyView()
        case .localFolderSelection:
            EmptyView()
        case .remoteServerEntry:
            VStack(alignment: .leading, spacing: 14) {
                TextField("https://opencode.example.com", text: $appState.remoteServerURLText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 520)
                    .onSubmit {
                        appState.connectToRemoteServer()
                    }

                if !appState.recentRemoteConnections.isEmpty {
                    recentConnectionsSection
                }

                HStack(spacing: 12) {
                    Button("Connect") {
                        appState.connectToRemoteServer()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isValidatingRemoteServer)

                    Button("Back") {
                        appState.resetServerSelection()
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .remoteDirectoryEntry:
            VStack(alignment: .leading, spacing: 14) {
                PromptTextView(
                    text: $appState.remoteDirectoryText,
                    measuredHeight: .constant(PromptTextView.defaultHeight),
                    highlightedSuggestionIndex: $highlightedRemoteDirectorySuggestionIndex,
                    cursorLocation: $remoteDirectoryCursorLocation,
                    suggestions: remoteDirectorySuggestions,
                    suggestionAnchor: $remoteDirectorySuggestionAnchor,
                    placeholder: "/Users/mark/projects/opencode",
                    textColor: theme.primaryTextColor,
                    insertionPointColor: theme.primaryTextColor,
                    placeholderColor: theme.secondaryTextColor,
                    focusRequestID: nil,
                    minLineCount: 1,
                    maxLineCount: 1,
                    onSelectSuggestion: { option in
                        applyRemoteDirectorySuggestion(option)
                    },
                    onFocus: {},
                    onSubmit: {
                        if let option = normalizedHighlightedRemoteDirectorySuggestionIndex.flatMap({ remoteDirectorySuggestions[$0] }) {
                            applyRemoteDirectorySuggestion(option)
                        } else {
                            appState.connectToRemoteDirectory()
                        }
                    }
                )
                .frame(height: 40)
                .padding(4)
                .background(theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 12) {
                    Button("Open Project") {
                        appState.connectToRemoteDirectory()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Change Server") {
                        appState.showRemoteServerEntry()
                    }
                    .buttonStyle(.bordered)
                }

            }
            .background {
                SlashCommandSuggestionOverlayBridge(
                    sessionID: "project-selector-remote-directory",
                    anchor: remoteDirectorySuggestionAnchor,
                    suggestions: remoteDirectorySuggestions,
                    highlightedIndex: normalizedHighlightedRemoteDirectorySuggestionIndex,
                    theme: theme,
                    onSelect: { option in
                        applyRemoteDirectorySuggestion(option)
                    }
                )
            }
        }
    }

    private var recentConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Connections")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(appState.recentRemoteConnections, id: \.self) { connection in
                    Button(connection) {
                        appState.connectToRecentRemoteServer(connection)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.mutedSurfaceBackground)
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
        }
    }

    private var title: String {
        switch appState.launchStage {
        case .chooseServerMode:
            return "Open a Directory"
        case .remoteServerEntry:
            return "Connect to a Server"
        case .remoteDirectoryEntry:
            return "Enter a Project Path"
        default:
            return "Choose a Project"
        }
    }

    private var subtitle: String {
        switch appState.launchStage {
        case .checkingLocalServer:
            return ""
        case .chooseServerMode:
            return "Choose whether to open a local project or connect to a remote opencode server first."
        case .localFolderSelection:
            return ""
        case .remoteServerEntry:
            return "Enter the base URL for the remote opencode server you want to use."
        case .remoteDirectoryEntry:
            return "Enter the project path exposed by the remote opencode server."
        }
    }

    private var metadataText: String {
        switch appState.launchStage {
        case .checkingLocalServer, .chooseServerMode, .localFolderSelection:
            return "Server: `\(OpenCodeAppModel.defaultServerURL.absoluteString)`\nTransport: HTTP + SSE"
        case .remoteServerEntry, .remoteDirectoryEntry:
            return "Server: `\(appState.serverDisplayText)`\nProject selection: typed path"
        }
    }

    private func launcherCard(title: String, subtitle: String, systemImage: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.accentSubtleBackground)
                            .frame(width: 56, height: 56)

                        if isLoading {
                            ProgressView()
                                .controlSize(.regular)
                        } else {
                            Image(systemName: systemImage)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                        }
                    }

                    Text(title)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                }

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .padding(28)
            .background(theme.surfaceBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(theme.border.opacity(0.9), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
