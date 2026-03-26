import Foundation
import SwiftUI

enum SessionTranscriptSupport {
    static func thinkingBannerTitle(
        session: SessionDisplay?,
        latestReasoningTitle: String?,
        questions: [QuestionRequest],
        permissions: [PermissionRequest],
        showsThinking: Bool = ThinkingVisibilityPreferences.showsThinking()
    ) -> String? {
        guard !showsThinking else { return nil }
        guard permissions.isEmpty, questions.isEmpty else { return nil }
        guard session?.status?.isThinkingActive == true else { return nil }

        return latestReasoningTitle
    }

    static func messageAttributedText(
        _ text: String,
        font: PlatformFont,
        color: PlatformColor
    ) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    static func patchDetail(from patchText: String?) -> ToolPatchDetail? {
        guard let patchText, !patchText.isEmpty else { return nil }

        struct FileBuilder {
            let id: Int
            let path: String
            var destinationPath: String?
            var operation: ToolPatchFileOperation
            var hunks: [ToolPatchHunk]
        }

        var files: [ToolPatchFile] = []
        var currentFile: FileBuilder?
        var currentHunkHeader: String?
        var currentLines: [ToolPatchLine] = []
        var nextFileID = 0
        var nextHunkID = 0
        var nextLineID = 0

        func buildFile(from builder: FileBuilder) -> ToolPatchFile {
            ToolPatchFile(
                id: builder.id,
                path: builder.path,
                destinationPath: builder.destinationPath,
                operation: builder.operation,
                hunks: builder.hunks
            )
        }

        func flushHunk() {
            guard var file = currentFile else { return }
            guard currentHunkHeader != nil || !currentLines.isEmpty else { return }

            file.hunks.append(
                ToolPatchHunk(
                    id: nextHunkID,
                    header: currentHunkHeader,
                    lines: currentLines
                )
            )
            nextHunkID += 1
            currentFile = file
            currentHunkHeader = nil
            currentLines = []
        }

        func flushFile() {
            flushHunk()

            guard let file = currentFile else { return }
            files.append(buildFile(from: file))
            currentFile = nil
        }

        func beginFile(path: String, operation: ToolPatchFileOperation) {
            flushFile()
            currentFile = FileBuilder(id: nextFileID, path: path, destinationPath: nil, operation: operation, hunks: [])
            nextFileID += 1
        }

        func updateCurrentFile(_ mutate: (inout FileBuilder) -> Void) {
            guard var file = currentFile else { return }
            mutate(&file)
            currentFile = file
        }

        func appendLine(kind: ToolPatchLineKind, text: String) {
            guard currentFile != nil else { return }
            currentLines.append(ToolPatchLine(id: nextLineID, kind: kind, text: text))
            nextLineID += 1
        }

        let filePrefixes: [(String, ToolPatchFileOperation)] = [
            ("*** Update File: ", .updated),
            ("*** Add File: ", .added),
            ("*** Delete File: ", .deleted)
        ]

        for line in patchText.components(separatedBy: .newlines) {
            if line == "*** Begin Patch" || line == "*** End Patch" {
                continue
            }

            if let (prefix, operation) = filePrefixes.first(where: { line.hasPrefix($0.0) }) {
                let path = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { continue }
                beginFile(path: path, operation: operation)
                continue
            }

            if line.hasPrefix("*** Move to: ") {
                let destinationPath = String(line.dropFirst(13)).trimmingCharacters(in: .whitespaces)
                guard !destinationPath.isEmpty else { continue }
                updateCurrentFile {
                    $0.destinationPath = destinationPath
                    if $0.operation == .updated {
                        $0.operation = .moved
                    }
                }
                continue
            }

            if line.hasPrefix("@@") {
                flushHunk()
                currentHunkHeader = line
                continue
            }

            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                appendLine(kind: .addition, text: String(line.dropFirst()))
                continue
            }

            if line.hasPrefix("-") && !line.hasPrefix("---") {
                appendLine(kind: .deletion, text: String(line.dropFirst()))
                continue
            }

            if line.hasPrefix(" ") {
                appendLine(kind: .context, text: String(line.dropFirst()))
                continue
            }

            if line.isEmpty {
                if currentHunkHeader != nil || !currentLines.isEmpty {
                    appendLine(kind: .context, text: "")
                }
                continue
            }

            appendLine(kind: .context, text: line)
        }

        flushFile()

        guard !files.isEmpty else { return nil }
        return ToolPatchDetail(files: files)
    }
}

struct TranscriptMessageHeaderView: View {
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

struct TranscriptMessageFinishView: View {
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

struct TranscriptToolSummaryView: View {
    let style: ToolSummaryStyle

    var body: some View {
        switch style {
        case let .standard(summary):
            TranscriptStandardToolSummaryView(summary: summary)
        case let .patch(summary):
            TranscriptPatchToolSummaryView(summary: summary)
        case let .read(summary):
            TranscriptReadToolSummaryView(summary: summary)
        case let .task(summary):
            TranscriptTaskToolSummaryView(summary: summary)
        }
    }
}

private struct TranscriptStandardToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolCallSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TranscriptToolSummaryIcon(systemName: summary.iconSystemName ?? ToolCallSummary.genericIconSystemName)

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

private struct TranscriptPatchToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolPatchSummary

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TranscriptToolSummaryIcon(systemName: "pencil")

            Text("Patch")
                .fontWeight(.semibold)

            if let target = summary.target {
                Text(verbatim: "`\(target)`")
                    .font(.caption.monospaced())
            }

            if let additions = summary.additions {
                TranscriptSummaryBadge(text: "+\(additions)", tint: theme.diffAddition, background: theme.diffAdditionBackground)
            }

            if let deletions = summary.deletions {
                TranscriptSummaryBadge(text: "-\(deletions)", tint: theme.diffDeletion, background: theme.diffDeletionBackground)
            }
        }
        .font(.caption)
    }
}

private struct TranscriptReadToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolReadSummary

    private var text: String {
        summary.fileName ?? summary.path ?? "Read"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TranscriptToolSummaryIcon(systemName: "eyeglasses")

            Text("Read")
                .fontWeight(.semibold)

            Text(verbatim: "`\(text)`")
                .font(.caption.monospaced())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

private struct TranscriptTaskToolSummaryView: View {
    @Environment(\.openCodeTheme) private var theme
    let summary: ToolTaskSummary

    private var text: String {
        summary.target ?? summary.title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TranscriptToolSummaryIcon(systemName: "square.stack.3d.up")

            Text(summary.title)
                .fontWeight(.semibold)

            Text(verbatim: "`\(text)`")
                .font(.caption.monospaced())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

struct TranscriptSummaryBadge: View {
    let text: String
    let tint: Color
    let background: Color

    var body: some View {
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

private struct TranscriptToolSummaryIcon: View {
    @Environment(\.openCodeTheme) private var theme
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.secondaryText)
            .frame(width: 14, alignment: .center)
    }
}

struct TranscriptToolPartDrawerView: View {
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
                TranscriptToolPartDetailSection(title: field.title, value: field.value)
            }

            switch presentation.drawerStyle {
            case .standard:
                EmptyView()
            case let .patch(detail):
                TranscriptPatchToolDetailView(detail: detail)
            case let .todo(detail):
                TranscriptTodoToolDetailView(detail: detail)
            }

            if let output = part.state?.output, !output.isEmpty, !presentation.drawerStyle.hidesRawOutput {
                TranscriptToolPartDetailSection(title: "Result", value: output)
            }

            if let error = part.state?.error, !error.isEmpty {
                TranscriptToolPartDetailSection(title: "Error", value: error, isError: true)
            }

            if let fallbackDetail = presentation.fallbackDetail {
                Text(fallbackDetail)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }
}

private struct TranscriptTodoToolDetailView: View {
    let detail: ToolTodoDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(detail.items) { item in
                TranscriptTodoChecklistRow(item: item)
            }
        }
    }
}

private struct TranscriptTodoChecklistRow: View {
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

private struct TranscriptPatchToolDetailView: View {
    let detail: ToolPatchDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(detail.files) { file in
                TranscriptPatchFileCardView(file: file)
            }
        }
    }
}

private struct TranscriptPatchFileCardView: View {
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
                    TranscriptPatchHunkView(hunk: hunk)
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

struct TranscriptPatchHunkView: View {
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
                    TranscriptPatchDiffLineView(line: line)
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

private struct TranscriptPatchDiffLineView: View {
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

struct TranscriptToolPartDetailSection: View {
    @Environment(\.openCodeTheme) private var theme
    let title: String
    let value: String
    var isError = false

    private var resolvedTextColor: PlatformColor {
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

struct TranscriptQuestionCardContent<TrailingOverlay: View>: View {
    @Environment(\.openCodeTheme) private var theme

    let request: QuestionRequest
    let usesCheckboxToggleStyle: Bool
    let leadingPadding: CGFloat
    let onSubmitAnswers: ([[String]]) -> Void
    let onReject: () -> Void
    @ViewBuilder
    let trailingOverlay: () -> TrailingOverlay

    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Question")
                .font(.headline)

            ForEach(request.questions) { question in
                TranscriptQuestionGroupView(
                    question: question,
                    selections: $selections,
                    usesCheckboxToggleStyle: usesCheckboxToggleStyle
                )
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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.accentSubtleBackground)
        )
        .overlay(alignment: .bottomTrailing) {
            trailingOverlay()
        }
        .padding(.leading, leadingPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranscriptQuestionGroupView: View {
    @Environment(\.openCodeTheme) private var theme
    let question: QuestionRequest.Question
    @Binding var selections: [String: Set<String>]
    let usesCheckboxToggleStyle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.header)
                .font(.subheadline.weight(.semibold))
            Text(question.question)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            ForEach(question.options, id: \.id) { option in
                optionToggle(option)
            }
        }
    }

    @ViewBuilder
    private func optionToggle(_ option: QuestionRequest.Question.Option) -> some View {
        let binding = Binding(
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
        )

        #if canImport(AppKit)
        if usesCheckboxToggleStyle {
            Toggle(isOn: binding) {
                optionLabel(option)
            }
            .toggleStyle(.checkbox)
        } else {
            Toggle(isOn: binding) {
                optionLabel(option)
            }
        }
        #else
        Toggle(isOn: binding) {
            optionLabel(option)
        }
        .toggleStyle(.switch)
        #endif
    }

    private func optionLabel(_ option: QuestionRequest.Question.Option) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(option.label)
            Text(option.description)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }
}
