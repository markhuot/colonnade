import OSLog
import SwiftUI
import Textual

private struct MarkdownContentView: View {
    @Environment(\.openCodeTheme) private var theme

    let text: String
    let messageRole: MessageRole
    var rendersMarkdown: Bool = true
    var baseFont: Font? = nil
    var foregroundStyle: AnyShapeStyle? = nil

    private var contentAlignment: Alignment {
        messageRole.isAssistant ? .leading : .trailing
    }

    var body: some View {
        Group {
            if rendersMarkdown {
                StructuredText(markdown: text)
                    .textual.structuredTextStyle(.gitHub)
                    .textual.highlighterTheme(theme.highlighterTheme)
                    .textual.codeBlockStyle(
                        OpenCodeCodeBlockStyle(
                            foregroundStyle: foregroundStyle,
                            backgroundColor: messageRole.isAssistant ? theme.codeBlockBackground : theme.userBubble,
                            alignment: contentAlignment
                        )
                    )
            } else {
                Text(verbatim: text)
            }
        }
        .font(baseFont)
        .applyForegroundStyle(foregroundStyle)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: contentAlignment)
    }
}

private struct OpenCodeCodeBlockStyle: StructuredText.CodeBlockStyle {
    var foregroundStyle: AnyShapeStyle?
    var backgroundColor: Color
    var alignment: Alignment

    func makeBody(configuration: Configuration) -> some View {
        ScrollView(.horizontal) {
            configuration.label
                .font(.system(.body, design: .monospaced))
                .applyForegroundStyle(foregroundStyle)
                .textSelection(.enabled)
                .textual.padding(.horizontal, .fontScaled(0.75))
                .textual.padding(.vertical, .fontScaled(0.6))
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .textual.blockSpacing(.fontScaled(top: 0.4, bottom: 0.8))
    }
}

private extension View {
    @ViewBuilder
    func applyForegroundStyle(_ style: AnyShapeStyle?) -> some View {
        if let style {
            foregroundStyle(style)
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
        let questions = sessionState.questions
        let permissions = deduplicatedPermissions(sessionState.permissions)
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
                thinkingBannerTitle: thinkingBannerTitle
            )
            Divider()
            SessionComposerView(sessionID: sessionID, permissions: permissions, sessionState: sessionState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(backgroundView)
        .overlay { overlayView }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.focusSession(sessionID)
        }
    }

    private func deduplicatedPermissions(_ permissions: [PermissionRequest]) -> [PermissionRequest] {
        var seenKeys = Set<SessionPermissionPresentationKey>()
        return permissions.filter { request in
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.surfaceBackground)
                .modifier(PaneShadowModifier(isFocused: isFocused))
        case .window:
            theme.surfaceBackground
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        if chrome == .pane {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(borderColor, lineWidth: appState.focusedSessionID == sessionID ? 2 : 1)
        }
    }

    private func latestThinkingBannerTitle(
        session: SessionDisplay?,
        messages: [MessageEnvelope],
        questions: [QuestionRequest],
        permissions: [PermissionRequest]
    ) -> String? {
        guard !UserDefaults.standard.bool(forKey: "showsThinking") else { return nil }
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
    @Environment(\.openCodeTheme) private var theme

    let sessionID: String
    let messages: [MessageEnvelope]
    let questions: [QuestionRequest]
    let thinkingBannerTitle: String?

    private var latestTodoToolPartID: String? {
        messages
            .reversed()
            .compactMap { message in
                message.toolParts.last(where: \ .isTodoWriteTool)?.id
            }
            .first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    MessageCard(
                        message: message,
                        showsTimestamp: shouldShowTimestamp(for: index),
                        latestTodoToolPartID: latestTodoToolPartID
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
    @State private var placeholderText = Self.placeholderOptions.randomElement() ?? "Let's get started!"

    let sessionID: String
    let permissions: [PermissionRequest]

    private var activePermission: PermissionRequest? {
        permissions.first
    }

    private var modelOptions: [ModelOption] {
        appState.modelOptions(for: sessionID)
    }

    private var agentOptions: [AgentOption] {
        appState.agentOptions(for: sessionID)
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
                        placeholder: placeholderText,
                        textColor: theme.primaryTextColor,
                        insertionPointColor: theme.primaryTextColor,
                        placeholderColor: theme.secondaryTextColor,
                        focusRequestID: appState.promptFocusRequest?.sessionID == sessionID ? appState.promptFocusRequest?.id : nil,
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
            } else if let request = activePermission {
                PermissionPromptView(request: request)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
    @AppStorage("showsThinking") private var showsThinking = true
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let message: MessageEnvelope
    let showsTimestamp: Bool
    let latestTodoToolPartID: String?

    private var subagentSessionsByPartID: [String: SessionDisplay] {
        MessagePart.resolveSubagentSessions(
            for: message.toolParts,
            in: appState.sessions,
            parentSessionID: message.info.sessionID,
            baseReferenceTimeMS: message.info.time.created
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTimestamp {
                MessageCardHeader(message: message)
            }

            if showsMessageBubble {
                VStack(alignment: .leading, spacing: 10) {
                    if !message.textParts.isEmpty {
                        ForEach(message.textParts) { part in
                            if let text = part.text, !text.isEmpty {
                                MarkdownContentView(
                                    text: text,
                                    messageRole: message.info.role,
                                    rendersMarkdown: part.shouldRenderMarkdown(
                                        for: message.info.role,
                                        messageIsCompleted: message.isCompleted
                                    )
                                )
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if showsThinking, !message.reasoningParts.isEmpty {
                        ForEach(message.reasoningParts) { part in
                            if let text = part.text, !text.isEmpty {
                                MarkdownContentView(
                                    text: text,
                                    messageRole: message.info.role,
                                    rendersMarkdown: part.shouldRenderMarkdown(
                                        for: message.info.role,
                                        messageIsCompleted: message.isCompleted
                                    ),
                                    baseFont: .callout,
                                    foregroundStyle: AnyShapeStyle(.secondary)
                                )
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
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

            ForEach(message.toolParts) { toolPart in
                ToolPartView(
                    part: toolPart,
                    subagentSession: subagentSessionsByPartID[toolPart.id],
                    latestTodoToolPartID: latestTodoToolPartID
                )
                    .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.toolCardPadding))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(message.info.role.isAssistant ? theme.assistantBubble : theme.userBubble)
    }

    private var showsMessageBubble: Bool {
        !message.visibleText.isEmpty
            || (showsThinking && !message.reasoningText.isEmpty)
            || (message.stepFinish?.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame && message.stepFinish != nil)
            || message.info.error != nil
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

    private var presentation: ToolPresentation {
        part.toolPresentation
    }

    private var statusLabel: String? {
        presentation.statusLabel
    }

    private var shouldAutoExpand: Bool {
        part.isTodoWriteTool && part.id == latestTodoToolPartID
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
                ToolPartDrawerView(part: part)
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
            HStack {
                Button("Deny", role: .destructive) {
                    appState.answerPermission(request, reply: .reject)
                }

                Button("Allow Always") {
                    appState.answerPermission(request, reply: .always)
                }

                Button("Allow once") {
                    appState.answerPermission(request, reply: .once)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.errorBackground)
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
