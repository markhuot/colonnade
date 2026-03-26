import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IOSProjectSelectorView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @State private var isRemoteDirectoryFocused = false
    @State private var remoteDirectoryPromptHeight: CGFloat = 44
    @State private var highlightedRemoteDirectorySuggestionIndex: Int? = 0

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
        highlightedRemoteDirectorySuggestionIndex = 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(theme.secondaryText)

                switch appState.launchStage {
                case .remoteDirectoryEntry:
                    remoteDirectorySection
                case .chooseServerMode, .checkingLocalServer, .localFolderSelection, .remoteServerEntry:
                    remoteServerSection
                }
            }
            .padding(20)
        }
        .background(theme.windowBackground)
    }

    private var title: String {
        switch appState.launchStage {
        case .remoteServerEntry:
            return "Connect to a Server"
        case .remoteDirectoryEntry:
            return "Open a Remote Project"
        default:
            return "Connect to a Server"
        }
    }

    private var subtitle: String {
        switch appState.launchStage {
        case .remoteServerEntry:
            return "Enter the base URL for the opencode server you want to use from iOS."
        case .remoteDirectoryEntry:
            return "Enter the project path exposed by that server."
        default:
            return "Connect to a remote opencode server to browse projects from iOS."
        }
    }

    private var remoteServerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("https://opencode.example.com", text: $appState.remoteServerURLText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !appState.recentRemoteConnections.isEmpty {
                recentConnectionsSection
            }

            Button("Connect") {
                appState.connectToRemoteServer()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isValidatingRemoteServer)

            if appState.supportsLocalServerSelection {
                Button("Back") {
                    appState.resetServerSelection()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var remoteDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !appState.recentProjectDirectories.isEmpty {
                recentProjectsSection
            }

            IOSPromptTextEditor(
                text: $appState.remoteDirectoryText,
                isFocused: $isRemoteDirectoryFocused,
                measuredHeight: $remoteDirectoryPromptHeight,
                highlightedSuggestionIndex: $highlightedRemoteDirectorySuggestionIndex,
                focusRequestID: nil,
                textColor: theme.primaryTextColor,
                placeholderColor: theme.secondaryTextColor,
                suggestions: remoteDirectorySuggestions,
                allowsNewlines: false,
                accessoryContent: {
                    if isRemoteDirectoryFocused && !remoteDirectorySuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.secondaryText)

                            IOSSuggestionListView(
                                theme: theme,
                                suggestions: remoteDirectorySuggestions,
                                highlightedIndex: normalizedHighlightedRemoteDirectorySuggestionIndex,
                                onSelect: { option in
                                    applyRemoteDirectorySuggestion(option)
                                }
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .background(theme.windowBackground)
                    }
                },
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
                },
                onKeyboardDismiss: {}
            )
            .frame(minHeight: 44, idealHeight: remoteDirectoryPromptHeight, maxHeight: max(remoteDirectoryPromptHeight, 44))
            .background(theme.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button("Open Project") {
                appState.connectToRemoteDirectory()
            }
            .buttonStyle(.borderedProminent)

            Button("Back") {
                appState.showRemoteServerEntry()
            }
            .buttonStyle(.bordered)

        }
    }

    private var recentConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Connections")
                .font(.headline)

            ForEach(appState.recentRemoteConnections, id: \.self) { connection in
                Button(connection) {
                    appState.connectToRecentRemoteServer(connection)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Projects")
                .font(.headline)

            ForEach(appState.recentProjectDirectories, id: \.self) { directory in
                Button(directory) {
                    appState.connectToRecentProjectDirectory(directory)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(theme.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct IOSSuggestionListView: View {
    let theme: OpenCodeTheme
    let suggestions: [CommandOption]
    let highlightedIndex: Int?
    let onSelect: (CommandOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, option in
                Button {
                    onSelect(option)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(option.name)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(index == highlightedIndex ? theme.accentSubtleBackground : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border.opacity(0.7), lineWidth: 1)
        )
    }
}
