import SwiftUI

struct IOSSessionColumnView: View {
    private static let paneCornerRadius: CGFloat = 24

    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @ObservedObject var sessionState: SessionLiveState
    let draftState: SessionDraftState

    let sessionID: String
    let isComposerActive: Bool
    let onActivateComposer: (String) -> Void

    var body: some View {
        let session = sessionState.session
        let messages = sessionState.messages
        let questions = appState.questionForSession(sessionID)
        let permissions = deduplicatedPermissions(sessionState.permissions)
        let availableSessions = appState.sessions
        let thinkingBannerTitle = latestThinkingBannerTitle(
            session: session,
            messages: messages,
            questions: questions,
            permissions: permissions
        )
        VStack(spacing: 0) {
            IOSSessionHeaderView(
                sessionID: sessionID,
                session: session,
                indicator: session?.indicator ?? SessionIndicator.resolve(status: nil, hasPendingPermission: false),
                contextUsageText: session?.contextUsageText
            )
            Divider()
            IOSSessionTranscriptSection(
                snapshot: IOSSessionTranscriptSnapshot(
                    sessionID: sessionID,
                    messages: messages,
                    questions: questions,
                    thinkingBannerTitle: thinkingBannerTitle,
                    availableSessions: availableSessions
                ),
                onAnswerQuestion: { request, answers in
                    appState.answerQuestion(request, answers: answers)
                },
                onRejectQuestion: { request in
                    appState.rejectQuestion(request)
                }
            )
            .equatable()
            Divider()
            if !isComposerActive {
                IOSSessionPromptPreviewSection(
                    sessionID: sessionID,
                    draftState: draftState,
                    permissions: permissions,
                    onFocus: {
                        appState.focusSession(sessionID)
                    },
                    onPermissionReply: { request, reply in
                        appState.answerPermission(request, reply: reply)
                    },
                    onActivateComposer: onActivateComposer
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Self.paneCornerRadius, style: .continuous)
                .fill(theme.surfaceBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Self.paneCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.paneCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(isFocused ? 0.16 : 0.06), radius: isFocused ? 16 : 8, x: 0, y: 8)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.focusSession(sessionID)
        }
    }

    private func deduplicatedPermissions(_ permissions: [PermissionRequest]) -> [PermissionRequest] {
        var seenKeys = Set<IOSSessionPermissionPresentationKey>()
        return permissions.filter { request in
            guard !appState.isPermissionDismissed(request) else { return false }
            let key = IOSSessionPermissionPresentationKey(request: request)
            return seenKeys.insert(key).inserted
        }
    }

    private var borderColor: Color {
        appState.focusedSessionID == sessionID ? theme.accent.opacity(0.85) : theme.border.opacity(0.7)
    }

    private var isFocused: Bool {
        appState.focusedSessionID == sessionID
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

private struct IOSSessionTranscriptSnapshot: Equatable {
    let sessionID: String
    let messages: [MessageEnvelope]
    let questions: [QuestionRequest]
    let thinkingBannerTitle: String?
    let availableSessions: [SessionDisplay]
}

private struct IOSSessionTranscriptSection: View, Equatable {
    let snapshot: IOSSessionTranscriptSnapshot
    let onAnswerQuestion: (QuestionRequest, [[String]]) -> Void
    let onRejectQuestion: (QuestionRequest) -> Void

    nonisolated static func == (lhs: IOSSessionTranscriptSection, rhs: IOSSessionTranscriptSection) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        IOSSessionTimelineView(
            messages: snapshot.messages,
            questions: snapshot.questions,
            thinkingBannerTitle: snapshot.thinkingBannerTitle,
            availableSessions: snapshot.availableSessions,
            onAnswerQuestion: onAnswerQuestion,
            onRejectQuestion: onRejectQuestion
        )
    }
}

private struct IOSSessionPromptPreviewSection: View {
    @ObservedObject var draftState: SessionDraftState

    let sessionID: String
    let permissions: [PermissionRequest]
    let onFocus: () -> Void
    let onPermissionReply: (PermissionRequest, PermissionReply) -> Void
    let onActivateComposer: (String) -> Void

    var body: some View {
        IOSSessionComposerTriggerView(
            sessionID: sessionID,
            draftPreview: draftPreview,
            permissions: permissions,
            onFocus: onFocus,
            onPermissionReply: onPermissionReply,
            onActivateComposer: onActivateComposer
        )
    }

    private var draftPreview: String {
        let draft = draftState.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.isEmpty ? "Message" : draft
    }
}

private struct IOSSessionHeaderView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let sessionID: String
    let session: SessionDisplay?
    let indicator: SessionIndicator
    let contextUsageText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 10) {
                        Button {
                            appState.closeSession(sessionID)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.secondaryText)
                                .frame(width: 28, height: 28)
                                .background(theme.mutedSurfaceBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                SessionStatusIcon(color: indicator.color())
                                Text(session?.title ?? sessionID)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            Text(contextUsageText ?? "No context usage yet")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }

                Spacer(minLength: 10)
            }
        }
        .padding(18)
    }
}

private struct IOSSessionTimelineView: View {
    struct MessageRenderContext: Equatable {
        let subagentSessionsByPartID: [String: SessionDisplay]
    }

    @Environment(\.openCodeTheme) private var theme

    let messages: [MessageEnvelope]
    let questions: [QuestionRequest]
    let thinkingBannerTitle: String?
    let availableSessions: [SessionDisplay]
    let onAnswerQuestion: (QuestionRequest, [[String]]) -> Void
    let onRejectQuestion: (QuestionRequest) -> Void

    private var latestTodoToolPartID: String? {
        messages
            .reversed()
            .compactMap { message in
                message.toolParts.last(where: \.isTodoWriteTool)?.id
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
        let messageRenderContexts = messageRenderContexts
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    IOSMessageCard(
                        message: message,
                        showsTimestamp: shouldShowTimestamp(for: index),
                        latestTodoToolPartID: latestTodoToolPartID,
                        renderContext: messageRenderContexts[message.id] ?? MessageRenderContext(subagentSessionsByPartID: [:])
                    )
                }

                ForEach(questions) { request in
                    IOSQuestionCard(
                        request: request,
                        onSubmitAnswers: { answers in
                            onAnswerQuestion(request, answers)
                        },
                        onReject: {
                            onRejectQuestion(request)
                        }
                    )
                }

                if let thinkingBannerTitle {
                    IOSThinkingStatusBanner(title: thinkingBannerTitle)
                        .padding(.top, 4)
                        .padding(.leading, 6)
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

private struct IOSSessionComposerTriggerView: View {
    @Environment(\.openCodeTheme) private var theme

    let sessionID: String
    let draftPreview: String
    let permissions: [PermissionRequest]
    let onFocus: () -> Void
    let onPermissionReply: (PermissionRequest, PermissionReply) -> Void
    let onActivateComposer: (String) -> Void

    private var activePermission: PermissionRequest? {
        permissions.first
    }

    var body: some View {
        Group {
            if let request = activePermission {
                IOSPermissionPromptView(
                    request: request,
                    onReply: { reply in
                        onPermissionReply(request, reply)
                    }
                )
            } else {
                Button {
                    onFocus()
                    onActivateComposer(sessionID)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)

                        Text(draftPreview)
                            .font(.body)
                            .foregroundStyle(draftPreview == "Message" ? theme.secondaryText : theme.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(18)
            }
        }
    }
}

struct IOSActivePromptComposerView: View {
    @Environment(\.openCodeTheme) private var theme

    @State private var isPromptFocused = false
    @State private var promptHeight: CGFloat = 44
    private let maximumPromptHeight: CGFloat = 220

    let sessionID: String
    @ObservedObject var draftState: SessionDraftState
    let composerFocusRequestID: UUID?
    let agentOptions: [AgentOption]
    let modelOptions: [ModelOption]
    let selectedModelOption: ModelOption?
    let selectedAgentKey: Binding<String>
    let selectedModelKey: Binding<String>
    let selectedThinkingLevel: Binding<String>
    let onFocus: () -> Void
    let onSubmit: () -> Bool
    let onClose: () -> Void

    private var thinkingLevels: [String] {
        [OpenCodeAppModel.defaultThinkingLevel] + (selectedModelOption?.thinkingLevels ?? [])
    }

    private var showsAccessoryControls: Bool {
        !agentOptions.isEmpty || !modelOptions.isEmpty
    }

    private var editorHeight: CGFloat {
        min(max(promptHeight, 52), maximumPromptHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                IOSPromptTextEditor(
                    text: Binding(
                        get: { draftState.text },
                        set: { draftState.text = $0 }
                    ),
                    isFocused: $isPromptFocused,
                    measuredHeight: $promptHeight,
                    highlightedSuggestionIndex: .constant(nil),
                    focusRequestID: composerFocusRequestID,
                    textColor: theme.primaryTextColor,
                    placeholderColor: theme.secondaryTextColor,
                    suggestions: [],
                    allowsNewlines: true,
                    accessoryContent: {
                        EmptyView()
                    },
                    onSelectSuggestion: { _ in },
                    onFocus: {
                        onFocus()
                    },
                    onSubmit: { },
                    onKeyboardDismiss: {
                        onClose()
                    }
                )
                .frame(height: editorHeight)
                .background(theme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .background(theme.accent)
                .foregroundStyle(Color.white)
                .clipShape(Circle())
                .padding(.bottom, 1)
            }

            if showsAccessoryControls {
                IOSComposerAccessoryBar(
                    agentOptions: agentOptions,
                    modelOptions: modelOptions,
                    thinkingLevels: thinkingLevels,
                    selectedModelSupportsReasoning: selectedModelOption?.supportsReasoning == true,
                    selectedAgentKey: selectedAgentKey,
                    selectedModelKey: selectedModelKey,
                    selectedThinkingLevel: selectedThinkingLevel,
                    theme: theme
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.border.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        .onAppear {
            onFocus()
            isPromptFocused = true
        }
    }

    private func submit() {
        if onSubmit() {
            onClose()
        }
    }
}

private struct IOSComposerAccessoryBar: View {
    let agentOptions: [AgentOption]
    let modelOptions: [ModelOption]
    let thinkingLevels: [String]
    let selectedModelSupportsReasoning: Bool
    let selectedAgentKey: Binding<String>
    let selectedModelKey: Binding<String>
    let selectedThinkingLevel: Binding<String>
    let theme: OpenCodeTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !agentOptions.isEmpty {
                    Picker("Agent", selection: selectedAgentKey) {
                        ForEach(agentOptions) { option in
                            Text(option.menuLabel).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }

                if !modelOptions.isEmpty {
                    Picker("Model", selection: selectedModelKey) {
                        ForEach(modelOptions) { option in
                            Text(option.menuLabel).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                    if selectedModelSupportsReasoning {
                        Picker("Thinking", selection: selectedThinkingLevel) {
                            ForEach(thinkingLevels, id: \.self) { level in
                                Text(level == OpenCodeAppModel.defaultThinkingLevel ? "Default" : level.capitalized).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

private struct IOSMessageCard: View {
    @AppStorage(ThinkingVisibilityPreferences.showsThinkingKey) private var showsThinking = true
    @Environment(\.openCodeTheme) private var theme

    let message: MessageEnvelope
    let showsTimestamp: Bool
    let latestTodoToolPartID: String?
    let renderContext: IOSSessionTimelineView.MessageRenderContext

    var body: some View {
        let textParts = message.textParts
        let reasoningParts = message.reasoningParts
        let toolParts = message.toolParts
        let subagentSessionsByPartID = renderContext.subagentSessionsByPartID
        let visibleText = message.visibleText
        let reasoningText = message.reasoningText
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
        let renderedMessageText = MarkdownTextRenderer.render(
            text: visibleText,
            rendersMarkdown: rendersMarkdownText,
            theme: theme,
            style: .body(theme: theme)
        )
        let renderedReasoningText = MarkdownTextRenderer.render(
            text: reasoningText,
            rendersMarkdown: rendersMarkdownReasoning,
            theme: theme,
            style: .callout(theme: theme)
        )

        VStack(alignment: .leading, spacing: 8) {
            if showsTimestamp {
                IOSMessageCardHeader(message: message)
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
                        IOSMessageFinishView(part: finish)
                    }

                    if message.info.error != nil {
                        Text(message.info.error?.prettyDescription ?? "Unknown error")
                            .font(.caption)
                            .foregroundStyle(theme.error)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.info.role.isAssistant ? theme.assistantBubble : theme.userBubble)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(toolParts) { toolPart in
                IOSToolPartView(
                    part: toolPart,
                    subagentSession: subagentSessionsByPartID[toolPart.id],
                    latestTodoToolPartID: latestTodoToolPartID
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IOSMessageCardHeader: View {
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

private struct IOSMessageFinishView: View {
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

private struct IOSToolPartView: View {
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
                    IOSToolSummaryView(style: presentation.summaryStyle)

                    Spacer(minLength: 8)

                    if let statusLabel = presentation.statusLabel {
                        Text(statusLabel)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }

                    if subagentSession != nil {
                        Image(systemName: "rectangle.stack")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                IOSToolPartDrawerView(part: resolvedPart)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(cardShape.fill(theme.toolCardBackground))
        .overlay(cardShape.stroke(theme.border.opacity(0.6), lineWidth: 1))
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

private struct IOSToolSummaryView: View {
    let style: ToolSummaryStyle

    var body: some View {
        switch style {
        case let .standard(summary):
            IOSStandardToolSummaryView(summary: summary)
        case let .patch(summary):
            IOSPatchToolSummaryView(summary: summary)
        case let .read(summary):
            IOSReadToolSummaryView(summary: summary)
        case let .task(summary):
            IOSTaskToolSummaryView(summary: summary)
        }
    }
}

private struct IOSStandardToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolCallSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            IOSToolSummaryIcon(systemName: summary.iconSystemName ?? ToolCallSummary.genericIconSystemName)
            Text(summary.action).fontWeight(.semibold)
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

private struct IOSPatchToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolPatchSummary

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            IOSToolSummaryIcon(systemName: "pencil")
            Text("Patch").fontWeight(.semibold)
            if let target = summary.target {
                Text(verbatim: "`\(target)`")
                    .font(.caption.monospaced())
            }
            if let additions = summary.additions {
                IOSSummaryBadge(text: "+\(additions)", tint: theme.diffAddition, background: theme.diffAdditionBackground)
            }
            if let deletions = summary.deletions {
                IOSSummaryBadge(text: "-\(deletions)", tint: theme.diffDeletion, background: theme.diffDeletionBackground)
            }
        }
        .font(.caption)
    }
}

private struct IOSSummaryBadge: View {
    let text: String
    let tint: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(background))
    }
}

private struct IOSToolSummaryIcon: View {
    @Environment(\.openCodeTheme) private var theme
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.secondaryText)
            .frame(width: 14, alignment: .center)
    }
}

private struct IOSReadToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolReadSummary

    private var text: String {
        summary.fileName ?? summary.path ?? "Read"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            IOSToolSummaryIcon(systemName: "eyeglasses")
            Text("Read").fontWeight(.semibold)
            Text(verbatim: "`\(text)`")
                .font(.caption.monospaced())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

private struct IOSTaskToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolTaskSummary

    private var text: String {
        summary.target ?? summary.title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            IOSToolSummaryIcon(systemName: "square.stack.3d.up")
            Text(summary.title).fontWeight(.semibold)
            Text(verbatim: "`\(text)`")
                .font(.caption.monospaced())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

private struct IOSToolPartDrawerView: View {
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
                IOSToolPartDetailSection(title: field.title, value: field.value)
            }

            switch presentation.drawerStyle {
            case .standard:
                EmptyView()
            case let .patch(detail):
                IOSPatchToolDetailView(detail: detail)
            case let .todo(detail):
                IOSTodoToolDetailView(detail: detail)
            }

            if let output = part.state?.output, !output.isEmpty, !presentation.drawerStyle.hidesRawOutput {
                IOSToolPartDetailSection(title: "Result", value: output)
            }

            if let error = part.state?.error, !error.isEmpty {
                IOSToolPartDetailSection(title: "Error", value: error, isError: true)
            }

            if let fallbackDetail = presentation.fallbackDetail {
                Text(fallbackDetail)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }
}

private struct IOSTodoToolDetailView: View {
    let detail: ToolTodoDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(detail.items) { item in
                IOSTodoChecklistRow(item: item)
            }
        }
    }
}

private struct IOSTodoChecklistRow: View {
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

private struct IOSPatchToolDetailView: View {
    let detail: ToolPatchDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(detail.files) { file in
                IOSPatchFileCardView(file: file)
            }
        }
    }
}

private struct IOSPatchFileCardView: View {
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
                    .background(Capsule(style: .continuous).fill(theme.mutedSurfaceBackground))

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
                    IOSPatchHunkView(hunk: hunk)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.codeBlockBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.border.opacity(0.6), lineWidth: 1))
    }
}

private struct IOSPatchHunkView: View {
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
                    IOSPatchDiffLineView(line: line)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.toolCardBackground.opacity(0.7)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct IOSPatchDiffLineView: View {
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

private struct IOSToolPartDetailSection: View {
    @Environment(\.openCodeTheme) private var theme
    let title: String
    let value: String
    var isError = false

    private var resolvedTextColor: UIColor {
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

            SelectableToolTextView(text: value, textColor: resolvedTextColor)
                .frame(maxWidth: .infinity, minHeight: 28, idealHeight: contentHeight, maxHeight: 110)
        }
    }
}

private struct IOSPermissionPromptView: View {
    @Environment(\.openCodeTheme) private var theme

    let request: PermissionRequest
    let onReply: (PermissionReply) -> Void

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
            HStack(spacing: 8) {
                Button("Deny", role: .destructive) {
                    onReply(.reject)
                }
                Button("Allow Always") {
                    onReply(.always)
                }
                Button("Allow Once") {
                    onReply(.once)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.errorBackground)
    }
}

private struct IOSQuestionCard: View {
    @Environment(\.openCodeTheme) private var theme

    let request: QuestionRequest
    let onSubmitAnswers: ([[String]]) -> Void
    let onReject: () -> Void
    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Question")
                .font(.headline)

            ForEach(request.questions) { question in
                IOSQuestionGroupView(question: question, selections: $selections)
            }

            HStack {
                Button("Submit") {
                    let answers = request.questions.map { question in
                        Array(selections[question.id, default: []])
                    }
                    onSubmitAnswers(answers)
                }
                .buttonStyle(.borderedProminent)

                Button("Reject", role: .destructive) {
                    onReject()
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.accentSubtleBackground))
    }
}

private struct IOSQuestionGroupView: View {
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
                .toggleStyle(.switch)
            }
        }
    }
}

private struct IOSThinkingStatusBanner: View {
    @Environment(\.openCodeTheme) private var theme
    let title: String

    var body: some View {
        Text((try? AttributedString(markdown: title)) ?? AttributedString(title))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(theme.accentSubtleBackground))
    }
}

private struct IOSSessionPermissionPresentationKey: Hashable {
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
