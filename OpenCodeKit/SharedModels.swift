import Foundation

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

struct AgentCatalog: Codable, Hashable {
    private struct Wrapper: Codable {
        let agents: [AgentDefinition]?
        let all: [AgentDefinition]?
        let available: [AgentDefinition]?
        let items: [AgentDefinition]?
    }

    private struct RawAgentDefinition: Codable {
        let id: String?
        let name: String?
        let description: String?
        let hidden: Bool?
        let mode: String?
    }

    let agents: [AgentDefinition]

    init(agents: [AgentDefinition]) {
        self.agents = agents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let agents = try? container.decode([AgentDefinition].self) {
            self.agents = agents
            return
        }

        if let wrapper = try? container.decode(Wrapper.self) {
            self.agents = wrapper.agents ?? wrapper.all ?? wrapper.available ?? wrapper.items ?? []
            return
        }

        if let definitionsByID = try? container.decode([String: RawAgentDefinition].self) {
            self.agents = definitionsByID.map { key, value in
                AgentDefinition(
                    id: value.id ?? key,
                    name: value.name,
                    description: value.description,
                    hidden: value.hidden ?? false,
                    mode: value.mode
                )
            }
            return
        }

        if let namesByID = try? container.decode([String: String].self) {
            self.agents = namesByID.map { key, value in
                AgentDefinition(id: key, name: value, description: nil, hidden: false, mode: nil)
            }
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported agent catalog payload")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(agents)
    }
}

struct AgentDefinition: Codable, Identifiable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case hidden
        case mode
    }

    let id: String
    let name: String?
    let description: String?
    let hidden: Bool
    let mode: String?

    init(id: String, name: String?, description: String?, hidden: Bool = false, mode: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.hidden = hidden
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let resolvedName = try container.decodeIfPresent(String.self, forKey: .name)
        let resolvedID = try container.decodeIfPresent(String.self, forKey: .id) ?? resolvedName

        guard let resolvedID, !resolvedID.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Agent is missing both id and name")
        }

        id = resolvedID
        name = resolvedName
        description = try container.decodeIfPresent(String.self, forKey: .description)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }
}

struct AgentOption: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let isRecent: Bool

    var menuLabel: String {
        isRecent ? "\(name) - Recent" : name
    }
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

    init?(key: String) {
        let components = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else {
            return nil
        }

        self.init(providerID: components[0], modelID: components[1])
    }
}

struct ModelOption: Identifiable, Hashable {
    let providerID: String
    let providerName: String
    let modelID: String
    let modelName: String
    let supportsReasoning: Bool
    let thinkingLevels: [String]
    let isServerDefault: Bool
    let isPreferredDefault: Bool
    let isRecent: Bool

    var id: String { reference.key }

    var reference: ModelReference {
        ModelReference(providerID: providerID, modelID: modelID)
    }

    var menuLabel: String {
        if isRecent {
            return "\(modelName) - \(providerName) - Recent"
        }

        if isPreferredDefault {
            return "\(modelName) - \(providerName) - Local Default"
        }

        if isServerDefault {
            return "\(modelName) - \(providerName) - Default"
        }

        return "\(modelName) - \(providerName)"
    }

    var preferenceLabel: String {
        "\(modelName) - \(providerName)"
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

struct SessionPaneState: Codable, Hashable, Identifiable {
    let sessionID: String
    let position: Int
    let width: Double
    let isHidden: Bool

    var id: String { sessionID }
}

enum SessionIndicatorTint: Hashable {
    case idle
    case busy
    case retry
    case permission
}

struct SessionIndicator: Hashable {
    let tint: SessionIndicatorTint
    let label: String?
    let showsTodoProgress: Bool

    static func resolve(status: SessionStatus?, hasPendingPermission: Bool) -> SessionIndicator {
        if hasPendingPermission {
            return SessionIndicator(tint: .permission, label: "Permission Required", showsTodoProgress: false)
        }

        guard let status else {
            return SessionIndicator(tint: .idle, label: nil, showsTodoProgress: false)
        }

        return SessionIndicator(
            tint: status.activityTint,
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

struct SessionDisplay: Identifiable, Hashable {
    let id: String
    let title: String
    let createdAtMS: Double
    let updatedAtMS: Double
    let parentID: String?
    let status: SessionStatus?
    let hasPendingPermission: Bool
    let todoProgress: TodoProgress?
    let contextUsageText: String?
    let isArchived: Bool

    var isSubagentSession: Bool {
        parentID != nil
    }

    var indicator: SessionIndicator {
        SessionIndicator.resolve(status: status, hasPendingPermission: hasPendingPermission)
    }
}

struct PersistenceSnapshot: Equatable {
    let sessions: [SessionDisplay]
    let messagesBySession: [String: [MessageEnvelope]]
    let questionsBySession: [String: [QuestionRequest]]
    let permissionsBySession: [String: [PermissionRequest]]
    let selectedDirectory: String?
    let paneStates: [String: SessionPaneState]

    static let empty = PersistenceSnapshot(
        sessions: [],
        messagesBySession: [:],
        questionsBySession: [:],
        permissionsBySession: [:],
        selectedDirectory: nil,
        paneStates: [:]
    )
}

struct ToolCallSummary: Hashable {
    static let genericIconSystemName = "wrench.and.screwdriver"

    let action: String
    let target: String?
    let iconSystemName: String?
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

struct ToolTaskSummary: Hashable {
    let title: String
    let target: String?
}

enum ToolTodoStatus: Hashable {
    case completed
    case inProgress
    case pending
    case cancelled
    case unknown(String)

    init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "completed":
            self = .completed
        case "in_progress", "in-progress", "running":
            self = .inProgress
        case "cancelled", "canceled":
            self = .cancelled
        case "pending", nil:
            self = .pending
        case let value?:
            self = .unknown(value)
        }
    }
}

struct ToolTodoItem: Identifiable, Hashable {
    let id: Int
    let content: String
    let status: ToolTodoStatus
}

struct ToolTodoDetail: Hashable {
    let items: [ToolTodoItem]
}

enum ToolSummaryStyle: Hashable {
    case standard(ToolCallSummary)
    case patch(ToolPatchSummary)
    case read(ToolReadSummary)
    case task(ToolTaskSummary)
}

enum ToolDrawerStyle: Hashable {
    case standard
    case patch(ToolPatchDetail)
    case todo(ToolTodoDetail)

    var hasVisibleContent: Bool {
        switch self {
        case .standard:
            return false
        case .patch, .todo:
            return true
        }
    }

    var hidesRawOutput: Bool {
        switch self {
        case .todo:
            return true
        case .standard, .patch:
            return false
        }
    }
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
    struct SubagentInvocation: Hashable {
        let taskID: String?
        let sessionID: String?
        let subagentType: String?
    }

    var reasoningTitle: String? {
        guard type == .reasoning else { return nil }

        let directCandidates = [
            metadata?["title"]?.stringValue,
            metadata?["header"]?.stringValue,
            name,
            description,
            prompt
        ]

        for candidate in directCandidates {
            if let normalized = Self.normalizedReasoningTitleCandidate(candidate) {
                return normalized
            }
        }

        return Self.reasoningTitle(from: text)
    }

    var toolDrawerTitle: String? {
        guard let title = Self.normalizedToolSupplementalText(state?.title) else { return nil }

        let output = Self.normalizedToolSupplementalText(state?.output)
        let error = Self.normalizedToolSupplementalText(state?.error)

        if title == output || title == error {
            return nil
        }

        return title
    }

    var isTodoWriteTool: Bool {
        toolKey == "todowrite"
    }

    var subagentInvocation: SubagentInvocation? {
        guard toolKey == "task" else { return nil }

        let input = state?.input ?? [:]
        let metadata = state?.metadata ?? [:]
        let sessionID = Self.firstNonEmptyString([
            Self.jsonString(input["sessionID"]),
            Self.jsonString(input["sessionId"]),
            Self.jsonString(input["subagentSessionID"]),
            Self.jsonString(input["subagentSessionId"]),
            Self.jsonString(metadata["sessionID"]),
            Self.jsonString(metadata["sessionId"]),
            Self.jsonString(metadata["subagentSessionID"]),
            Self.jsonString(metadata["subagentSessionId"]),
            state?.attachments?.compactMap(\.sessionID).first
        ])

        return SubagentInvocation(
            taskID: Self.firstNonEmptyString([
                Self.jsonString(input["task_id"]),
                Self.jsonString(input["taskId"]),
                Self.jsonString(metadata["task_id"]),
                Self.jsonString(metadata["taskId"])
            ]),
            sessionID: sessionID,
            subagentType: Self.firstNonEmptyString([
                Self.jsonString(input["subagent_type"]),
                Self.jsonString(input["subagentType"]),
                Self.jsonString(metadata["subagent_type"]),
                Self.jsonString(metadata["subagentType"]),
                agent
            ])
        )
    }

    var toolPresentation: ToolPresentation {
        let descriptor = toolDescriptor
        let statusLabel = state.flatMap { $0.status == .completed ? nil : $0.status.title }
        let hasSupplementalContent = !(state?.output?.isEmpty ?? true) || !(state?.error?.isEmpty ?? true)
        let hasDescriptorContent = !descriptor.detailFields.isEmpty || descriptor.drawerStyle.hasVisibleContent
        let fallbackDetail: String?

        if !hasDescriptorContent, !hasSupplementalContent, state?.status != .completed {
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
            let paths = patch?.files.map { Self.fileName(from: $0.destinationPath ?? $0.path) ?? ($0.destinationPath ?? $0.path) }
                ?? Self.patchPaths(from: input["patchText"]?.stringValue)
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
                        iconSystemName: ToolCallSummary.genericIconSystemName,
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
                    ToolCallSummary(action: "Search", target: pattern, iconSystemName: "magnifyingglass", additions: nil, deletions: nil)
                ),
                detailFields: Self.detailField(title: "Pattern", value: pattern)
            )
        case "glob":
            let pattern = input["pattern"]?.stringValue
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(action: "Find", target: pattern, iconSystemName: "magnifyingglass", additions: nil, deletions: nil)
                ),
                detailFields: Self.detailField(title: "Pattern", value: pattern)
            )
        case "webfetch":
            let url = input["url"]?.stringValue
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(action: "Fetch", target: url, iconSystemName: "globe", additions: nil, deletions: nil)
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
                        iconSystemName: "terminal",
                        additions: nil,
                        deletions: nil
                    )
                ),
                detailFields: Self.detailField(title: "Command", value: command)
            )
        case "todowrite":
            let todoDetail = Self.todoDetail(from: input["todos"])
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(
                        action: "Todo",
                        target: nil,
                        iconSystemName: "pin",
                        additions: nil,
                        deletions: nil
                    )
                ),
                detailFields: [],
                drawerStyle: todoDetail.map(ToolDrawerStyle.todo) ?? .standard
            )
        case "task":
            let description = Self.normalizedToolSupplementalText(input["description"]?.stringValue)
            let prompt = Self.normalizedToolSupplementalText(input["prompt"]?.stringValue)
            let invocation = subagentInvocation
            let target = description ?? invocation?.subagentType ?? invocation?.taskID

            return ToolDescriptor(
                summaryStyle: .task(
                    ToolTaskSummary(
                        title: "Subagent",
                        target: target
                    )
                ),
                detailFields: [
                    Self.detailField(title: "Type", value: invocation?.subagentType),
                    Self.detailField(title: "Task ID", value: invocation?.taskID),
                    Self.detailField(title: "Prompt", value: prompt)
                ].flatMap { $0 }
            )
        default:
            return ToolDescriptor(
                summaryStyle: .standard(
                    ToolCallSummary(
                        action: state?.title.flatMap { $0.isEmpty ? nil : $0 } ?? Self.humanizedToolName(toolKey),
                        target: nil,
                        iconSystemName: ToolCallSummary.genericIconSystemName,
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

    private static func todoDetail(from value: JSONValue?) -> ToolTodoDetail? {
        guard let todos = value?.arrayValue else { return nil }

        let items = todos.enumerated().compactMap { index, entry -> ToolTodoItem? in
            guard let object = entry.objectValue else { return nil }
            guard let content = Self.normalizedToolSupplementalText(object["content"]?.stringValue) else { return nil }

            return ToolTodoItem(
                id: index,
                content: content,
                status: ToolTodoStatus(rawValue: object["status"]?.stringValue)
            )
        }

        guard !items.isEmpty else { return nil }
        return ToolTodoDetail(items: items)
    }

    static func resolveSubagentSession(
        for invocation: SubagentInvocation,
        in sessions: [SessionDisplay],
        parentSessionID: String,
        referenceTimeMS: Double?
    ) -> SessionDisplay? {
        let part = MessagePart(
            id: "subagent-resolution",
            sessionID: parentSessionID,
            messageID: nil,
            type: .tool,
            text: nil,
            synthetic: nil,
            ignored: nil,
            time: referenceTimeMS.map { .init(start: $0, end: nil, compacted: nil) },
            metadata: nil,
            callID: nil,
            tool: "functions.task",
            state: nil,
            mime: nil,
            filename: nil,
            url: nil,
            reason: nil,
            cost: nil,
            tokens: nil,
            prompt: nil,
            description: nil,
            agent: invocation.subagentType,
            model: nil,
            command: nil,
            name: nil,
            source: nil,
            hash: nil,
            files: nil,
            snapshot: nil
        )

        let resolutions = resolveSubagentSessions(
            for: [part],
            in: sessions,
            parentSessionID: parentSessionID,
            baseReferenceTimeMS: referenceTimeMS,
            invocationOverrides: [part.id: invocation]
        )

        return resolutions[part.id]
    }

    static func resolveSubagentSessions(
        for parts: [MessagePart],
        in sessions: [SessionDisplay],
        parentSessionID: String,
        baseReferenceTimeMS: Double?,
        invocationOverrides: [String: SubagentInvocation] = [:]
    ) -> [String: SessionDisplay] {
        let childSessions = sessions
            .filter { $0.parentID == parentSessionID }
            .sorted(by: subagentSessionSort)

        guard !childSessions.isEmpty else { return [:] }

        var assignments: [String: SessionDisplay] = [:]
        var remainingChildren = childSessions
        let allSessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let candidates = parts.compactMap { part -> (partID: String, invocation: SubagentInvocation, referenceTimeMS: Double?)? in
            let invocation = invocationOverrides[part.id] ?? part.subagentInvocation
            guard let invocation else { return nil }
            return (part.id, invocation, part.time?.start ?? baseReferenceTimeMS)
        }

        for candidate in candidates {
            guard let sessionID = candidate.invocation.sessionID else { continue }

            if let childIndex = remainingChildren.firstIndex(where: { $0.id == sessionID }) {
                assignments[candidate.partID] = remainingChildren.remove(at: childIndex)
                continue
            }

            if let session = allSessionsByID[sessionID] {
                assignments[candidate.partID] = session
            }
        }

        for candidate in candidates where assignments[candidate.partID] == nil {
            guard let childIndex = bestSubagentSessionIndex(in: remainingChildren, referenceTimeMS: candidate.referenceTimeMS) else {
                continue
            }

            assignments[candidate.partID] = remainingChildren.remove(at: childIndex)
        }

        return assignments
    }

    private static func normalizedToolSupplementalText(_ value: String?) -> String? {
        guard let value else { return nil }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func reasoningTitle(from text: String?) -> String? {
        guard let text else { return nil }

        for line in text.components(separatedBy: .newlines) {
            if let candidate = normalizedReasoningTitleCandidate(line) {
                return candidate
            }
        }

        return nil
    }

    private static func normalizedReasoningTitleCandidate(_ value: String?) -> String? {
        guard var candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            return nil
        }

        if candidate.hasPrefix("#") {
            while candidate.first == "#" {
                candidate.removeFirst()
            }
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if candidate.hasPrefix("- ") || candidate.hasPrefix("* ") {
            candidate = String(candidate.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if candidate.hasSuffix(":") {
            candidate.removeLast()
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        candidate = candidate.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !candidate.isEmpty, candidate.count <= 80 else { return nil }
        return candidate
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

    private static func firstNonEmptyString(_ candidates: [String?]) -> String? {
        candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func jsonString(_ value: JSONValue?) -> String? {
        value?.stringValue
    }

    private static var subagentSessionSort: (SessionDisplay, SessionDisplay) -> Bool {
        { lhs, rhs in
            if lhs.createdAtMS == rhs.createdAtMS {
                return lhs.id < rhs.id
            }
            return lhs.createdAtMS < rhs.createdAtMS
        }
    }

    private static func bestSubagentSessionIndex(in sessions: [SessionDisplay], referenceTimeMS: Double?) -> Int? {
        guard !sessions.isEmpty else { return nil }
        guard let referenceTimeMS else { return 0 }

        return sessions.indices.min { lhs, rhs in
            let lhsDistance = abs(sessions[lhs].createdAtMS - referenceTimeMS)
            let rhsDistance = abs(sessions[rhs].createdAtMS - referenceTimeMS)

            if lhsDistance == rhsDistance {
                return subagentSessionSort(sessions[lhs], sessions[rhs])
            }

            return lhsDistance < rhsDistance
        }
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

    var isCompleted: Bool {
        info.time.completed != nil || stepFinish != nil
    }

    var shouldRenderMarkdown: Bool {
        !info.role.isAssistant || isCompleted
    }

    var textParts: [MessagePart] {
        parts.filter { $0.type == .text }
    }

    var reasoningParts: [MessagePart] {
        parts.filter { $0.type == .reasoning }
    }

    var totalTokens: Int? {
        info.tokens?.total ?? stepFinish?.tokens?.total
    }

    var visibleText: String {
        let textParts = textParts.compactMap(\.text)
        return textParts.joined(separator: "\n\n")
    }

    var reasoningText: String {
        reasoningParts.compactMap(\.text).joined(separator: "\n\n")
    }

    var latestReasoningTitle: String? {
        parts.reversed().compactMap(\.reasoningTitle).first
    }

    var toolParts: [MessagePart] {
        parts.filter { $0.type == .tool }
    }

    var stepFinish: MessagePart? {
        parts.last(where: { $0.type == .stepFinish })
    }
}

extension MessagePart {
    var isCompleted: Bool {
        time?.end != nil
    }

    func shouldRenderMarkdown(for role: MessageRole, messageIsCompleted: Bool) -> Bool {
        !role.isAssistant || messageIsCompleted || isCompleted
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
    var isThinkingActive: Bool {
        switch self {
        case .busy, .retry:
            return true
        case .idle, .unknown:
            return false
        }
    }

    var activityTint: SessionIndicatorTint {
        switch self {
        case .busy, .retry:
            return .busy
        case .idle, .unknown:
            return .idle
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
extension SessionPaneState: @unchecked Sendable {}
extension SessionIndicatorTint: @unchecked Sendable {}
extension SessionIndicator: @unchecked Sendable {}
extension SessionDisplay: @unchecked Sendable {}
extension PersistenceSnapshot: @unchecked Sendable {}
extension JSONValue: @unchecked Sendable {}
