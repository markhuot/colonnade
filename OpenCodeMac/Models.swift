import AppKit
import Foundation
import SwiftUI

enum OpenCodeThemeID: String, CaseIterable, Identifiable, Codable {
    case native
    case githubLight = "github-light"
    case githubDark = "github-dark"
    case nord
    case oneDarkPro = "one-dark-pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native:
            return "Native"
        case .githubLight:
            return "GitHub Light"
        case .githubDark:
            return "GitHub Dark"
        case .nord:
            return "Nord"
        case .oneDarkPro:
            return "One Dark Pro"
        }
    }
}

struct OpenCodeTheme: Equatable {
    let id: OpenCodeThemeID
    let preferredColorScheme: ColorScheme?
    let windowBackgroundColor: NSColor
    let surfaceBackgroundColor: NSColor
    let mutedSurfaceBackgroundColor: NSColor
    let inputBackgroundColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let borderColor: NSColor
    let assistantBubbleColor: NSColor
    let codeBlockBackgroundColor: NSColor
    let toolCardBackgroundColor: NSColor
    let diffAdditionColor: NSColor
    let diffAdditionBackgroundColor: NSColor
    let diffDeletionColor: NSColor
    let diffDeletionBackgroundColor: NSColor

    static func == (lhs: OpenCodeTheme, rhs: OpenCodeTheme) -> Bool {
        lhs.id == rhs.id
    }

    static func resolve(_ id: OpenCodeThemeID) -> OpenCodeTheme {
        switch id {
        case .native:
            return OpenCodeTheme(
                id: .native,
                preferredColorScheme: nil,
                windowBackgroundColor: .windowBackgroundColor,
                surfaceBackgroundColor: .windowBackgroundColor,
                mutedSurfaceBackgroundColor: .controlBackgroundColor,
                inputBackgroundColor: .textBackgroundColor,
                primaryTextColor: .labelColor,
                secondaryTextColor: .secondaryLabelColor,
                borderColor: .separatorColor.withAlphaComponent(0.7),
                assistantBubbleColor: .controlBackgroundColor,
                codeBlockBackgroundColor: .controlBackgroundColor,
                toolCardBackgroundColor: .controlBackgroundColor,
                diffAdditionColor: .systemGreen,
                diffAdditionBackgroundColor: .systemGreen.withAlphaComponent(0.16),
                diffDeletionColor: .systemRed,
                diffDeletionBackgroundColor: .systemRed.withAlphaComponent(0.16)
            )
        case .githubLight:
            return OpenCodeTheme(
                id: .githubLight,
                preferredColorScheme: .light,
                windowBackgroundColor: NSColor(hex: 0xFFFFFF),
                surfaceBackgroundColor: NSColor(hex: 0xF6F8FA),
                mutedSurfaceBackgroundColor: NSColor(hex: 0xEFF2F5),
                inputBackgroundColor: NSColor(hex: 0xFFFFFF),
                primaryTextColor: NSColor(hex: 0x1F2328),
                secondaryTextColor: NSColor(hex: 0x656D76),
                borderColor: NSColor(hex: 0xD0D7DE),
                assistantBubbleColor: NSColor(hex: 0xF6F8FA),
                codeBlockBackgroundColor: NSColor(hex: 0xEFF2F5),
                toolCardBackgroundColor: NSColor(hex: 0xF0F3F6),
                diffAdditionColor: NSColor(hex: 0x1A7F37),
                diffAdditionBackgroundColor: NSColor(hex: 0xDFF3E4),
                diffDeletionColor: NSColor(hex: 0xCF222E),
                diffDeletionBackgroundColor: NSColor(hex: 0xFFEBE9)
            )
        case .githubDark:
            return OpenCodeTheme(
                id: .githubDark,
                preferredColorScheme: .dark,
                windowBackgroundColor: NSColor(hex: 0x0D1117),
                surfaceBackgroundColor: NSColor(hex: 0x161B22),
                mutedSurfaceBackgroundColor: NSColor(hex: 0x1F2630),
                inputBackgroundColor: NSColor(hex: 0x0D1117),
                primaryTextColor: NSColor(hex: 0xE6EDF3),
                secondaryTextColor: NSColor(hex: 0x8B949E),
                borderColor: NSColor(hex: 0x30363D),
                assistantBubbleColor: NSColor(hex: 0x161B22),
                codeBlockBackgroundColor: NSColor(hex: 0x11161D),
                toolCardBackgroundColor: NSColor(hex: 0x11161D),
                diffAdditionColor: NSColor(hex: 0x3FB950),
                diffAdditionBackgroundColor: NSColor(hex: 0x0F381A),
                diffDeletionColor: NSColor(hex: 0xF85149),
                diffDeletionBackgroundColor: NSColor(hex: 0x3F1518)
            )
        case .nord:
            return OpenCodeTheme(
                id: .nord,
                preferredColorScheme: .dark,
                windowBackgroundColor: NSColor(hex: 0x2E3440),
                surfaceBackgroundColor: NSColor(hex: 0x3B4252),
                mutedSurfaceBackgroundColor: NSColor(hex: 0x434C5E),
                inputBackgroundColor: NSColor(hex: 0x2A303B),
                primaryTextColor: NSColor(hex: 0xECEFF4),
                secondaryTextColor: NSColor(hex: 0xD8DEE9),
                borderColor: NSColor(hex: 0x4C566A),
                assistantBubbleColor: NSColor(hex: 0x434C5E),
                codeBlockBackgroundColor: NSColor(hex: 0x2A303B),
                toolCardBackgroundColor: NSColor(hex: 0x2A303B),
                diffAdditionColor: NSColor(hex: 0xA3BE8C),
                diffAdditionBackgroundColor: NSColor(hex: 0x3E4C41),
                diffDeletionColor: NSColor(hex: 0xBF616A),
                diffDeletionBackgroundColor: NSColor(hex: 0x4D3841)
            )
        case .oneDarkPro:
            return OpenCodeTheme(
                id: .oneDarkPro,
                preferredColorScheme: .dark,
                windowBackgroundColor: NSColor(hex: 0x282C34),
                surfaceBackgroundColor: NSColor(hex: 0x31353F),
                mutedSurfaceBackgroundColor: NSColor(hex: 0x3A3F4B),
                inputBackgroundColor: NSColor(hex: 0x21252B),
                primaryTextColor: NSColor(hex: 0xABB2BF),
                secondaryTextColor: NSColor(hex: 0x7F848E),
                borderColor: NSColor(hex: 0x4B5263),
                assistantBubbleColor: NSColor(hex: 0x31353F),
                codeBlockBackgroundColor: NSColor(hex: 0x21252B),
                toolCardBackgroundColor: NSColor(hex: 0x21252B),
                diffAdditionColor: NSColor(hex: 0x98C379),
                diffAdditionBackgroundColor: NSColor(hex: 0x253126),
                diffDeletionColor: NSColor(hex: 0xE06C75),
                diffDeletionBackgroundColor: NSColor(hex: 0x3B2228)
            )
        }
    }

    var displayName: String { id.displayName }
    var windowBackground: Color { Color(nsColor: windowBackgroundColor) }
    var surfaceBackground: Color { Color(nsColor: surfaceBackgroundColor) }
    var mutedSurfaceBackground: Color { Color(nsColor: mutedSurfaceBackgroundColor) }
    var inputBackground: Color { Color(nsColor: inputBackgroundColor) }
    var primaryText: Color { Color(nsColor: primaryTextColor) }
    var secondaryText: Color { Color(nsColor: secondaryTextColor) }
    var border: Color { Color(nsColor: borderColor) }
    var assistantBubble: Color { Color(nsColor: assistantBubbleColor) }
    var codeBlockBackground: Color { Color(nsColor: codeBlockBackgroundColor) }
    var toolCardBackground: Color { Color(nsColor: toolCardBackgroundColor) }
    var diffAddition: Color { Color(nsColor: diffAdditionColor) }
    var diffAdditionBackground: Color { Color(nsColor: diffAdditionBackgroundColor) }
    var diffDeletion: Color { Color(nsColor: diffDeletionColor) }
    var diffDeletionBackground: Color { Color(nsColor: diffDeletionBackgroundColor) }
}

@MainActor
final class ThemeController: ObservableObject {
    enum Constants {
        static let selectedThemeKey = "selectedTheme"
    }

    @Published private(set) var selectedThemeID: OpenCodeThemeID

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawValue = defaults.string(forKey: Constants.selectedThemeKey),
           let storedTheme = OpenCodeThemeID(rawValue: rawValue) {
            selectedThemeID = storedTheme
        } else {
            selectedThemeID = .native
        }
    }

    var selectedTheme: OpenCodeTheme {
        OpenCodeTheme.resolve(selectedThemeID)
    }

    func selectTheme(_ themeID: OpenCodeThemeID) {
        guard selectedThemeID != themeID else { return }
        selectedThemeID = themeID
        defaults.set(themeID.rawValue, forKey: Constants.selectedThemeKey)
    }
}

private struct OpenCodeThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = OpenCodeTheme.resolve(.native)
}

extension EnvironmentValues {
    var openCodeTheme: OpenCodeTheme {
        get { self[OpenCodeThemeEnvironmentKey.self] }
        set { self[OpenCodeThemeEnvironmentKey.self] = newValue }
    }
}

extension View {
    func themedWindow(_ theme: OpenCodeTheme) -> some View {
        background(WindowThemeView(theme: theme))
    }
}

struct WindowThemeView: NSViewRepresentable {
    let theme: OpenCodeTheme

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.backgroundColor = theme.windowBackgroundColor
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct OpenCodeSession: Codable, Identifiable, Hashable {
    struct Summary: Codable, Hashable {
        let additions: Int?
        let deletions: Int?
        let files: Int?
    }

    struct TimeInfo: Codable, Hashable {
        let created: Double
        let updated: Double
        let compacting: Double?
        let archived: Double?
    }

    let id: String
    let slug: String
    let projectID: String
    let workspaceID: String?
    let directory: String
    let parentID: String?
    let title: String
    let version: String
    let summary: Summary?
    let time: TimeInfo
}

struct OpenCodeServerHealth: Codable, Hashable {
    let healthy: Bool
    let version: String
}

struct OpenCodeProject: Codable, Hashable, Identifiable {
    struct TimeInfo: Codable, Hashable {
        let created: Double
        let initialized: Double?
    }

    let id: String
    let worktree: String
    let vcsDir: String?
    let vcs: String?
    let time: TimeInfo

    enum CodingKeys: String, CodingKey {
        case id
        case worktree
        case vcsDir
        case vcs
        case time
    }
}

struct WorkspaceConnection: Codable, Hashable {
    let serverURL: URL
    let directory: String
}

struct ModelContextKey: Hashable {
    let providerID: String
    let modelID: String
}

struct ModelCatalog: Codable, Hashable {
    let providers: [ModelProvider]
    let defaultModels: [String: String]
    let connectedProviderIDs: [String]

    enum CodingKeys: String, CodingKey {
        case all
        case providers
        case defaultModels = "default"
        case connected
    }

    init(providers: [ModelProvider], defaultModels: [String: String], connectedProviderIDs: [String]) {
        self.providers = providers
        self.defaultModels = defaultModels
        self.connectedProviderIDs = connectedProviderIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providers = try container.decodeIfPresent([ModelProvider].self, forKey: .providers)
            ?? container.decodeIfPresent([ModelProvider].self, forKey: .all)
            ?? []
        defaultModels = try container.decodeIfPresent([String: String].self, forKey: .defaultModels) ?? [:]
        connectedProviderIDs = try container.decodeIfPresent([String].self, forKey: .connected) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providers, forKey: .providers)
        try container.encode(defaultModels, forKey: .defaultModels)
        try container.encode(connectedProviderIDs, forKey: .connected)
    }
}

struct ModelProvider: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let models: [String: ModelDefinition]
}

struct ModelDefinition: Codable, Identifiable, Hashable {
    struct Capabilities: Codable, Hashable {
        struct IO: Codable, Hashable {
            let text: Bool?
        }

        let reasoning: Bool?
        let toolcall: Bool?
        let input: IO?
        let output: IO?
    }

    struct Limit: Codable, Hashable {
        let context: Int?
    }

    struct Variant: Codable, Hashable {
        let reasoningEffort: String?
        let reasoningSummary: String?
        let include: [String]?
    }

    let id: String
    let providerID: String
    let name: String
    let family: String?
    let status: String?
    let capabilities: Capabilities?
    let limit: Limit?
    let variants: [String: Variant]
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case providerID
        case name
        case family
        case status
        case capabilities
        case limit
        case variants
        case releaseDate = "release_date"
    }
}

struct ModelReference: Codable, Hashable, Identifiable {
    let providerID: String
    let modelID: String

    var id: String { key }

    var key: String {
        "\(providerID)/\(modelID)"
    }

    init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }
}

struct ModelOption: Identifiable, Hashable {
    let providerID: String
    let providerName: String
    let modelID: String
    let modelName: String
    let supportsReasoning: Bool
    let thinkingLevels: [String]
    let isDefault: Bool
    let isRecent: Bool

    var id: String { reference.key }

    var reference: ModelReference {
        ModelReference(providerID: providerID, modelID: modelID)
    }

    var menuLabel: String {
        if isRecent {
            return "\(modelName) - \(providerName) - Recent"
        }

        if isDefault {
            return "\(modelName) - \(providerName) - Default"
        }

        return "\(modelName) - \(providerName)"
    }
}

struct MessageEnvelope: Codable, Identifiable, Hashable {
    let info: MessageInfo
    var parts: [MessagePart]

    var id: String { info.id }
}

struct MessageInfo: Codable, Hashable {
    struct TimeInfo: Codable, Hashable {
        let created: Double
        let completed: Double?
    }

    struct ModelRef: Codable, Hashable {
        let providerID: String
        let modelID: String
    }

    struct PathInfo: Codable, Hashable {
        let cwd: String
        let root: String
    }

    struct TokenCache: Codable, Hashable {
        let read: Int?
        let write: Int?
    }

    struct TokenInfo: Codable, Hashable {
        let total: Int?
        let input: Int?
        let output: Int?
        let reasoning: Int?
        let cache: TokenCache?
    }

    let id: String
    let sessionID: String
    let role: MessageRole
    let time: TimeInfo
    let parentID: String?
    let agent: String?
    let model: ModelRef?
    let modelID: String?
    let providerID: String?
    let mode: String?
    let path: PathInfo?
    let cost: Double?
    let tokens: TokenInfo?
    let finish: String?
    let summary: JSONValue?
    let error: JSONValue?
}

struct MessagePart: Codable, Identifiable, Hashable {
    struct TimeInfo: Codable, Hashable {
        let start: Double?
        let end: Double?
        let compacted: Double?
    }

    struct ToolState: Codable, Hashable {
        let status: ToolExecutionStatus
        let input: [String: JSONValue]?
        let raw: String?
        let output: String?
        let title: String?
        let metadata: [String: JSONValue]?
        let error: String?
        let time: TimeInfo?
        let attachments: [FileAttachment]?
    }

    struct FileAttachment: Codable, Hashable, Identifiable {
        let id: String
        let sessionID: String?
        let messageID: String?
        let type: String?
        let mime: String?
        let filename: String?
        let url: String?
    }

    struct SourceRange: Codable, Hashable {
        let value: String
        let start: Int
        let end: Int
    }

    struct TokenCache: Codable, Hashable {
        let read: Int?
        let write: Int?
    }

    struct TokenInfo: Codable, Hashable {
        let total: Int?
        let input: Int?
        let output: Int?
        let reasoning: Int?
        let cache: TokenCache?
    }

    let id: String
    let sessionID: String?
    let messageID: String?
    let type: MessagePartKind
    var text: String?
    let synthetic: Bool?
    let ignored: Bool?
    let time: TimeInfo?
    let metadata: [String: JSONValue]?
    let callID: String?
    let tool: String?
    var state: ToolState?
    let mime: String?
    let filename: String?
    let url: String?
    let reason: String?
    let cost: Double?
    let tokens: TokenInfo?
    let prompt: String?
    let description: String?
    let agent: String?
    let model: MessageInfo.ModelRef?
    let command: String?
    let name: String?
    let source: SourceRange?
    let hash: String?
    let files: [String]?
    let snapshot: String?

    mutating func apply(delta: String, to field: MessagePartDeltaField) {
        switch field {
        case .text:
            text = (text ?? "") + delta
        case .output:
            var current = state
            current = ToolState(
                status: current?.status ?? .running,
                input: current?.input,
                raw: current?.raw,
                output: (current?.output ?? "") + delta,
                title: current?.title,
                metadata: current?.metadata,
                error: current?.error,
                time: current?.time,
                attachments: current?.attachments
            )
            state = current
        case .error:
            var current = state
            current = ToolState(
                status: current?.status ?? .error,
                input: current?.input,
                raw: current?.raw,
                output: current?.output,
                title: current?.title,
                metadata: current?.metadata,
                error: (current?.error ?? "") + delta,
                time: current?.time,
                attachments: current?.attachments
            )
            state = current
        case .unknown:
            break
        }
    }
}

enum SessionStatus: Codable, Hashable {
    case idle
    case busy
    case retry(attempt: Int, message: String, next: Double)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case attempt
        case message
        case next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "idle":
            self = .idle
        case "busy":
            self = .busy
        case "retry":
            self = .retry(
                attempt: try container.decodeIfPresent(Int.self, forKey: .attempt) ?? 0,
                message: try container.decodeIfPresent(String.self, forKey: .message) ?? "Retrying",
                next: try container.decodeIfPresent(Double.self, forKey: .next) ?? 0
            )
        default:
            self = .unknown(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode("idle", forKey: .type)
        case .busy:
            try container.encode("busy", forKey: .type)
        case let .retry(attempt, message, next):
            try container.encode("retry", forKey: .type)
            try container.encode(attempt, forKey: .attempt)
            try container.encode(message, forKey: .message)
            try container.encode(next, forKey: .next)
        case let .unknown(type):
            try container.encode(type, forKey: .type)
        }
    }
}

struct QuestionRequest: Codable, Identifiable, Hashable {
    struct Question: Codable, Hashable, Identifiable {
        struct Option: Codable, Hashable, Identifiable {
            var id: String { label }

            let label: String
            let description: String
        }

        var id: String { header }

        let question: String
        let header: String
        let options: [Option]
        let multiple: Bool?
        let custom: Bool?
    }

    let id: String
    let sessionID: String
    let questions: [Question]
}

struct PermissionRequest: Codable, Identifiable, Hashable {
    struct ToolInfo: Codable, Hashable {
        let messageID: String
        let callID: String
    }

    let id: String
    let sessionID: String
    let permission: String
    let patterns: [String]
    let metadata: [String: JSONValue]
    let always: [String]
    let tool: ToolInfo?
}

struct SessionTodo: Codable, Hashable, Identifiable {
    var id: String { content }

    let content: String
    let status: TodoStatus
    let priority: TodoPriority
}

struct TodoProgress: Hashable {
    let completed: Int
    let total: Int
    let actionable: Int

    var fractionComplete: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var percentageText: String {
        "\(Int((fractionComplete * 100).rounded()))%"
    }

    static func from(_ todos: [SessionTodo]) -> TodoProgress? {
        let relevant = todos.filter { $0.status != .cancelled }
        guard !relevant.isEmpty else { return nil }
        let completed = relevant.filter { $0.status == .completed }.count
        let actionable = relevant.filter { $0.status == .pending || $0.status == .inProgress }.count
        guard actionable > 0 else { return nil }
        return TodoProgress(completed: completed, total: relevant.count, actionable: actionable)
    }
}

struct EventPayload: Codable {
    let type: SessionEventName
    let properties: JSONValue?
}

struct SessionWindowContext: Codable, Hashable {
    let connection: WorkspaceConnection
    let sessionID: String
}

struct SessionPaneState: Codable, Hashable, Identifiable {
    let sessionID: String
    let position: Int
    let width: Double
    let isHidden: Bool

    var id: String { sessionID }
}

struct SessionIndicator {
    let color: Color
    let label: String?
    let showsTodoProgress: Bool

    static let idleColor = Color(nsColor: .systemGreen)
    static let busyColor = Color(nsColor: .systemOrange)
    static let retryColor = Color(nsColor: .systemYellow)
    static let permissionColor = Color(nsColor: .systemRed)

    static func resolve(status: SessionStatus?, hasPendingPermission: Bool) -> SessionIndicator {
        if hasPendingPermission {
            return SessionIndicator(
                color: permissionColor,
                label: "Permission Required",
                showsTodoProgress: false
            )
        }

        guard let status else {
            return SessionIndicator(color: idleColor, label: nil, showsTodoProgress: false)
        }

        return SessionIndicator(
            color: status.displayColor,
            label: {
                if case .busy = status {
                    return nil
                }
                return status.label
            }(),
            showsTodoProgress: status.showsTodoProgress
        )
    }
}

struct ToolCallSummary: Hashable {
    let action: String
    let target: String?
    let additions: Int?
    let deletions: Int?
}

struct ToolPatchSummary: Hashable {
    let target: String?
    let additions: Int?
    let deletions: Int?
}

enum ToolPatchFileOperation: String, Hashable {
    case added
    case updated
    case deleted
    case moved
}

enum ToolPatchLineKind: Hashable {
    case context
    case addition
    case deletion
}

struct ToolPatchLine: Identifiable, Hashable {
    let id: Int
    let kind: ToolPatchLineKind
    let text: String
}

struct ToolPatchHunk: Identifiable, Hashable {
    let id: Int
    let header: String?
    let lines: [ToolPatchLine]
}

struct ToolPatchFile: Identifiable, Hashable {
    let id: Int
    let path: String
    let destinationPath: String?
    let operation: ToolPatchFileOperation
    let hunks: [ToolPatchHunk]
}

struct ToolPatchDetail: Hashable {
    let files: [ToolPatchFile]
}

struct ToolReadSummary: Hashable {
    let fileName: String?
    let path: String?
}

enum ToolSummaryStyle: Hashable {
    case standard(ToolCallSummary)
    case patch(ToolPatchSummary)
    case read(ToolReadSummary)
}

enum ToolDrawerStyle: Hashable {
    case standard
    case patch(ToolPatchDetail)
}

struct ToolDetailField: Identifiable, Hashable {
    let title: String
    let value: String

    var id: String { title + value }
}

struct ToolPresentation: Hashable {
    let summaryStyle: ToolSummaryStyle
    let drawerStyle: ToolDrawerStyle
    let detailFields: [ToolDetailField]
    let statusLabel: String?
    let fallbackDetail: String?
}

extension MessagePart {
    var toolPresentation: ToolPresentation {
        let descriptor = toolDescriptor
        let statusLabel = state.flatMap { $0.status == .completed ? nil : $0.status.title }
        let hasSupplementalContent = !(state?.output?.isEmpty ?? true) || !(state?.error?.isEmpty ?? true)
        let fallbackDetail: String?

        if descriptor.detailFields.isEmpty, !hasSupplementalContent, state?.status != .completed {
            fallbackDetail = state?.status.title ?? ToolExecutionStatus.pending.title
        } else {
            fallbackDetail = nil
        }

        return ToolPresentation(
            summaryStyle: descriptor.summaryStyle,
            drawerStyle: descriptor.drawerStyle,
            detailFields: descriptor.detailFields,
            statusLabel: statusLabel,
            fallbackDetail: fallbackDetail
        )
    }

    private var toolDescriptor: ToolDescriptor {
        let input = state?.input ?? [:]

        switch toolKey {
        case "apply_patch":
            let patch = Self.patchDetail(from: input["patchText"]?.stringValue)
            let paths = patch?.files.map { Self.fileName(from: $0.destinationPath ?? $0.path) ?? ($0.destinationPath ?? $0.path) } ?? Self.patchPaths(from: input["patchText"]?.stringValue)
            let diffStat = Self.patchDiffStat(from: state?.metadata)
            return ToolDescriptor(
                summaryStyle: .patch(
                    ToolPatchSummary(
                        target: Self.compactTargetLabel(from: paths),
                        additions: diffStat.additions,
                        deletions: diffStat.deletions
                    )
                ),
                detailFields: paths.isEmpty ? [] : [ToolDetailField(title: "Files", value: paths.joined(separator: "\n"))],
                drawerStyle: patch.map(ToolDrawerStyle.patch) ?? .standard
            )
        case "read":
            let filePath = input["filePath"]?.stringValue
            return ToolDescriptor(
                summaryStyle: .read(
                    ToolReadSummary(
                        fileName: Self.fileName(from: filePath),
                        path: filePath
                    )
                ),
                detailFields: Self.detailField(title: "Path", value: filePath)
            )
        case "write", "edit":
            let filePath = input["filePath"]?.stringValue
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(
                        action: toolKey.capitalized,
                        target: Self.fileName(from: filePath),
                        additions: nil,
                        deletions: nil
                    )
                ),
                detailFields: Self.detailField(title: "Path", value: filePath)
            )
        case "grep":
            let pattern = input["pattern"]?.stringValue
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(action: "Search", target: pattern, additions: nil, deletions: nil)
                ),
                detailFields: Self.detailField(title: "Pattern", value: pattern)
            )
        case "glob":
            let pattern = input["pattern"]?.stringValue
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(action: "Find", target: pattern, additions: nil, deletions: nil)
                ),
                detailFields: Self.detailField(title: "Pattern", value: pattern)
            )
        case "webfetch":
            let url = input["url"]?.stringValue
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(action: "Fetch", target: url, additions: nil, deletions: nil)
                ),
                detailFields: Self.detailField(title: "URL", value: url)
            )
        case "bash":
            let command = input["command"]?.stringValue
            let description = input["description"]?.stringValue
            let action: String

            if let description, !description.isEmpty {
                action = Self.capitalizedSentence(description)
            } else if let command, !command.isEmpty {
                action = "Run"
            } else {
                action = "Run command"
            }

            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(
                        action: action,
                        target: action == "Run" ? Self.truncated(command ?? "", limit: 44) : nil,
                        additions: nil,
                        deletions: nil
                    )
                ),
                detailFields: Self.detailField(title: "Command", value: command)
            )
        default:
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(
                        action: state?.title.flatMap { $0.isEmpty ? nil : $0 } ?? Self.humanizedToolName(toolKey),
                        target: nil,
                        additions: nil,
                        deletions: nil
                    )
                ),
                detailFields: []
            )
        }
    }

    private var toolKey: String {
        let raw = tool ?? "tool"
        return raw.split(separator: ".").last.map(String.init) ?? raw
    }

    private static func detailField(title: String, value: String?) -> [ToolDetailField] {
        guard let value, !value.isEmpty else { return [] }
        return [ToolDetailField(title: title, value: value)]
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
        guard paths.count == 1 else { return "\(first) +\(paths.count - 1)" }
        return first
    }

    private static func patchPaths(from patchText: String?) -> [String] {
        guard let patchText, !patchText.isEmpty else { return [] }

        let prefixes = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
        var paths: [String] = []

        for line in patchText.components(separatedBy: .newlines) {
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

    private static func patchDetail(from patchText: String?) -> ToolPatchDetail? {
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

private struct ToolDescriptor {
    let summaryStyle: ToolSummaryStyle
    let drawerStyle: ToolDrawerStyle
    let detailFields: [ToolDetailField]

    init(summaryStyle: ToolSummaryStyle, detailFields: [ToolDetailField], drawerStyle: ToolDrawerStyle = .standard) {
        self.summaryStyle = summaryStyle
        self.drawerStyle = drawerStyle
        self.detailFields = detailFields
    }
}

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return nil
        case .array, .object:
            return nil
        }
    }

    var prettyDescription: String {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case let .array(values):
            return values.map(\.prettyDescription).joined(separator: ", ")
        case let .object(values):
            return values
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.prettyDescription)" }
                .joined(separator: "\n")
        case .null:
            return "null"
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func decoded<T: Decodable>(_ type: T.Type) -> T? {
        guard JSONSerialization.isValidJSONObject(self.asJSONObject) else {
            return nil
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: self.asJSONObject)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private var asJSONObject: [String: Any] {
        reduce(into: [String: Any]()) { partialResult, item in
            partialResult[item.key] = item.value.foundationObject
        }
    }
}

private extension JSONValue {
    var foundationObject: Any {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return value
        case let .bool(value):
            return value
        case let .object(value):
            return value.mapValues(\.foundationObject)
        case let .array(value):
            return value.map(\.foundationObject)
        case .null:
            return NSNull()
        }
    }
}

extension MessageEnvelope {
    var createdAt: Date {
        Date(timeIntervalSince1970: info.time.created / 1000)
    }

    var totalTokens: Int? {
        info.tokens?.total ?? stepFinish?.tokens?.total
    }

    var visibleText: String {
        let textParts = parts.filter { $0.type == .text }.compactMap(\.text)
        return textParts.joined(separator: "\n\n")
    }

    var reasoningText: String {
        parts.filter { $0.type == .reasoning }.compactMap(\.text).joined(separator: "\n\n")
    }

    var toolParts: [MessagePart] {
        parts.filter { $0.type == .tool }
    }

    var stepFinish: MessagePart? {
        parts.last(where: { $0.type == .stepFinish })
    }
}

extension MessageInfo {
    var modelContextKey: ModelContextKey? {
        let resolvedProviderID = providerID ?? model?.providerID
        let resolvedModelID = modelID ?? model?.modelID

        guard let resolvedProviderID, let resolvedModelID else {
            return nil
        }

        return ModelContextKey(providerID: resolvedProviderID, modelID: resolvedModelID)
    }
}

extension SessionStatus {
    var displayColor: Color {
        switch self {
        case .busy:
            return SessionIndicator.busyColor
        case .retry:
            return SessionIndicator.retryColor
        case .idle, .unknown:
            return SessionIndicator.idleColor
        }
    }

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .busy:
            return "Busy"
        case let .retry(_, message, _):
            return message
        case let .unknown(type):
            return type.capitalized
        }
    }

    var tintName: String {
        switch self {
        case .idle:
            return "Idle"
        case .busy:
            return "Busy"
        case .retry:
            return "Retry"
        case .unknown:
            return "Unknown"
        }
    }

    var showsTodoProgress: Bool {
        switch self {
        case .busy, .retry:
            return true
        case .idle, .unknown:
            return false
        }
    }
}

extension OpenCodeSession: @unchecked Sendable {}
extension OpenCodeServerHealth: @unchecked Sendable {}
extension OpenCodeProject: @unchecked Sendable {}
extension OpenCodeProject.TimeInfo: @unchecked Sendable {}
extension WorkspaceConnection: @unchecked Sendable {}
extension OpenCodeSession.Summary: @unchecked Sendable {}
extension OpenCodeSession.TimeInfo: @unchecked Sendable {}
extension ModelContextKey: @unchecked Sendable {}
extension ModelCatalog: @unchecked Sendable {}
extension ModelProvider: @unchecked Sendable {}
extension ModelDefinition: @unchecked Sendable {}
extension ModelDefinition.Capabilities: @unchecked Sendable {}
extension ModelDefinition.Capabilities.IO: @unchecked Sendable {}
extension ModelDefinition.Limit: @unchecked Sendable {}
extension ModelDefinition.Variant: @unchecked Sendable {}
extension ModelReference: @unchecked Sendable {}
extension ModelOption: @unchecked Sendable {}
extension MessageEnvelope: @unchecked Sendable {}
extension MessageInfo: @unchecked Sendable {}
extension MessageInfo.TimeInfo: @unchecked Sendable {}
extension MessageInfo.ModelRef: @unchecked Sendable {}
extension MessageInfo.PathInfo: @unchecked Sendable {}
extension MessageInfo.TokenCache: @unchecked Sendable {}
extension MessageInfo.TokenInfo: @unchecked Sendable {}
extension MessagePart: @unchecked Sendable {}
extension MessagePart.TimeInfo: @unchecked Sendable {}
extension MessagePart.ToolState: @unchecked Sendable {}
extension MessagePart.FileAttachment: @unchecked Sendable {}
extension MessagePart.SourceRange: @unchecked Sendable {}
extension MessagePart.TokenCache: @unchecked Sendable {}
extension MessagePart.TokenInfo: @unchecked Sendable {}
extension SessionStatus: @unchecked Sendable {}
extension QuestionRequest: @unchecked Sendable {}
extension QuestionRequest.Question: @unchecked Sendable {}
extension QuestionRequest.Question.Option: @unchecked Sendable {}
extension PermissionRequest: @unchecked Sendable {}
extension PermissionRequest.ToolInfo: @unchecked Sendable {}
extension SessionTodo: @unchecked Sendable {}
extension TodoProgress: @unchecked Sendable {}
extension EventPayload: @unchecked Sendable {}
extension SessionWindowContext: @unchecked Sendable {}
extension SessionPaneState: @unchecked Sendable {}
extension SessionIndicator: @unchecked Sendable {}
extension JSONValue: @unchecked Sendable {}
