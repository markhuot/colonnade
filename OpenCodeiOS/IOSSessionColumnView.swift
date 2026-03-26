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
        let transcriptRows = sessionState.transcriptRows
        let questions = appState.questionForSession(sessionID)
        let permissions = deduplicatedPermissions(sessionState.permissions)
        let availableSessions = appState.sessions
        let thinkingBannerTitle = latestThinkingBannerTitle(
            session: session,
            latestReasoningTitle: sessionState.latestReasoningTitle,
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
                    transcriptRows: transcriptRows,
                    questions: questions,
                    thinkingBannerTitle: thinkingBannerTitle,
                    availableSessions: availableSessions,
                    latestTodoToolPartID: sessionState.latestTodoToolPartID
                ),
                sessionState: sessionState,
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
                    draftState: draftState,
                    sessionID: sessionID,
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
        latestReasoningTitle: String?,
        questions: [QuestionRequest],
        permissions: [PermissionRequest]
    ) -> String? {
        SessionTranscriptSupport.thinkingBannerTitle(
            session: session,
            latestReasoningTitle: latestReasoningTitle,
            questions: questions,
            permissions: permissions
        )
    }
}

private struct IOSSessionTranscriptSnapshot: Equatable {
    let sessionID: String
    let transcriptRows: [TranscriptMessageRow]
    let questions: [QuestionRequest]
    let thinkingBannerTitle: String?
    let availableSessions: [SessionDisplay]
    let latestTodoToolPartID: String?
}

private struct IOSSessionTranscriptSection: View, Equatable {
    let snapshot: IOSSessionTranscriptSnapshot
    @ObservedObject var sessionState: SessionLiveState
    let onAnswerQuestion: (QuestionRequest, [[String]]) -> Void
    let onRejectQuestion: (QuestionRequest) -> Void

    nonisolated static func == (lhs: IOSSessionTranscriptSection, rhs: IOSSessionTranscriptSection) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        IOSSessionTimelineView(
            sessionState: sessionState,
            transcriptRows: snapshot.transcriptRows,
            questions: snapshot.questions,
            thinkingBannerTitle: snapshot.thinkingBannerTitle,
            availableSessions: snapshot.availableSessions,
            latestTodoToolPartID: snapshot.latestTodoToolPartID,
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
    @Environment(\.openCodeTheme) private var theme

    @ObservedObject var sessionState: SessionLiveState
    let transcriptRows: [TranscriptMessageRow]
    let questions: [QuestionRequest]
    let thinkingBannerTitle: String?
    let availableSessions: [SessionDisplay]
    let latestTodoToolPartID: String?
    let onAnswerQuestion: (QuestionRequest, [[String]]) -> Void
    let onRejectQuestion: (QuestionRequest) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(transcriptRows) { row in
                    if let messageState = sessionState.messageState(for: row.id) {
                        IOSMessageRowView(
                            messageState: messageState,
                            showsTimestamp: row.showsTimestamp,
                            availableSessions: availableSessions,
                            latestTodoToolPartID: latestTodoToolPartID
                        )
                    }
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
                    .padding(.vertical, 9)
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

private struct IOSMessageRowView: View {
    @ObservedObject var messageState: SessionMessageState

    let showsTimestamp: Bool
    let availableSessions: [SessionDisplay]
    let latestTodoToolPartID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IOSMessageCard(
                messageState: messageState,
                showsTimestamp: showsTimestamp
            )

            IOSMessageToolPartsView(
                messageState: messageState,
                availableSessions: availableSessions,
                latestTodoToolPartID: latestTodoToolPartID
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IOSMessageCard: View {
    @AppStorage(ThinkingVisibilityPreferences.showsThinkingKey) private var showsThinking = true
    @Environment(\.openCodeTheme) private var theme
    @ObservedObject var messageState: SessionMessageState

    let showsTimestamp: Bool

    private var message: MessageEnvelope {
        messageState.snapshot
    }

    var body: some View {
        let visibleText = messageState.visibleText
        let reasoningText = messageState.reasoningText
        let showsMessageBubble = !visibleText.isEmpty
            || (showsThinking && !reasoningText.isEmpty)
            || (messageState.stepFinish?.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame && messageState.stepFinish != nil)
            || messageState.info.error != nil
        let renderedMessageText = SessionTranscriptSupport.messageAttributedText(
            visibleText,
            font: UIFont.preferredFont(forTextStyle: .body),
            color: theme.primaryTextColor
        )
        let renderedReasoningText = SessionTranscriptSupport.messageAttributedText(
            reasoningText,
            font: UIFont.preferredFont(forTextStyle: .callout),
            color: theme.secondaryTextColor
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

                    if let finish = messageState.stepFinish, finish.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame {
                        IOSMessageFinishView(part: finish)
                    }

                    if messageState.info.error != nil {
                        Text(messageState.info.error?.prettyDescription ?? "Unknown error")
                            .font(.caption)
                            .foregroundStyle(theme.error)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(messageState.info.role.isAssistant ? theme.assistantBubble : theme.userBubble)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IOSMessageToolPartsView: View {
    @ObservedObject var messageState: SessionMessageState

    let availableSessions: [SessionDisplay]
    let latestTodoToolPartID: String?

    private var toolParts: [MessagePart] {
        messageState.toolParts
    }

    private var subagentSessionsByPartID: [String: SessionDisplay] {
        MessagePart.resolveSubagentSessions(
            for: toolParts,
            in: availableSessions,
            parentSessionID: messageState.info.sessionID,
            baseReferenceTimeMS: messageState.info.time.created
        )
    }

    var body: some View {
        ForEach(toolParts) { toolPart in
            IOSToolPartView(
                part: toolPart,
                subagentSession: subagentSessionsByPartID[toolPart.id],
                latestTodoToolPartID: latestTodoToolPartID
            )
        }
    }
}

private struct IOSMessageCardHeader: View {
    let message: MessageEnvelope

    var body: some View {
        TranscriptMessageHeaderView(message: message)
    }
}

private struct IOSMessageFinishView: View {
    let part: MessagePart

    var body: some View {
        TranscriptMessageFinishView(part: part)
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
        TranscriptToolSummaryView(style: style)
    }
}

private struct IOSToolPartDrawerView: View {
    let part: MessagePart

    var body: some View {
        TranscriptToolPartDrawerView(part: part)
    }
}

private struct IOSToolPartDetailSection: View {
    let title: String
    let value: String
    var isError = false

    var body: some View {
        TranscriptToolPartDetailSection(title: title, value: value, isError: isError)
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
    let request: QuestionRequest
    let onSubmitAnswers: ([[String]]) -> Void
    let onReject: () -> Void

    var body: some View {
        TranscriptQuestionCardContent(
            request: request,
            usesCheckboxToggleStyle: false,
            leadingPadding: 0,
            onSubmitAnswers: onSubmitAnswers,
            onReject: onReject,
            trailingOverlay: {
                EmptyView()
            }
        )
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
