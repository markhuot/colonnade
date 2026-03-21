import OSLog
import SwiftUI

enum MarkdownRenderer {
    struct ListItem: Equatable {
        let marker: String
        let text: String
    }

    enum Block: Equatable {
        case paragraph(String)
        case unorderedList([ListItem])
        case orderedList([ListItem])
        case codeFence(String)
    }

    static func attributedString(from text: String) -> AttributedString? {
        guard !text.isEmpty else { return AttributedString("") }

        do {
            return try AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return nil
        }
    }

    static func blocks(from text: String) -> [Block] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var listItems: [ListItem] = []
        var activeListType: ListType?
        var codeFenceLines: [String] = []
        var inCodeFence = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines.removeAll()
        }

        func flushList() {
            guard let currentListType = activeListType, !listItems.isEmpty else { return }
            switch currentListType {
            case .unordered:
                blocks.append(.unorderedList(listItems))
            case .ordered:
                blocks.append(.orderedList(listItems))
            }
            listItems.removeAll()
            activeListType = nil
        }

        func flushCodeFence() {
            guard inCodeFence else { return }
            blocks.append(.codeFence(codeFenceLines.joined(separator: "\n")))
            codeFenceLines.removeAll()
            inCodeFence = false
        }

        for line in lines {
            if isFenceDelimiter(line) {
                flushParagraph()
                flushList()

                if inCodeFence {
                    flushCodeFence()
                } else {
                    inCodeFence = true
                }
                continue
            }

            if inCodeFence {
                codeFenceLines.append(line)
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let unordered = unorderedListItem(from: line) {
                flushParagraph()
                if activeListType == .ordered {
                    flushList()
                }
                activeListType = .unordered
                listItems.append(unordered)
                continue
            }

            if let ordered = orderedListItem(from: line) {
                flushParagraph()
                if activeListType == .unordered {
                    flushList()
                }
                activeListType = .ordered
                listItems.append(ordered)
                continue
            }

            if activeListType != nil, !listItems.isEmpty {
                let continuation = line.trimmingCharacters(in: .whitespaces)
                let last = listItems.removeLast()
                listItems.append(ListItem(marker: last.marker, text: last.text + "\n" + continuation))
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        flushList()
        flushCodeFence()
        return blocks
    }

    private enum ListType {
        case unordered
        case ordered
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private static func unorderedListItem(from line: String) -> ListItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }
        let marker = String(trimmed.prefix(1))
        let text = String(trimmed.dropFirst(2))
        return ListItem(marker: marker, text: text)
    }

    private static func orderedListItem(from line: String) -> ListItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let number = trimmed[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let remainderStart = trimmed.index(after: dotIndex)
        guard remainderStart < trimmed.endIndex, trimmed[remainderStart] == " " else { return nil }

        let textStart = trimmed.index(after: remainderStart)
        let text = String(trimmed[textStart...])
        return ListItem(marker: String(number) + ".", text: text)
    }
}

private struct MarkdownTextView: View {
    let text: String
    var baseFont: Font? = nil
    var foregroundStyle: AnyShapeStyle? = nil

    var body: some View {
        Group {
            if let attributed = MarkdownRenderer.attributedString(from: text) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(baseFont)
        .applyForegroundStyle(foregroundStyle)
        .textSelection(.enabled)
    }
}

private struct MarkdownContentView: View {
    let text: String
    var baseFont: Font? = nil
    var foregroundStyle: AnyShapeStyle? = nil

    private var blocks: [MarkdownRenderer.Block] {
        MarkdownRenderer.blocks(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownRenderer.Block) -> some View {
        switch block {
        case let .paragraph(text):
            MarkdownTextView(text: text, baseFont: baseFont, foregroundStyle: foregroundStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownListItemView(item: item, baseFont: baseFont, foregroundStyle: foregroundStyle)
                }
            }
        case let .orderedList(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownListItemView(item: item, baseFont: baseFont, foregroundStyle: foregroundStyle)
                }
            }
        case let .codeFence(code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .applyForegroundStyle(foregroundStyle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.06))
            )
        }
    }
}

private struct MarkdownListItemView: View {
    let item: MarkdownRenderer.ListItem
    var baseFont: Font? = nil
    var foregroundStyle: AnyShapeStyle? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.marker)
                .font(baseFont)
                .applyForegroundStyle(foregroundStyle)

            MarkdownTextView(text: item.text, baseFont: baseFont, foregroundStyle: foregroundStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    @EnvironmentObject private var appState: OpenCodeAppState
    @ObservedObject var sessionState: SessionLiveState

    private let logger = Logger(subsystem: "ai.opencode.mac", category: "ui-sync")

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
                .fill(Color(nsColor: .windowBackgroundColor))
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
        appState.focusedSessionID == sessionID ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08)
    }
}

private struct SessionHeaderView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: OpenCodeAppState

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
                                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    Button {
                        if let directory = appState.selectedDirectory {
                            openWindow(
                                id: "session-window",
                                value: SessionWindowContext(directory: directory, sessionID: sessionID)
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
    @EnvironmentObject private var appState: OpenCodeAppState

    let sessionID: String
    let messages: [MessageEnvelope]
    let questions: [QuestionRequest]

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
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: appState.focusedSessionScrollRequest) { _, request in
                guard let request, request.sessionID == sessionID else { return }

                withAnimation(.easeOut(duration: 0.2)) {
                    switch request.direction {
                    case .top:
                        proxy.scrollTo(topAnchorID, anchor: .top)
                    case .bottom:
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var topAnchorID: String {
        "session-timeline-top-\(sessionID)"
    }

    private var bottomAnchorID: String {
        "session-timeline-bottom-\(sessionID)"
    }

    private func shouldShowTimestamp(for index: Int) -> Bool {
        guard index > 0 else { return true }
        return messages[index].createdAt.timeIntervalSince(messages[index - 1].createdAt) > 300
    }
}

private struct SessionComposerView: View {
    @EnvironmentObject private var appState: OpenCodeAppState

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
        [OpenCodeAppState.defaultThinkingLevel] + (appState.selectedModelOption(for: sessionID)?.thinkingLevels ?? [])
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
                            set: { appState.drafts[sessionID] = $0 }
                        ),
                        measuredHeight: $promptHeight,
                        placeholder: placeholderText,
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
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )

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
                                        Text(level == OpenCodeAppState.defaultThinkingLevel ? "Default" : level.capitalized).tag(level)
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

private struct MessageCard: View {
    @AppStorage("showsThinking") private var showsThinking = true

    let message: MessageEnvelope
    let showsTimestamp: Bool

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            if showsTimestamp {
                MessageCardHeader(message: message)
            }

            VStack(alignment: alignment, spacing: 10) {
                if !message.visibleText.isEmpty {
                    MarkdownContentView(text: message.visibleText)
                        .multilineTextAlignment(textAlignment)
                        .frame(maxWidth: .infinity, alignment: contentAlignment)
                }

                if showsThinking, !message.reasoningText.isEmpty {
                    MarkdownContentView(
                        text: message.reasoningText,
                        baseFont: .callout,
                        foregroundStyle: AnyShapeStyle(.secondary)
                    )
                        .multilineTextAlignment(textAlignment)
                        .frame(maxWidth: .infinity, alignment: contentAlignment)
                }

                ForEach(message.toolParts) { toolPart in
                    ToolPartView(part: toolPart)
                }

                if let finish = message.stepFinish, finish.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame {
                    MessageFinishView(part: finish)
                }

                if message.info.error != nil {
                    Text(message.info.error?.prettyDescription ?? "Unknown error")
                        .font(.caption)
                        .multilineTextAlignment(textAlignment)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: contentAlignment)
                }
            }
            .padding(14)
            .background(bubbleBackground)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var alignment: HorizontalAlignment {
        message.info.role.isAssistant ? .leading : .trailing
    }

    private var frameAlignment: Alignment {
        message.info.role.isAssistant ? .leading : .trailing
    }

    private var contentAlignment: Alignment {
        message.info.role.isAssistant ? .leading : .trailing
    }

    private var textAlignment: TextAlignment {
        message.info.role.isAssistant ? .leading : .trailing
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(message.info.role.isAssistant ? Color(nsColor: .controlBackgroundColor) : Color.accentColor.opacity(0.16))
    }
}

private struct MessageCardHeader: View {
    let message: MessageEnvelope

    var body: some View {
        Text(Self.timestampFormatter.string(from: message.createdAt))
            .frame(maxWidth: .infinity, alignment: .center)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct MessageFinishView: View {
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
        .foregroundStyle(.secondary)
    }
}

private struct ToolPartView: View {
    let part: MessagePart
    @State private var isExpanded = false

    private var summary: ToolCallSummary {
        part.toolCallSummary
    }

    private var statusLabel: String? {
        guard let status = part.state?.status else { return nil }
        guard status != .completed else { return nil }
        return status.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Group {
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

                    Spacer(minLength: 8)

                    if let statusLabel {
                        Text(statusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
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
                .fill(Color.black.opacity(0.035))
        )
    }
}

private struct ToolPartDrawerView: View {
    let part: MessagePart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = part.state?.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(part.toolDetailFields) { field in
                ToolPartDetailSection(title: field.title, value: field.value)
            }

            if let output = part.state?.output, !output.isEmpty {
                ToolPartDetailSection(title: "Result", value: output)
            }

            if let error = part.state?.error, !error.isEmpty {
                ToolPartDetailSection(title: "Error", value: error, isError: true)
            }

            if part.toolDetailFields.isEmpty,
               (part.state?.output?.isEmpty ?? true),
               (part.state?.error?.isEmpty ?? true) {
                if part.state?.status != .completed {
                    Text(part.state?.status.title ?? ToolExecutionStatus.pending.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ToolPartDetailSection: View {
    let title: String
    let value: String
    var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isError ? .red : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
    }
}

private struct ToolCallSummary {
    let action: String
    let target: String?
    let additions: Int?
    let deletions: Int?
}

private struct ToolDetailField: Identifiable {
    let title: String
    let value: String

    var id: String { title + value }
}

private extension MessagePart {
    var toolCallSummary: ToolCallSummary {
        let input = state?.input ?? [:]

        switch toolKey {
        case "apply_patch":
            let paths = Self.patchPaths(from: input["patchText"]?.stringValue)
            let diffStat = Self.patchDiffStat(from: state?.metadata)
            return ToolCallSummary(
                action: "Patch",
                target: Self.compactTargetLabel(from: paths),
                additions: diffStat.additions,
                deletions: diffStat.deletions
            )
        case "read":
            return ToolCallSummary(action: "Read", target: Self.fileName(from: input["filePath"]?.stringValue), additions: nil, deletions: nil)
        case "write":
            return ToolCallSummary(action: "Write", target: Self.fileName(from: input["filePath"]?.stringValue), additions: nil, deletions: nil)
        case "edit":
            return ToolCallSummary(action: "Edit", target: Self.fileName(from: input["filePath"]?.stringValue), additions: nil, deletions: nil)
        case "grep":
            return ToolCallSummary(action: "Search", target: input["pattern"]?.stringValue, additions: nil, deletions: nil)
        case "glob":
            return ToolCallSummary(action: "Find", target: input["pattern"]?.stringValue, additions: nil, deletions: nil)
        case "webfetch":
            return ToolCallSummary(action: "Fetch", target: input["url"]?.stringValue, additions: nil, deletions: nil)
        case "bash":
            if let description = input["description"]?.stringValue, !description.isEmpty {
                return ToolCallSummary(action: Self.capitalizedSentence(description), target: nil, additions: nil, deletions: nil)
            }

            if let command = input["command"]?.stringValue, !command.isEmpty {
                return ToolCallSummary(action: "Run", target: Self.truncated(command, limit: 44), additions: nil, deletions: nil)
            }

            return ToolCallSummary(action: "Run command", target: nil, additions: nil, deletions: nil)
        default:
            if let title = state?.title, !title.isEmpty {
                return ToolCallSummary(action: title, target: nil, additions: nil, deletions: nil)
            }

            return ToolCallSummary(action: Self.humanizedToolName(toolKey), target: nil, additions: nil, deletions: nil)
        }
    }

    var toolDetailFields: [ToolDetailField] {
        let input = state?.input ?? [:]

        switch toolKey {
        case "apply_patch":
            let paths = Self.patchPaths(from: input["patchText"]?.stringValue)
            guard !paths.isEmpty else { return [] }
            return [ToolDetailField(title: "Files", value: paths.joined(separator: "\n"))]
        case "read", "write", "edit":
            guard let filePath = input["filePath"]?.stringValue, !filePath.isEmpty else { return [] }
            return [ToolDetailField(title: "Path", value: filePath)]
        case "grep", "glob":
            guard let pattern = input["pattern"]?.stringValue, !pattern.isEmpty else { return [] }
            return [ToolDetailField(title: "Pattern", value: pattern)]
        case "webfetch":
            guard let url = input["url"]?.stringValue, !url.isEmpty else { return [] }
            return [ToolDetailField(title: "URL", value: url)]
        case "bash":
            guard let command = input["command"]?.stringValue, !command.isEmpty else { return [] }
            return [ToolDetailField(title: "Command", value: command)]
        default:
            return []
        }
    }

    private var toolKey: String {
        let raw = tool ?? "tool"
        return raw.split(separator: ".").last.map(String.init) ?? raw
    }

    private static func humanizedToolName(_ tool: String) -> String {
        tool
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func capitalizedSentence(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }

    private static func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "..."
    }

    private static func fileName(from path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }

    private static func compactTargetLabel(from paths: [String]) -> String? {
        guard let first = paths.first else { return nil }
        guard paths.count > 1 else { return first }
        return "\(first) +\(paths.count - 1)"
    }

    private static func patchPaths(from patchText: String?) -> [String] {
        guard let patchText, !patchText.isEmpty else { return [] }

        var paths: [String] = []

        for line in patchText.components(separatedBy: .newlines) {
            let prefixes = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]

            guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else {
                continue
            }

            let path = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }

            let fileName = fileName(from: path) ?? path
            if !paths.contains(fileName) {
                paths.append(fileName)
            }
        }

        return paths
    }

    private static func patchDiffStat(from metadata: [String: JSONValue]?) -> (additions: Int?, deletions: Int?) {
        guard let metadata else { return (nil, nil) }

        let additions = jsonInt(metadata["additions"])
            ?? jsonInt(metadata["insertions"])
            ?? jsonInt(metadata["summary"]?.objectValue?["additions"])
        let deletions = jsonInt(metadata["deletions"])
            ?? jsonInt(metadata["removals"])
            ?? jsonInt(metadata["summary"]?.objectValue?["deletions"])

        return (additions, deletions)
    }

    private static func jsonInt(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }

        switch value {
        case let .number(number):
            return Int(number)
        case let .string(string):
            return Int(string)
        default:
            return nil
        }
    }
}

private struct PermissionPromptView: View {
    @EnvironmentObject private var appState: OpenCodeAppState

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
    }
}

private struct QuestionCard: View {
    @EnvironmentObject private var appState: OpenCodeAppState

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
    }
}

private struct QuestionGroupView: View {
    let question: QuestionRequest.Question
    @Binding var selections: [String: Set<String>]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.header)
                .font(.subheadline.weight(.semibold))
            Text(question.question)
                .font(.caption)
                .foregroundStyle(.secondary)

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
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}
