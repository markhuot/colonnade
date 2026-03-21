import Foundation
import SwiftUI

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
    let directory: String
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
