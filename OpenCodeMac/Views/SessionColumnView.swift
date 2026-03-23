import AppKit
import OSLog
import SwiftUI
import Textual
private struct MarkdownContentView: View {
    @Environment(\.openCodeTheme) private var theme

    let text: String
    let messageRole: MessageRole
    var baseFont: Font? = nil
    var foregroundStyle: AnyShapeStyle? = nil

    private var contentAlignment: Alignment {
        messageRole.isAssistant ? .leading : .trailing
    }

    var body: some View {
        StructuredText(markdown: text)
            .font(baseFont)
            .applyForegroundStyle(foregroundStyle)
            .textual.textSelection(.enabled)
            .textual.structuredTextStyle(.gitHub)
            .textual.codeBlockStyle(
                OpenCodeCodeBlockStyle(
                    foregroundStyle: foregroundStyle,
                    backgroundColor: messageRole.isAssistant ? theme.codeBlockBackground : Color.accentColor.opacity(0.12),
                    alignment: contentAlignment
                )
            )
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

struct SessionColumnView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @ObservedObject var sessionState: SessionLiveState

    private let logger = Logger(subsystem: "ai.opencode.app", category: "ui-sync")

    let sessionID: String

    var body: some View {
        let session = sessionState.session
        let messages = sessionState.messages
        let questions = sessionState.questions
        let permissions = deduplicatedPermissions(sessionState.permissions)

        VStack(spacing: 0) {
            SessionHeaderView(
                sessionID: sessionID,
                session: session,
                indicator: session?.indicator ?? SessionIndicator.resolve(status: nil, hasPendingPermission: false),
                contextUsageText: session?.contextUsageText
            )
            Divider()
            SessionTimelineView(sessionID: sessionID, messages: messages, questions: questions)
            Divider()
            SessionComposerView(sessionID: sessionID, permissions: permissions)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.surfaceBackground)
                .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(borderColor, lineWidth: appState.focusedSessionID == sessionID ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            appState.focusSession(sessionID)
        }
        .task(id: sessionID) {
            appState.openSession(sessionID)
        }
        .onAppear {
            let partCount = messages.reduce(0) { $0 + $1.parts.count }
            logger.notice("Session column appear sessionID=\(sessionID, privacy: .public) messages=\(messages.count, privacy: .public) parts=\(partCount, privacy: .public)")
        }
        .onChange(of: messages) { _, newMessages in
            let lastMessageID = newMessages.last?.id ?? "nil"
            let partCount = newMessages.reduce(0) { $0 + $1.parts.count }
            logger.notice(
                "Session column messages changed sessionID=\(sessionID, privacy: .public) count=\(newMessages.count, privacy: .public) parts=\(partCount, privacy: .public) lastMessageID=\(lastMessageID, privacy: .public)"
            )
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
        appState.focusedSessionID == sessionID ? Color.accentColor.opacity(0.85) : theme.border.opacity(0.7)
    }
}

private struct SessionHeaderView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let sessionID: String
    let session: SessionDisplay?
    let indicator: SessionIndicator
    let contextUsageText: String?

    @State private var isHoveringStatusIcon = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            appState.closeSession(sessionID)
                        } label: {
                            Group {
                                if isHoveringStatusIcon {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(theme.secondaryText)
                                } else {
                                    SessionStatusIcon(color: indicator.color)
                                }
                            }
                            .frame(width: 14, height: 14)
                            .padding(.top, 5)
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
    }
}

private struct SessionTimelineView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    @State private var scrollMetrics = TimelineScrollMetrics.zero
    @State private var isPinnedToBottom = true
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var programmaticScroll: ProgrammaticTimelineScroll?

    let sessionID: String
    let messages: [MessageEnvelope]
    let questions: [QuestionRequest]

    private let autoFollowThreshold: CGFloat = 36

    private var contentSignature: TimelineContentSignature {
        TimelineContentSignature(messages: messages, questions: questions)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Color.clear
                        .frame(height: 0)
                        .id(topAnchorID)

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        MessageCard(message: message, showsTimestamp: shouldShowTimestamp(for: index))
                            .id(message.id)
                    }

                    ForEach(questions) { request in
                        QuestionCard(request: request)
                    }

                    Color.clear
                        .frame(height: 0)
                        .id(bottomAnchorID)
                }
                .padding(18)
                .background(
                    TimelineScrollObserver { change in
                        handleScrollMetricsChange(change)
                    }
                )
            }
            .defaultScrollAnchor(.bottom)
            .background(theme.mutedSurfaceBackground.opacity(0.8))
            .onChange(of: contentSignature) { oldValue, newValue in
                guard shouldAutoFollow(for: oldValue, newValue) else { return }
                scheduleAutoFollow(with: proxy)
            }
            .onChange(of: appState.focusedSessionScrollRequest) { _, request in
                guard let request, request.sessionID == sessionID else { return }

                switch request.direction {
                case .top:
                    requestScroll(to: .top, with: proxy, animated: true)
                case .bottom:
                    requestScroll(to: .bottom, with: proxy, animated: true)
                }
            }
            .onDisappear {
                autoScrollTask?.cancel()
                autoScrollTask = nil
            }
        }
    }

    private var topAnchorID: String {
        "session-timeline-top-\(sessionID)"
    }

    private var bottomAnchorID: String {
        "session-timeline-bottom-\(sessionID)"
    }

    private func shouldAutoFollow(for oldValue: TimelineContentSignature?, _ newValue: TimelineContentSignature) -> Bool {
        guard oldValue != nil else { return false }
        return isPinnedToBottom
    }

    private func scheduleAutoFollow(with proxy: ScrollViewProxy) {
        autoScrollTask?.cancel()
        autoScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            requestScroll(to: .bottom, with: proxy, animated: false)
        }
    }

    private func requestScroll(to target: TimelineScrollTarget, with proxy: ScrollViewProxy, animated: Bool, attempt: Int = 0) {
        let request = ProgrammaticTimelineScroll(target: target)
        programmaticScroll = request

        let action = {
            switch target {
            case .top:
                proxy.scrollTo(topAnchorID, anchor: .top)
            case .bottom:
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }

        if target == .bottom {
            isPinnedToBottom = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if programmaticScroll == request {
                let nearBottom = scrollMetrics.distanceToBottom <= autoFollowThreshold

                if target == .bottom, !nearBottom, isPinnedToBottom, attempt == 0 {
                    requestScroll(to: .bottom, with: proxy, animated: false, attempt: 1)
                    return
                }

                programmaticScroll = nil
                isPinnedToBottom = nearBottom || scrollMetrics.contentHeight <= scrollMetrics.viewportHeight + 1
            }
        }
    }

    private func handleScrollMetricsChange(_ change: TimelineScrollChange) {
        let previous = scrollMetrics
        let metrics = change.metrics
        scrollMetrics = metrics

        if metrics.contentHeight <= metrics.viewportHeight + 1 {
            isPinnedToBottom = true

            return
        }

        let nearBottom = metrics.distanceToBottom <= autoFollowThreshold
        let viewportHeightChanged = abs(metrics.viewportHeight - previous.viewportHeight) > 1

        if let request = programmaticScroll {
            if request.target == .bottom, nearBottom {
                isPinnedToBottom = true
                programmaticScroll = nil
            }
            return
        }

        if change.source == .user || viewportHeightChanged {
            isPinnedToBottom = nearBottom
            return
        }
    }

    private func shouldShowTimestamp(for index: Int) -> Bool {
        guard index > 0 else { return true }
        return messages[index].createdAt.timeIntervalSince(messages[index - 1].createdAt) > 300
    }
}

private enum TimelineScrollTarget: Equatable {
    case top
    case bottom
}

private struct ProgrammaticTimelineScroll: Equatable {
    let id = UUID()
    let target: TimelineScrollTarget
}

private struct TimelineContentSignature: Equatable {
    let messageCount: Int
    let lastMessageID: String?
    let lastVisibleTextLength: Int
    let lastReasoningTextLength: Int
    let lastPartCount: Int
    let questionCount: Int

    init(messages: [MessageEnvelope], questions: [QuestionRequest]) {
        let lastMessage = messages.last
        messageCount = messages.count
        lastMessageID = lastMessage?.id
        lastVisibleTextLength = lastMessage?.visibleText.count ?? 0
        lastReasoningTextLength = lastMessage?.reasoningText.count ?? 0
        lastPartCount = lastMessage?.parts.count ?? 0
        questionCount = questions.count
    }
}

private struct TimelineScrollMetrics: Equatable {
    let verticalOffset: CGFloat
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let distanceToBottom: CGFloat

    static let zero = TimelineScrollMetrics(verticalOffset: 0, viewportHeight: 0, contentHeight: 0, distanceToBottom: 0)
}

private struct TimelineScrollChange: Equatable {
    let metrics: TimelineScrollMetrics
    let source: TimelineScrollChangeSource
}

private enum TimelineScrollChangeSource: Equatable {
    case user
    case content
    case layout
}

private struct TimelineScrollObserver: NSViewRepresentable {
    let onChange: @MainActor (TimelineScrollChange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            context.coordinator.onChange = onChange
            context.coordinator.attach(to: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.detach()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (TimelineScrollChange) -> Void

        private weak var observedView: NSView?
        private weak var scrollView: NSScrollView?
        private weak var clipView: NSClipView?
        private weak var documentView: NSView?

        init(onChange: @escaping @MainActor (TimelineScrollChange) -> Void) {
            self.onChange = onChange
            super.init()
        }

        func attach(to view: NSView) {
            observedView = view
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.installObservers(from: view)
            }
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            clipView?.postsBoundsChangedNotifications = false
            documentView?.postsFrameChangedNotifications = false
            scrollView = nil
            clipView = nil
            documentView = nil
            observedView = nil
        }

        private func installObservers(from view: NSView) {
            guard let scrollView = view.enclosingScrollView,
                  let clipView = scrollView.contentView as NSClipView?,
                  let documentView = scrollView.documentView
            else { return }

            if self.scrollView === scrollView, self.documentView === documentView {
                publishMetrics(source: .layout)
                return
            }

            detach()

            observedView = view
            self.scrollView = scrollView
            self.clipView = clipView
            self.documentView = documentView

            clipView.postsBoundsChangedNotifications = true
            documentView.postsFrameChangedNotifications = true

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFrameChanged),
                name: NSView.frameDidChangeNotification,
                object: documentView
            )

            publishMetrics(source: .layout)
        }

        @objc private func handleBoundsChanged() {
            publishMetrics(source: boundsChangeSource())
        }

        @objc private func handleFrameChanged() {
            publishMetrics(source: .content)
        }

        private func boundsChangeSource() -> TimelineScrollChangeSource {
            guard let event = NSApp.currentEvent else { return .layout }

            switch event.type {
            case .scrollWheel, .swipe, .keyDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                return .user
            default:
                return .layout
            }
        }

        private func publishMetrics(source: TimelineScrollChangeSource) {
            guard let clipView, let documentView else { return }

            let visibleRect = clipView.documentVisibleRect
            let contentHeight = documentView.bounds.height
            let viewportHeight = visibleRect.height
            let verticalOffset = visibleRect.origin.y
            let distanceToBottom: CGFloat

            if documentView.isFlipped {
                distanceToBottom = max(contentHeight - visibleRect.maxY, 0)
            } else {
                distanceToBottom = max(visibleRect.minY, 0)
            }

            onChange(
                TimelineScrollChange(
                    metrics: TimelineScrollMetrics(
                        verticalOffset: verticalOffset,
                        viewportHeight: viewportHeight,
                        contentHeight: contentHeight,
                        distanceToBottom: distanceToBottom
                    ),
                    source: source
                )
            )
        }
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

    private var selectedModelKey: Binding<String> {
        Binding(
            get: { appState.selectedModelOption(for: sessionID)?.id ?? modelOptions.first?.id ?? "" },
            set: { appState.setSelectedModel($0, for: sessionID) }
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
                            appState.sendMessage(sessionID: sessionID)
                        }
                    )
                    .frame(height: promptHeight)
                    .padding(4)

                    HStack {
                        if !modelOptions.isEmpty {
                            Picker("Model", selection: selectedModelKey) {
                                ForEach(modelOptions) { option in
                                    Text(option.menuLabel).tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 320)

                            if let selectedModel = appState.selectedModelOption(for: sessionID), selectedModel.supportsReasoning {
                                Picker("Thinking", selection: selectedThinkingLevel) {
                                    ForEach(thinkingLevels, id: \.self) { level in
                                        Text(level == OpenCodeAppModel.defaultThinkingLevel ? "Default" : level.capitalized).tag(level)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 140)
                            }
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 6)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let request = activePermission {
                        PermissionPromptView(request: request)
                    }
                }
            }
        }
        .padding(18)
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
    @Environment(\.openCodeTheme) private var theme

    let message: MessageEnvelope
    let showsTimestamp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTimestamp {
                MessageCardHeader(message: message)
            }

            if showsMessageBubble {
                VStack(alignment: .leading, spacing: 10) {
                    if !message.visibleText.isEmpty {
                        MarkdownContentView(text: message.visibleText, messageRole: message.info.role)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showsThinking, !message.reasoningText.isEmpty {
                        MarkdownContentView(
                            text: message.reasoningText,
                            messageRole: message.info.role,
                            baseFont: .callout,
                            foregroundStyle: AnyShapeStyle(.secondary)
                        )
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let finish = message.stepFinish, finish.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame {
                        MessageFinishView(part: finish)
                    }

                    if message.info.error != nil {
                        Text(message.info.error?.prettyDescription ?? "Unknown error")
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(TimelineMessageLayout.messageCardPadding)
                .background(bubbleBackground)
                .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.messageCardPadding))
            }

            ForEach(message.toolParts) { toolPart in
                ToolPartView(part: toolPart)
                    .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.toolCardPadding))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(message.info.role.isAssistant ? theme.assistantBubble : Color.accentColor.opacity(0.16))
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
    @Environment(\.openCodeTheme) private var theme
    let part: MessagePart
    @State private var isExpanded = false

    private var presentation: ToolPresentation {
        part.toolPresentation
    }

    private var statusLabel: String? {
        presentation.statusLabel
    }

    var body: some View {
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.toolCardBackground)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }
}

private struct StandardToolSummaryView: View {
    let summary: ToolCallSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(summary.action)
                .fontWeight(.semibold)

            if let target = summary.target {
                Text(verbatim: "`\(target)`")
                    .font(.caption.monospaced())
            }

            if let additions = summary.additions {
                Text("+\(additions)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.green)
            }

            if let deletions = summary.deletions {
                Text("-\(deletions)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
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
            }

            if let output = part.state?.output, !output.isEmpty {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            ScrollView(.horizontal) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isError ? .red : theme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
    }
}

private struct PermissionPromptView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel

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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.promptCardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuestionCard: View {
    @EnvironmentObject private var appState: OpenCodeAppModel

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
                .fill(Color.blue.opacity(0.10))
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
