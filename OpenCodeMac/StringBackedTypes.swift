import Foundation

protocol UnknownStringCodableEnum: Codable, Hashable, Sendable {
    init(rawString: String)
    var rawString: String { get }
}

extension UnknownStringCodableEnum {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawString: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawString)
    }
}

enum MessageRole: UnknownStringCodableEnum, Sendable {
    case assistant
    case system
    case tool
    case user
    case unknown(String)

    init(rawString: String) {
        switch rawString {
        case "assistant":
            self = .assistant
        case "system":
            self = .system
        case "tool":
            self = .tool
        case "user":
            self = .user
        default:
            self = .unknown(rawString)
        }
    }

    var rawString: String {
        switch self {
        case .assistant:
            return "assistant"
        case .system:
            return "system"
        case .tool:
            return "tool"
        case .user:
            return "user"
        case let .unknown(value):
            return value
        }
    }

    var title: String {
        switch self {
        case .assistant:
            return "Assistant"
        case .system:
            return "System"
        case .tool:
            return "Tool"
        case .user:
            return "You"
        case let .unknown(value):
            return value.capitalized
        }
    }

    var isAssistant: Bool {
        if case .assistant = self {
            return true
        }
        return false
    }
}

enum MessagePartKind: UnknownStringCodableEnum, Sendable {
    case reasoning
    case stepFinish
    case text
    case tool
    case unknown(String)

    init(rawString: String) {
        switch rawString {
        case "reasoning":
            self = .reasoning
        case "step-finish":
            self = .stepFinish
        case "text":
            self = .text
        case "tool":
            self = .tool
        default:
            self = .unknown(rawString)
        }
    }

    var rawString: String {
        switch self {
        case .reasoning:
            return "reasoning"
        case .stepFinish:
            return "step-finish"
        case .text:
            return "text"
        case .tool:
            return "tool"
        case let .unknown(value):
            return value
        }
    }
}

enum MessagePartDeltaField: UnknownStringCodableEnum, Sendable {
    case error
    case output
    case text
    case unknown(String)

    init(rawString: String) {
        switch rawString {
        case "error":
            self = .error
        case "output":
            self = .output
        case "text":
            self = .text
        default:
            self = .unknown(rawString)
        }
    }

    var rawString: String {
        switch self {
        case .error:
            return "error"
        case .output:
            return "output"
        case .text:
            return "text"
        case let .unknown(value):
            return value
        }
    }
}

enum ToolExecutionStatus: UnknownStringCodableEnum, Sendable {
    case completed
    case error
    case pending
    case running
    case unknown(String)

    init(rawString: String) {
        switch rawString {
        case "completed":
            self = .completed
        case "error":
            self = .error
        case "pending":
            self = .pending
        case "running":
            self = .running
        default:
            self = .unknown(rawString)
        }
    }

    var rawString: String {
        switch self {
        case .completed:
            return "completed"
        case .error:
            return "error"
        case .pending:
            return "pending"
        case .running:
            return "running"
        case let .unknown(value):
            return value
        }
    }

    var title: String {
        rawString.capitalized
    }
}

enum PermissionReply: UnknownStringCodableEnum, Sendable {
    case always
    case once
    case reject
    case unknown(String)

    init(rawString: String) {
        switch rawString {
        case "always":
            self = .always
        case "once":
            self = .once
        case "reject":
            self = .reject
        default:
            self = .unknown(rawString)
        }
    }

    var rawString: String {
        switch self {
        case .always:
            return "always"
        case .once:
            return "once"
        case .reject:
            return "reject"
        case let .unknown(value):
            return value
        }
    }
}

enum TodoStatus: UnknownStringCodableEnum, Sendable {
    case cancelled
    case completed
    case inProgress
    case pending
    case unknown(String)

    init(rawString: String) {
        switch rawString {
        case "cancelled":
            self = .cancelled
        case "completed":
            self = .completed
        case "in_progress":
            self = .inProgress
        case "pending":
            self = .pending
        default:
            self = .unknown(rawString)
        }
    }

    var rawString: String {
        switch self {
        case .cancelled:
            return "cancelled"
        case .completed:
            return "completed"
        case .inProgress:
            return "in_progress"
        case .pending:
            return "pending"
        case let .unknown(value):
            return value
        }
    }
}

enum TodoPriority: UnknownStringCodableEnum, Sendable {
    case high
    case low
    case medium
    case unknown(String)

    init(rawString: String) {
        switch rawString {
        case "high":
            self = .high
        case "low":
            self = .low
        case "medium":
            self = .medium
        default:
            self = .unknown(rawString)
        }
    }

    var rawString: String {
        switch self {
        case .high:
            return "high"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case let .unknown(value):
            return value
        }
    }
}

enum SessionEventName: UnknownStringCodableEnum, Sendable {
    case messagePartDelta
    case messagePartRemoved
    case messagePartUpdated
    case messageRemoved
    case messageUpdated
    case permissionAsked
    case permissionReplied
    case questionAsked
    case questionRejected
    case questionReplied
    case serverConnected
    case sessionCreated
    case sessionDeleted
    case sessionError
    case sessionStatus
    case sessionUpdated
    case todoUpdated
    case unknown(String)

    init(rawString: String) {
        switch rawString {
        case "message.part.delta":
            self = .messagePartDelta
        case "message.part.removed":
            self = .messagePartRemoved
        case "message.part.updated":
            self = .messagePartUpdated
        case "message.removed":
            self = .messageRemoved
        case "message.updated":
            self = .messageUpdated
        case "permission.asked":
            self = .permissionAsked
        case "permission.replied":
            self = .permissionReplied
        case "question.asked":
            self = .questionAsked
        case "question.rejected":
            self = .questionRejected
        case "question.replied":
            self = .questionReplied
        case "server.connected":
            self = .serverConnected
        case "session.created":
            self = .sessionCreated
        case "session.deleted":
            self = .sessionDeleted
        case "session.error":
            self = .sessionError
        case "session.status":
            self = .sessionStatus
        case "session.updated":
            self = .sessionUpdated
        case "todo.updated":
            self = .todoUpdated
        default:
            self = .unknown(rawString)
        }
    }

    var rawString: String {
        switch self {
        case .messagePartDelta:
            return "message.part.delta"
        case .messagePartRemoved:
            return "message.part.removed"
        case .messagePartUpdated:
            return "message.part.updated"
        case .messageRemoved:
            return "message.removed"
        case .messageUpdated:
            return "message.updated"
        case .permissionAsked:
            return "permission.asked"
        case .permissionReplied:
            return "permission.replied"
        case .questionAsked:
            return "question.asked"
        case .questionRejected:
            return "question.rejected"
        case .questionReplied:
            return "question.replied"
        case .serverConnected:
            return "server.connected"
        case .sessionCreated:
            return "session.created"
        case .sessionDeleted:
            return "session.deleted"
        case .sessionError:
            return "session.error"
        case .sessionStatus:
            return "session.status"
        case .sessionUpdated:
            return "session.updated"
        case .todoUpdated:
            return "todo.updated"
        case let .unknown(value):
            return value
        }
    }
}

enum SessionLifecycleEvent: Hashable, Sendable {
    case created
    case deleted
    case updated
}

enum EventPropertyKey: String, Sendable {
    case delta
    case error
    case field
    case info
    case messageID
    case part
    case partID
    case sessionID
    case status
}

extension SessionEventName {
    var lifecycleEvent: SessionLifecycleEvent? {
        switch self {
        case .sessionCreated:
            return .created
        case .sessionDeleted:
            return .deleted
        case .sessionUpdated:
            return .updated
        case .messagePartDelta,
             .messagePartRemoved,
             .messagePartUpdated,
             .messageRemoved,
             .messageUpdated,
             .permissionAsked,
             .permissionReplied,
             .questionAsked,
             .questionRejected,
             .questionReplied,
             .serverConnected,
             .sessionError,
             .sessionStatus,
             .todoUpdated,
             .unknown:
            return nil
        }
    }
}
