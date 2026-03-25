import AppKit
import OSLog
import SwiftUI

private extension View {
    @ViewBuilder
    func clipPaneContent(if condition: Bool, cornerRadius: CGFloat) -> some View {
        if condition {
            clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
        }
    }
}

private struct PaneShadowModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        if isFocused {
            content.shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 8)
        } else {
            content
        }
    }
}

struct SessionColumnView: View {
    private static let paneCornerRadius: CGFloat = 24

    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @ObservedObject var sessionState: SessionLiveState

    let sessionID: String
    var chrome: SessionColumnChrome = .pane
    var onPaneDragChanged: ((CGFloat) -> Void)? = nil
    var onPaneDragEnded: (() -> Void)? = nil

    var body: some View {
        let session = sessionState.session
        let messages = sessionState.messages
        let questions = appState.questionForSession(sessionID)
        let permissions = deduplicatedPermissions(sessionState.permissions)
        let chromeName = chrome == .pane ? "pane" : "window"
        let thinkingBannerTitle = latestThinkingBannerTitle(
            session: session,
            messages: messages,
            questions: questions,
            permissions: permissions
        )

        VStack(spacing: 0) {
            if chrome == .pane {
                SessionHeaderView(
                    sessionID: sessionID,
                    session: session,
                    indicator: session?.indicator ?? SessionIndicator.resolve(status: nil, hasPendingPermission: false),
                    contextUsageText: session?.contextUsageText,
                    allowsPaneDrag: chrome == .pane,
                    onPaneDragChanged: onPaneDragChanged,
                    onPaneDragEnded: onPaneDragEnded
                )
                Divider()
            }
            SessionTimelineView(
                sessionID: sessionID,
                messages: messages,
                questions: questions,
                thinkingBannerTitle: thinkingBannerTitle,
                availableSessions: appState.sessions
            )
            Divider()
            SessionComposerView(sessionID: sessionID, permissions: permissions, sessionState: sessionState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipPaneContent(if: chrome == .pane, cornerRadius: Self.paneCornerRadius)
        .background(backgroundView)
        .overlay { overlayView }
        .performanceLayoutProbe("SessionColumnView") {
            "sessionID=\(sessionID) chrome=\(chromeName) messages=\(messages.count) questions=\(questions.count) permissions=\(permissions.count) focused=\(isFocused)"
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.focusSession(sessionID)
        }
    }

    private func deduplicatedPermissions(_ permissions: [PermissionRequest]) -> [PermissionRequest] {
        var seenKeys = Set<SessionPermissionPresentationKey>()
        return permissions.filter { request in
            guard !appState.isPermissionDismissed(request) else { return false }
            let key = SessionPermissionPresentationKey(request: request)
            return seenKeys.insert(key).inserted
        }
    }

    private var borderColor: Color {
        appState.focusedSessionID == sessionID ? theme.accent.opacity(0.85) : theme.border.opacity(0.7)
    }

    private var isFocused: Bool {
        appState.focusedSessionID == sessionID
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch chrome {
        case .pane:
            RoundedRectangle(cornerRadius: Self.paneCornerRadius, style: .continuous)
                .fill(theme.surfaceBackground)
                .modifier(PaneShadowModifier(isFocused: isFocused))
        case .window:
            theme.surfaceBackground
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        if chrome == .pane {
            RoundedRectangle(cornerRadius: Self.paneCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: appState.focusedSessionID == sessionID ? 2 : 1)
        }
    }

    private func latestThinkingBannerTitle(
        session: SessionDisplay?,
        messages: [MessageEnvelope],
        questions: [QuestionRequest],
        permissions: [PermissionRequest]
    ) -> String? {
        guard !ThinkingVisibilityPreferences.showsThinking() else { return nil }
        guard permissions.isEmpty, questions.isEmpty else { return nil }
        guard session?.status?.isThinkingActive == true else { return nil }

        return messages.reversed().compactMap(\.latestReasoningTitle).first
    }
}

enum SessionColumnChrome {
    case pane
    case window
}

private struct SessionHeaderView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let sessionID: String
    let session: SessionDisplay?
    let indicator: SessionIndicator
    let contextUsageText: String?
    var allowsPaneDrag = false
    var onPaneDragChanged: ((CGFloat) -> Void)? = nil
    var onPaneDragEnded: (() -> Void)? = nil

    @State private var isHoveringStatusIcon = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button {
                            appState.closeSession(sessionID)
                        } label: {
                            Group {
                                if isHoveringStatusIcon {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(theme.secondaryText)
                                } else {
                                    SessionStatusIcon(color: indicator.color())
                                }
                            }
                            .frame(width: 14, height: 14)
                            .offset(y: -6)
                        }
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }
                        .buttonStyle(.plain)
                        .help("Close Pane")
                        .onHover { hovering in
                            isHoveringStatusIcon = hovering
                        }

                        Text(session?.title ?? sessionID)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                    }

                    Text(contextUsageText ?? "No context usage yet")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    Button {
                        if let workspaceConnection = appState.workspaceConnection {
                            openWindow(
                                id: "session-window",
                                value: SessionWindowContext(connection: workspaceConnection, sessionID: sessionID)
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.plain)
                }
                .font(.headline)
            }
        }
        .padding(18)
        .modifier(SessionHeaderDragModifier(
            allowsPaneDrag: allowsPaneDrag,
            onPaneDragChanged: onPaneDragChanged,
            onPaneDragEnded: onPaneDragEnded
        ))
    }
}

private struct SessionHeaderDragModifier: ViewModifier {
    let allowsPaneDrag: Bool
    let onPaneDragChanged: ((CGFloat) -> Void)?
    let onPaneDragEnded: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if allowsPaneDrag {
            content
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { value in
                            onPaneDragChanged?(value.translation.width)
                        }
                        .onEnded { _ in
                            onPaneDragEnded?()
                        }
                )
        } else {
            content
        }
    }
}

private struct SessionTimelineView: View {
    struct MessageRenderContext: Equatable {
        let subagentSessionsByPartID: [String: SessionDisplay]
    }

    @Environment(\.openCodeTheme) private var theme

    let sessionID: String
    let messages: [MessageEnvelope]
    let questions: [QuestionRequest]
    let thinkingBannerTitle: String?
    let availableSessions: [SessionDisplay]

    private var latestTodoToolPartID: String? {
        messages
            .reversed()
            .compactMap { message in
                message.toolParts.last(where: \ .isTodoWriteTool)?.id
            }
            .first
    }

    private var messageRenderContexts: [String: MessageRenderContext] {
        Dictionary(uniqueKeysWithValues: messages.map { message in
            let subagentSessionsByPartID = MessagePart.resolveSubagentSessions(
                for: message.toolParts,
                in: availableSessions,
                parentSessionID: message.info.sessionID,
                baseReferenceTimeMS: message.info.time.created
            )
            return (message.id, MessageRenderContext(subagentSessionsByPartID: subagentSessionsByPartID))
        })
    }

    var body: some View {
        let latestTodoToolPartID = PerformanceInstrumentation.measure(
            "timeline-latest-todo",
            thresholdMS: 1,
            details: "sessionID=\(sessionID) messages=\(messages.count)"
        ) {
            self.latestTodoToolPartID
        }
        let messageRenderContexts = PerformanceInstrumentation.measure(
            "timeline-message-render-contexts",
            thresholdMS: 1,
            details: "sessionID=\(sessionID) messages=\(messages.count) sessions=\(availableSessions.count)"
        ) {
            self.messageRenderContexts
        }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    MessageCard(
                        message: message,
                        showsTimestamp: shouldShowTimestamp(for: index),
                        latestTodoToolPartID: latestTodoToolPartID,
                        renderContext: messageRenderContexts[message.id] ?? MessageRenderContext(subagentSessionsByPartID: [:])
                    )
                }

                ForEach(questions) { request in
                    QuestionCard(request: request)
                }

                if let thinkingBannerTitle {
                    ThinkingStatusBanner(title: thinkingBannerTitle)
                        .padding(.top, 4)
                        .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.messageCardPadding))
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
            .padding(18)
        }

        .defaultScrollAnchor(.bottom)
        .background(theme.mutedSurfaceBackground.opacity(0.8))
        .performanceLayoutProbe("SessionTimelineView") {
            "sessionID=\(sessionID) messages=\(messages.count) questions=\(questions.count) thinkingBanner=\(thinkingBannerTitle != nil)"
        }
    }

    private func shouldShowTimestamp(for index: Int) -> Bool {
        guard index > 0 else { return true }
        return messages[index].createdAt.timeIntervalSince(messages[index - 1].createdAt) > 300
    }
}

private struct SessionComposerView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    private static let placeholderOptions = [
        "Let's get started!",
        "What are we working on now?",
        "What should we tackle next?",
        "How can I help?"
    ]

    @State private var promptHeight = PromptTextView.defaultHeight
    @State private var highlightedCommandSuggestionIndex: Int? = 0
    @State private var promptCursorLocation = 0
    @State private var promptSuggestionAnchor: CGRect = .zero
    @State private var placeholderText = Self.placeholderOptions.randomElement() ?? "Let's get started!"
    @State private var lastAutoFocusedPermissionID: String?
    let sessionID: String
    let permissions: [PermissionRequest]

    private var isFocused: Bool {
        appState.focusedSessionID == sessionID
    }

    private var activePermission: PermissionRequest? {
        permissions.first
    }

    private var modelOptions: [ModelOption] {
        appState.modelOptions(for: sessionID)
    }

    private var agentOptions: [AgentOption] {
        appState.agentOptions(for: sessionID)
    }

    private var commandSuggestions: [CommandOption] {
        appState.slashCommandSuggestions(for: sessionID, cursorLocation: promptCursorLocation)
    }

    private var normalizedHighlightedCommandSuggestionIndex: Int? {
        guard !commandSuggestions.isEmpty else { return nil }
        let candidate = highlightedCommandSuggestionIndex ?? 0
        return min(max(candidate, 0), commandSuggestions.count - 1)
    }

    private func applySlashCommandSuggestion(_ option: CommandOption) {
        appState.applySlashCommandSuggestion(option, for: sessionID)
        let updatedDraft = appState.drafts[sessionID, default: ""]
        promptCursorLocation = updatedDraft.utf16.count
        highlightedCommandSuggestionIndex = nil
    }

    private func maybeFocusPermissionPrompt(for permissionID: String?) {
        guard let permissionID else {
            lastAutoFocusedPermissionID = nil
            return
        }

        guard isFocused, lastAutoFocusedPermissionID != permissionID else { return }
        lastAutoFocusedPermissionID = permissionID
        appState.focusSession(sessionID, focusPrompt: true)
    }

    private var composerFocusRequestID: UUID? {
        appState.promptFocusRequest?.sessionID == sessionID ? appState.promptFocusRequest?.id : nil
    }

    private var permissionFocusRequestID: UUID? {
        guard activePermission != nil, isFocused else { return nil }
        return composerFocusRequestID
    }

    private var selectedAgentKey: Binding<String> {
        Binding(
            get: { appState.selectedAgentOption(for: sessionID)?.id ?? agentOptions.first?.id ?? "" },
            set: { appState.setSelectedAgent($0, for: sessionID) }
        )
    }

    private var selectedModelKey: Binding<String> {
        Binding(
            get: { appState.selectedModelOption(for: sessionID)?.id ?? modelOptions.first?.id ?? "" },
            set: { appState.setSelectedModel($0, for: sessionID, updateDefault: MacModifierKeyState.isOptionPressed()) }
        )
    }

    private var thinkingLevels: [String] {
        [OpenCodeAppModel.defaultThinkingLevel] + (appState.selectedModelOption(for: sessionID)?.thinkingLevels ?? [])
    }

    private var selectedThinkingLevel: Binding<String> {
        Binding(
            get: { appState.selectedThinkingLevel(for: sessionID) ?? thinkingLevels.first ?? "" },
            set: { appState.setSelectedThinkingLevel($0, for: sessionID) }
        )
    }

    @ObservedObject private var sessionState: SessionLiveState

    init(sessionID: String, permissions: [PermissionRequest], sessionState: SessionLiveState) {
        self.sessionID = sessionID
        self.permissions = permissions
        _sessionState = ObservedObject(wrappedValue: sessionState)
    }

    var body: some View {
        Group {
            if activePermission == nil {
                VStack(alignment: .leading, spacing: 10) {
                    PromptTextView(
                        text: Binding(
                            get: { appState.drafts[sessionID, default: ""] },
                            set: { appState.setDraft($0, for: sessionID) }
                        ),
                        measuredHeight: $promptHeight,
                        highlightedSuggestionIndex: $highlightedCommandSuggestionIndex,
                        cursorLocation: $promptCursorLocation,
                        suggestions: commandSuggestions,
                        suggestionAnchor: $promptSuggestionAnchor,
                        placeholder: placeholderText,
                        textColor: theme.primaryTextColor,
                        insertionPointColor: theme.primaryTextColor,
                        placeholderColor: theme.secondaryTextColor,
                        focusRequestID: composerFocusRequestID,
                        onSelectSuggestion: { option in
                            applySlashCommandSuggestion(option)
                        },
                        onFocus: {
                            appState.focusSession(sessionID)
                        },
                        onSubmit: {
                            if appState.sendMessage(sessionID: sessionID) {
                                promptHeight = PromptTextView.defaultHeight
                            }
                        }
                    )
                    .frame(height: promptHeight)
                    .padding(4)

                    HStack(spacing: 16) {
                        if !agentOptions.isEmpty {
                            Picker("Agent", selection: selectedAgentKey) {
                                ForEach(agentOptions) { option in
                                    Text(option.menuLabel).tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        if !modelOptions.isEmpty {
                            Picker("Model", selection: selectedModelKey) {
                                ForEach(modelOptions) { option in
                                    Text(option.menuLabel).tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)

                            if let selectedModel = appState.selectedModelOption(for: sessionID), selectedModel.supportsReasoning {
                                Picker("Thinking", selection: selectedThinkingLevel) {
                                    ForEach(thinkingLevels, id: \.self) { level in
                                        Text(level == OpenCodeAppModel.defaultThinkingLevel ? "Default" : level.capitalized).tag(level)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.leading, 0)
                    .padding(.trailing, 6)
                }
                .padding(18)
                .background {
                    SlashCommandSuggestionOverlayBridge(
                        sessionID: sessionID,
                        anchor: promptSuggestionAnchor,
                        suggestions: commandSuggestions,
                        highlightedIndex: normalizedHighlightedCommandSuggestionIndex,
                        theme: theme,
                        onSelect: { option in
                            applySlashCommandSuggestion(option)
                        }
                    )
                }
            } else if let request = activePermission {
                PermissionPromptView(request: request, focusRequestID: permissionFocusRequestID)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            maybeFocusPermissionPrompt(for: activePermission?.id)
        }
        .onChange(of: activePermission?.id) { _, newValue in
            maybeFocusPermissionPrompt(for: newValue)
        }
        .onChange(of: isFocused) { _, newValue in
            guard newValue else { return }
            maybeFocusPermissionPrompt(for: activePermission?.id)
        }
    }
}

struct SuggestionListView: View {
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
                        Text(option.name.hasPrefix("/") ? option.slashName : option.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.primaryText)

                        if let description = option.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }

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

typealias SlashCommandSuggestionsView = SuggestionListView

struct SlashCommandSuggestionOverlayBridge: NSViewRepresentable {
    let sessionID: String
    let anchor: CGRect
    let suggestions: [CommandOption]
    let highlightedIndex: Int?
    let theme: OpenCodeTheme
    let onSelect: (CommandOption) -> Void

    @MainActor
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    @MainActor
    func updateNSView(_ nsView: NSView, context: Context) {
        if suggestions.isEmpty || anchor == .zero {
            SlashCommandSuggestionOverlayController.shared.dismiss(for: sessionID)
        } else {
            SlashCommandSuggestionOverlayController.shared.present(
                for: sessionID,
                anchor: anchor,
                suggestions: suggestions,
                highlightedIndex: highlightedIndex,
                theme: theme,
                onSelect: onSelect
            )
        }
    }

    @MainActor
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        SlashCommandSuggestionOverlayController.shared.dismissAll()
    }
}

@MainActor
private final class SlashCommandSuggestionOverlayController {
    static let shared = SlashCommandSuggestionOverlayController()

    private var panel: NSPanel?
    private var activeSessionID: String?

    func present(
        for sessionID: String,
        anchor: CGRect,
        suggestions: [CommandOption],
        highlightedIndex: Int?,
        theme: OpenCodeTheme,
        onSelect: @escaping (CommandOption) -> Void
    ) {
        guard !suggestions.isEmpty, anchor != .zero else {
            dismiss(for: sessionID)
            return
        }

        let panel = ensurePanel()
        let rowHeight: CGFloat = 34
        let height = min(CGFloat(suggestions.count) * rowHeight + 12, 220)
        let width = max(anchor.width, 360)
        let origin = CGPoint(x: anchor.minX, y: anchor.minY - height - 6)
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
        panel.contentView = NSHostingView(
            rootView: SlashCommandSuggestionsView(theme: theme, suggestions: suggestions, highlightedIndex: highlightedIndex, onSelect: { option in
                onSelect(option)
                self.dismiss(for: sessionID)
            })
        )
        if panel.isVisible == false {
            panel.orderFrontRegardless()
        }
        activeSessionID = sessionID
    }

    func dismiss(for sessionID: String) {
        guard activeSessionID == sessionID else { return }
        panel?.orderOut(nil)
        activeSessionID = nil
    }

    func dismissAll() {
        panel?.orderOut(nil)
        activeSessionID = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

private struct ThinkingStatusBanner: View {
    @Environment(\.openCodeTheme) private var theme
    let title: String

    @State private var visibleTitle: String
    @State private var outgoingTitle: String?
    @State private var clearOutgoingTask: Task<Void, Never>?

    init(title: String) {
        self.title = title
        _visibleTitle = State(initialValue: title)
    }

    private func attributedTitle(_ title: String) -> AttributedString {
        (try? AttributedString(markdown: title)) ?? AttributedString(title)
    }

    private func titleLabel(_ title: String) -> some View {
        Text(attributedTitle(title))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func shimmeringTitle(_ title: String) -> some View {
        titleLabel(title)
            .foregroundStyle(Color(nsColor: theme.secondaryTextColor))
            .overlay {
                TimelineView(.animation) { context in
                    GeometryReader { geometry in
                        let cycle = 1.8
                        let progress = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: cycle) / cycle
                        let shimmerWidth = max(geometry.size.width * 0.5, 28)
                        let travel = geometry.size.width + shimmerWidth

                        LinearGradient(
                            colors: [
                                theme.accent.opacity(0),
                                theme.accent.opacity(0.2),
                                Color.white.opacity(0.95),
                                theme.accent.opacity(0.2),
                                theme.accent.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: shimmerWidth)
                        .offset(x: -shimmerWidth + (travel * progress))
                        .mask(titleLabel(title))
                    }
                }
                .allowsHitTesting(false)
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if let outgoingTitle {
                    titleLabel(outgoingTitle)
                        .foregroundStyle(Color(nsColor: theme.secondaryTextColor))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                shimmeringTitle(visibleTitle)
                    .id(visibleTitle)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
            .clipped()
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .animation(.easeInOut(duration: 0.22), value: visibleTitle)
        .onChange(of: title) { _, newTitle in
            guard newTitle != visibleTitle else { return }

            clearOutgoingTask?.cancel()

            let previousTitle = visibleTitle
            outgoingTitle = previousTitle

            withAnimation(.easeInOut(duration: 0.22)) {
                visibleTitle = newTitle
            }

            clearOutgoingTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled else { return }
                outgoingTitle = nil
            }
        }
        .onDisappear {
            clearOutgoingTask?.cancel()
            clearOutgoingTask = nil
        }
    }
}

private struct SessionPermissionPresentationKey: Hashable {
    let sessionID: String
    let permission: String
    let patterns: [String]
    let always: [String]
    let toolMessageID: String?
    let toolCallID: String?

    init(request: PermissionRequest) {
        sessionID = request.sessionID
        permission = request.permission
        patterns = request.patterns
        always = request.always
        toolMessageID = request.tool?.messageID
        toolCallID = request.tool?.callID
    }
}

private enum TimelineMessageLayout {
    static let textLeadingInset: CGFloat = 20
    static let messageCardPadding: CGFloat = 14
    static let toolCardPadding: CGFloat = 10
    static let promptCardPadding: CGFloat = 14

    static func leadingOffset(for contentPadding: CGFloat) -> CGFloat {
        max(textLeadingInset - contentPadding, 0)
    }
}

private struct MessageCard: View {
    @AppStorage(ThinkingVisibilityPreferences.showsThinkingKey) private var showsThinking = true
    @Environment(\.openCodeTheme) private var theme

    let message: MessageEnvelope
    let showsTimestamp: Bool
    let latestTodoToolPartID: String?
    let renderContext: SessionTimelineView.MessageRenderContext

    @State private var bodyEvaluationCount = 0
    @State private var previousBodyVisibleTextBytes = 0
    @State private var previousBodyReasoningTextBytes = 0
    @State private var previousResolvedSubagentCount = 0

    var body: some View {
        let _ = recordBodyEvaluation()
        let textParts = PerformanceInstrumentation.measure(
            "message-card-text-parts",
            thresholdMS: 1,
            details: "sessionID=\(message.info.sessionID) messageID=\(message.id)"
        ) {
            message.textParts
        }
        let reasoningParts = PerformanceInstrumentation.measure(
            "message-card-reasoning-parts",
            thresholdMS: 1,
            details: "sessionID=\(message.info.sessionID) messageID=\(message.id)"
        ) {
            message.reasoningParts
        }
        let toolParts = PerformanceInstrumentation.measure(
            "message-card-tool-parts",
            thresholdMS: 1,
            details: "sessionID=\(message.info.sessionID) messageID=\(message.id)"
        ) {
            message.toolParts
        }
        let subagentSessionsByPartID = renderContext.subagentSessionsByPartID
        let _ = recordRenderContext(
            toolPartCount: toolParts.count,
            resolvedPartCount: subagentSessionsByPartID.count
        )
        let visibleText = PerformanceInstrumentation.measure(
            "message-card-visible-text",
            thresholdMS: 1,
            details: "sessionID=\(message.info.sessionID) messageID=\(message.id) textParts=\(textParts.count)"
        ) {
            message.visibleText
        }
        let reasoningText = PerformanceInstrumentation.measure(
            "message-card-reasoning-text",
            thresholdMS: 1,
            details: "sessionID=\(message.info.sessionID) messageID=\(message.id) reasoningParts=\(reasoningParts.count)"
        ) {
            message.reasoningText
        }
        let showsMessageBubble = !visibleText.isEmpty
            || (showsThinking && !reasoningText.isEmpty)
            || (message.stepFinish?.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame && message.stepFinish != nil)
            || message.info.error != nil
        let rendersMarkdownText = textParts.allSatisfy {
            $0.shouldRenderMarkdown(for: message.info.role, messageIsCompleted: message.isCompleted)
        }
        let rendersMarkdownReasoning = reasoningParts.allSatisfy {
            $0.shouldRenderMarkdown(for: message.info.role, messageIsCompleted: message.isCompleted)
        }
        let renderedMessageText = PerformanceInstrumentation.measure(
            "message-card-render-visible-text",
            thresholdMS: 1,
            details: "sessionID=\(message.info.sessionID) messageID=\(message.id) bytes=\(visibleText.utf8.count) markdown=\(rendersMarkdownText)"
        ) {
            MarkdownTextRenderer.render(
                text: visibleText,
                rendersMarkdown: rendersMarkdownText,
                theme: theme,
                style: .body(theme: theme)
            )
        }
        let renderedReasoningText = PerformanceInstrumentation.measure(
            "message-card-render-reasoning-text",
            thresholdMS: 1,
            details: "sessionID=\(message.info.sessionID) messageID=\(message.id) bytes=\(reasoningText.utf8.count) markdown=\(rendersMarkdownReasoning)"
        ) {
            MarkdownTextRenderer.render(
                text: reasoningText,
                rendersMarkdown: rendersMarkdownReasoning,
                theme: theme,
                style: .callout(theme: theme)
            )
        }

        VStack(alignment: .leading, spacing: 8) {
            if showsTimestamp {
                MessageCardHeader(message: message)
            }

            if showsMessageBubble {
                VStack(alignment: .leading, spacing: 10) {
                    if !visibleText.isEmpty {
                        SelectableMessageTextView(
                            attributedText: renderedMessageText,
                            linkColor: theme.accentColor
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showsThinking, !reasoningText.isEmpty {
                        SelectableMessageTextView(
                            attributedText: renderedReasoningText,
                            linkColor: theme.accentColor
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let finish = message.stepFinish, finish.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame {
                        MessageFinishView(part: finish)
                    }

                    if message.info.error != nil {
                        Text(message.info.error?.prettyDescription ?? "Unknown error")
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(theme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(TimelineMessageLayout.messageCardPadding)
                .background(bubbleBackground)
                .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.messageCardPadding))
            }

            ForEach(toolParts) { toolPart in
                ToolPartView(
                    part: toolPart,
                    subagentSession: subagentSessionsByPartID[toolPart.id],
                    latestTodoToolPartID: latestTodoToolPartID
                )
                    .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.toolCardPadding))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .performanceLayoutProbe("MessageCard") {
            "sessionID=\(message.info.sessionID) messageID=\(message.id) role=\(message.info.role.rawString) parts=\(message.parts.count) toolParts=\(message.toolParts.count)"
        }
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(message.info.role.isAssistant ? theme.assistantBubble : theme.userBubble)
    }

    private func recordBodyEvaluation() {
        bodyEvaluationCount += 1

        let visibleTextBytes = message.visibleText.utf8.count
        let reasoningTextBytes = message.reasoningText.utf8.count
        let visibleTextChanged = visibleTextBytes != previousBodyVisibleTextBytes
        let reasoningTextChanged = reasoningTextBytes != previousBodyReasoningTextBytes
        let resolvedSubagentCount = renderContext.subagentSessionsByPartID.count
        let resolvedSubagentCountChanged = resolvedSubagentCount != previousResolvedSubagentCount

        if bodyEvaluationCount == 1 || visibleTextChanged || reasoningTextChanged || resolvedSubagentCountChanged || bodyEvaluationCount.isMultiple(of: 25) {
            PerformanceInstrumentation.log(
                "message-card-body-eval sessionID=\(message.info.sessionID) messageID=\(message.id) count=\(bodyEvaluationCount) visibleBytes=\(visibleTextBytes) visibleChanged=\(visibleTextChanged) reasoningBytes=\(reasoningTextBytes) reasoningChanged=\(reasoningTextChanged) resolvedSubagents=\(resolvedSubagentCount) resolvedSubagentsChanged=\(resolvedSubagentCountChanged)"
            )
        }

        previousBodyVisibleTextBytes = visibleTextBytes
        previousBodyReasoningTextBytes = reasoningTextBytes
        previousResolvedSubagentCount = resolvedSubagentCount
    }

    private func recordRenderContext(toolPartCount: Int, resolvedPartCount: Int) {
        PerformanceInstrumentation.log(
            "message-card-render-context sessionID=\(message.info.sessionID) messageID=\(message.id) toolParts=\(toolPartCount) resolved=\(resolvedPartCount) visibleBytes=\(message.visibleText.utf8.count) reasoningBytes=\(message.reasoningText.utf8.count)"
        )
    }
}

private struct MessageCardHeader: View {
    @Environment(\.openCodeTheme) private var theme
    let message: MessageEnvelope

    var body: some View {
        Text(Self.timestampFormatter.string(from: message.createdAt))
            .frame(maxWidth: .infinity, alignment: .center)
        .font(.caption.weight(.medium))
        .foregroundStyle(theme.secondaryText)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct MessageFinishView: View {
    @Environment(\.openCodeTheme) private var theme
    let part: MessagePart

    var body: some View {
        HStack(spacing: 12) {
            Text(part.reason?.capitalized ?? "Finished")
            if let total = part.tokens?.total {
                Text("\(total) tokens")
            }
            if let cost = part.cost {
                Text(String(format: "$%.4f", cost))
            }
        }
        .font(.caption)
        .foregroundStyle(theme.secondaryText)
    }
}

private struct ToolPartView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    let part: MessagePart
    let subagentSession: SessionDisplay?
    let latestTodoToolPartID: String?
    @State private var isExpanded = false
    @State private var detailedPart: MessagePart?

    private var presentation: ToolPresentation {
        resolvedPart.toolPresentation
    }

    private var resolvedPart: MessagePart {
        detailedPart ?? part
    }

    private var statusLabel: String? {
        presentation.statusLabel
    }

    private var shouldAutoExpand: Bool {
        resolvedPart.isTodoWriteTool && resolvedPart.id == latestTodoToolPartID
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                        ToolSummaryView(style: presentation.summaryStyle)

                    Spacer(minLength: 8)

                    if let statusLabel {
                        Text(statusLabel)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }

                    if let subagentSession {
                        Button {
                            guard let workspaceConnection = appState.workspaceConnection else { return }
                            openWindow(
                                id: "session-window",
                                value: SessionWindowContext(connection: workspaceConnection, sessionID: subagentSession.id)
                            )
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Open subagent session")
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ToolPartDrawerView(part: resolvedPart)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            cardShape
                .fill(theme.toolCardBackground)
        )
        .clipShape(cardShape)
        .overlay(
            cardShape
                .stroke(theme.border.opacity(0.6), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard part.isTodoWriteTool else { return }
            isExpanded = shouldAutoExpand
        }
        .task(id: isExpanded) {
            guard isExpanded, part.hasDeferredDetail, detailedPart == nil else { return }
            detailedPart = await PersistenceRepository.shared.loadMessagePartDetail(partID: part.id)
        }
        .onChange(of: latestTodoToolPartID) { _, _ in
            guard part.isTodoWriteTool else { return }

            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = shouldAutoExpand
            }
        }
    }
}

private struct ToolSummaryView: View {
    let style: ToolSummaryStyle

    var body: some View {
        switch style {
        case let .standard(summary):
            StandardToolSummaryView(summary: summary)
        case let .patch(summary):
            PatchToolSummaryView(summary: summary)
        case let .read(summary):
            ReadToolSummaryView(summary: summary)
        case let .task(summary):
            TaskToolSummaryView(summary: summary)
        }
    }
}

private struct StandardToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolCallSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ToolSummaryIcon(systemName: summary.iconSystemName ?? ToolCallSummary.genericIconSystemName)

            Text(summary.action)
                .fontWeight(.semibold)

            if let target = summary.target {
                Text(verbatim: "`\(target)`")
                    .font(.caption.monospaced())
            }

            if let additions = summary.additions {
                Text("+\(additions)")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.diffAddition)
            }

            if let deletions = summary.deletions {
                Text("-\(deletions)")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.diffDeletion)
            }
        }
        .font(.caption)
    }
}

private struct PatchToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolPatchSummary

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ToolSummaryIcon(systemName: "pencil")

            Text("Patch")
                .fontWeight(.semibold)

            if let target = summary.target {
                Text(verbatim: "`\(target)`")
                    .font(.caption.monospaced())
            }

            if let additions = summary.additions {
                summaryBadge(text: "+\(additions)", tint: theme.diffAddition, background: theme.diffAdditionBackground)
            }

            if let deletions = summary.deletions {
                summaryBadge(text: "-\(deletions)", tint: theme.diffDeletion, background: theme.diffDeletionBackground)
            }
        }
        .font(.caption)
    }

    private func summaryBadge(text: String, tint: Color, background: Color) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
    }
}

private struct ToolSummaryIcon: View {
    @Environment(\.openCodeTheme) private var theme
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.secondaryText)
            .frame(width: 14, alignment: .center)
    }
}

private struct ReadToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolReadSummary

    private var text: String {
        summary.fileName ?? summary.path ?? "Read"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ToolSummaryIcon(systemName: "eyeglasses")

            Text("Read")
                .fontWeight(.semibold)

            Text(verbatim: "`\(text)`")
                .font(.caption.monospaced())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            .frame(maxWidth: 220, alignment: .leading)
            .clipped()
        }
        .font(.caption)
    }
}

private struct TaskToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolTaskSummary

    private var text: String {
        summary.target ?? summary.title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ToolSummaryIcon(systemName: "square.stack.3d.up")

            Text(summary.title)
                .fontWeight(.semibold)

            Text(verbatim: "`\(text)`")
                .font(.caption.monospaced())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            .frame(maxWidth: 260, alignment: .leading)
            .clipped()
        }
        .font(.caption)
    }
}

private struct ToolPartDrawerView: View {
    @Environment(\.openCodeTheme) private var theme
    let part: MessagePart

    var body: some View {
        let presentation = part.toolPresentation

        VStack(alignment: .leading, spacing: 10) {
            if let title = part.toolDrawerTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            ForEach(presentation.detailFields) { field in
                ToolPartDetailSection(title: field.title, value: field.value)
            }

            switch presentation.drawerStyle {
            case .standard:
                EmptyView()
            case let .patch(detail):
                PatchToolDetailView(detail: detail)
            case let .todo(detail):
                TodoToolDetailView(detail: detail)
            }

            if let output = part.state?.output, !output.isEmpty, !presentation.drawerStyle.hidesRawOutput {
                ToolPartDetailSection(title: "Result", value: output)
            }

            if let error = part.state?.error, !error.isEmpty {
                ToolPartDetailSection(title: "Error", value: error, isError: true)
            }

            if let fallbackDetail = presentation.fallbackDetail {
                Text(fallbackDetail)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }
}

private struct TodoToolDetailView: View {
    let detail: ToolTodoDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(detail.items) { item in
                TodoChecklistRow(item: item)
            }
        }
    }
}

private struct TodoChecklistRow: View {
    @Environment(\.openCodeTheme) private var theme
    let item: ToolTodoItem

    private var marker: String {
        switch item.status {
        case .completed:
            return "[✓]"
        case .inProgress:
            return "[•]"
        case .pending, .cancelled, .unknown:
            return "[ ]"
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        switch item.status {
        case .completed:
            return AnyShapeStyle(theme.secondaryText)
        case .inProgress:
            return AnyShapeStyle(theme.accent)
        case .pending, .cancelled, .unknown:
            return AnyShapeStyle(theme.primaryText)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.caption.monospaced())
                .foregroundStyle(foregroundStyle)

            Text(item.content)
                .font(.caption)
                .foregroundStyle(foregroundStyle)
                .strikethrough(item.status == .completed, color: theme.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PatchToolDetailView: View {
    let detail: ToolPatchDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(detail.files) { file in
                PatchFileCardView(file: file)
            }
        }
    }
}

private struct PatchFileCardView: View {
    @Environment(\.openCodeTheme) private var theme
    let file: ToolPatchFile

    private var title: String {
        file.destinationPath ?? file.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))

                Text(file.operation.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.mutedSurfaceBackground)
                    )

                if let destinationPath = file.destinationPath, destinationPath != file.path {
                    Text("from \(file.path)")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(file.hunks) { hunk in
                    PatchHunkView(hunk: hunk)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.codeBlockBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct PatchHunkView: View {
    @Environment(\.openCodeTheme) private var theme
    let hunk: ToolPatchHunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = hunk.header {
                Text(header)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 1) {
                ForEach(hunk.lines) { line in
                    PatchDiffLineView(line: line)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.toolCardBackground.opacity(0.7))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PatchDiffLineView: View {
    @Environment(\.openCodeTheme) private var theme
    let line: ToolPatchLine

    private var symbol: String {
        switch line.kind {
        case .context:
            return " "
        case .addition:
            return "+"
        case .deletion:
            return "-"
        }
    }

    private var foreground: Color {
        switch line.kind {
        case .context:
            return theme.primaryText
        case .addition:
            return theme.diffAddition
        case .deletion:
            return theme.diffDeletion
        }
    }

    private var background: Color {
        switch line.kind {
        case .context:
            return .clear
        case .addition:
            return theme.diffAdditionBackground
        case .deletion:
            return theme.diffDeletionBackground
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(symbol)
                .foregroundStyle(foreground)
                .frame(width: 12, alignment: .leading)

            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(background)
    }
}

private struct ToolPartDetailSection: View {
    @Environment(\.openCodeTheme) private var theme
    let title: String
    let value: String
    var isError = false

    private var resolvedTextColor: NSColor {
        isError ? theme.errorColor : theme.primaryTextColor
    }

    private var contentHeight: CGFloat {
        SelectableToolTextView(text: value, textColor: resolvedTextColor).idealHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            SelectableToolTextView(
                text: value,
                textColor: resolvedTextColor
            )
            .frame(maxWidth: .infinity, minHeight: 28, idealHeight: contentHeight, maxHeight: 110)
        }
    }
}

private struct PermissionPromptView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel

    @Environment(\.openCodeTheme) private var theme

    let request: PermissionRequest
    let focusRequestID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permission Needed")
                .font(.headline)
            Text(request.permission)
                .font(.subheadline.weight(.medium))
            if !request.patterns.isEmpty {
                Text(request.patterns.joined(separator: "\n"))
                    .font(.caption.monospaced())
            }
            PermissionPromptButtonRow(
                focusRequestID: focusRequestID,
                onDeny: { appState.answerPermission(request, reply: .reject) },
                onAllowAlways: { appState.answerPermission(request, reply: .always) },
                onAllowOnce: { appState.answerPermission(request, reply: .once) }
            )
            .frame(height: 32)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.errorBackground)
    }
}

private struct PermissionPromptButtonRow: NSViewRepresentable {
    let focusRequestID: UUID?
    let onDeny: () -> Void
    let onAllowAlways: () -> Void
    let onAllowOnce: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSStackView {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8

        let denyButton = NSButton(title: "Deny", target: context.coordinator, action: #selector(Coordinator.handleDeny))
        denyButton.bezelStyle = .rounded
        denyButton.contentTintColor = .systemRed

        let allowAlwaysButton = NSButton(title: "Allow Always", target: context.coordinator, action: #selector(Coordinator.handleAllowAlways))
        allowAlwaysButton.bezelStyle = .rounded

        let allowOnceButton = NSButton(title: "Allow once", target: context.coordinator, action: #selector(Coordinator.handleAllowOnce))
        allowOnceButton.bezelStyle = .rounded
        allowOnceButton.keyEquivalent = "\r"
        allowOnceButton.keyEquivalentModifierMask = []

        stackView.addArrangedSubview(denyButton)
        stackView.addArrangedSubview(allowAlwaysButton)
        stackView.addArrangedSubview(allowOnceButton)

        context.coordinator.allowOnceButton = allowOnceButton
        context.coordinator.denyAction = onDeny
        context.coordinator.allowAlwaysAction = onAllowAlways
        context.coordinator.allowOnceAction = onAllowOnce

        return stackView
    }

    func updateNSView(_ nsView: NSStackView, context: Context) {
        context.coordinator.denyAction = onDeny
        context.coordinator.allowAlwaysAction = onAllowAlways
        context.coordinator.allowOnceAction = onAllowOnce

        guard let focusRequestID, focusRequestID != context.coordinator.lastAppliedFocusRequestID else { return }
        context.coordinator.lastAppliedFocusRequestID = focusRequestID
        context.coordinator.requestFocus()
    }

    @MainActor
    final class Coordinator: NSObject {
        var lastAppliedFocusRequestID: UUID?
        weak var allowOnceButton: NSButton?
        var denyAction: (() -> Void)?
        var allowAlwaysAction: (() -> Void)?
        var allowOnceAction: (() -> Void)?

        private var remainingFocusAttempts = 0
        private let maximumFocusAttempts = 6

        @objc
        func handleDeny() {
            denyAction?()
        }

        @objc
        func handleAllowAlways() {
            allowAlwaysAction?()
        }

        @objc
        func handleAllowOnce() {
            allowOnceAction?()
        }

        func requestFocus() {
            remainingFocusAttempts = maximumFocusAttempts
            attemptFocus()
        }

        private func attemptFocus() {
            guard remainingFocusAttempts > 0 else { return }
            remainingFocusAttempts -= 1

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.focusDefaultButtonIfAvailable() {
                    self.remainingFocusAttempts = 0
                    return
                }

                self.attemptFocus()
            }
        }

        private func focusDefaultButtonIfAvailable() -> Bool {
            guard let button = allowOnceButton, let window = button.window else { return false }
            window.makeFirstResponder(button)
            return window.firstResponder === button
        }
    }
}

private struct QuestionCard: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let request: QuestionRequest
    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Question")
                .font(.headline)

            ForEach(request.questions) { question in
                QuestionGroupView(question: question, selections: $selections)
            }

            HStack {
                Button("Submit") {
                    let answers = request.questions.map { question in
                        Array(selections[question.id, default: []])
                    }
                    appState.answerQuestion(request, answers: answers)
                }
                .buttonStyle(.borderedProminent)

                Button("Reject", role: .destructive) {
                    appState.rejectQuestion(request)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.accentSubtleBackground)
        )
        .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.promptCardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuestionGroupView: View {
    @Environment(\.openCodeTheme) private var theme
    let question: QuestionRequest.Question
    @Binding var selections: [String: Set<String>]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.header)
                .font(.subheadline.weight(.semibold))
            Text(question.question)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            ForEach(question.options, id: \.id) { option in
                Toggle(isOn: Binding(
                    get: { selections[question.id, default: []].contains(option.label) },
                    set: { newValue in
                        if question.multiple == true {
                            if newValue {
                                selections[question.id, default: []].insert(option.label)
                            } else {
                                selections[question.id, default: []].remove(option.label)
                            }
                        } else {
                            selections[question.id] = newValue ? [option.label] : []
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                        Text(option.description)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}
