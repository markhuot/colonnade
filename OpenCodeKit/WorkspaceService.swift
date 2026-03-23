import Foundation

protocol WorkspaceServiceProtocol: Sendable {
    func loadWorkspace(directory: String) async throws -> WorkspaceSnapshot
    func loadInteractions(directory: String) async throws -> InteractionSnapshot
    func createSession(directory: String, title: String?, parentID: String?) async throws -> OpenCodeSession
    func archiveSession(directory: String, sessionID: String) async throws -> OpenCodeSession
    func stopSession(directory: String, sessionID: String) async throws
    func loadSessions(directory: String) async throws -> [OpenCodeSession]
    func loadMessages(directory: String, sessionID: String) async throws -> [MessageEnvelope]
    func loadTodos(directory: String, sessionID: String) async throws -> [SessionTodo]
    func loadStatuses(directory: String) async throws -> [String: SessionStatus]
    func loadAgentCatalog() async throws -> AgentCatalog
    func loadModelContextLimits() async throws -> [ModelContextKey: Int]
    func loadModelCatalog() async throws -> ModelCatalog
    func sendMessage(directory: String, sessionID: String, text: String, agent: String?, model: ModelReference?, variant: String?) async throws
    func replyToPermission(directory: String, requestID: String, reply: PermissionReply) async throws
    func replyToQuestion(directory: String, requestID: String, answers: [[String]]) async throws
    func rejectQuestion(directory: String, requestID: String) async throws
}

struct WorkspaceSnapshot {
    let sessions: [OpenCodeSession]
    let statuses: [String: SessionStatus]
    let questions: [QuestionRequest]
    let permissions: [PermissionRequest]
}

struct InteractionSnapshot {
    let questions: [QuestionRequest]
    let permissions: [PermissionRequest]
}

struct WorkspaceService: WorkspaceServiceProtocol {
    let client: any OpenCodeAPIClientProtocol

    func loadWorkspace(directory: String) async throws -> WorkspaceSnapshot {
        async let sessionsTask = client.sessions(directory: directory)
        async let statusesTask = client.sessionStatus(directory: directory)
        async let questionsTask = client.questions(directory: directory)
        async let permissionsTask = client.permissions(directory: directory)

        return try await WorkspaceSnapshot(
            sessions: sessionsTask,
            statuses: statusesTask,
            questions: questionsTask,
            permissions: permissionsTask
        )
    }

    func loadInteractions(directory: String) async throws -> InteractionSnapshot {
        async let questionsTask = client.questions(directory: directory)
        async let permissionsTask = client.permissions(directory: directory)

        return try await InteractionSnapshot(
            questions: questionsTask,
            permissions: permissionsTask
        )
    }

    func createSession(directory: String, title: String? = nil, parentID: String? = nil) async throws -> OpenCodeSession {
        try await client.createSession(directory: directory, title: title, parentID: parentID)
    }

    func archiveSession(directory: String, sessionID: String) async throws -> OpenCodeSession {
        try await client.archiveSession(directory: directory, sessionID: sessionID, archivedAtMS: Date().timeIntervalSince1970 * 1000)
    }

    func stopSession(directory: String, sessionID: String) async throws {
        try await client.abortSession(directory: directory, sessionID: sessionID)
    }

    func loadSessions(directory: String) async throws -> [OpenCodeSession] {
        try await client.sessions(directory: directory)
    }

    func loadMessages(directory: String, sessionID: String) async throws -> [MessageEnvelope] {
        try await client.messages(directory: directory, sessionID: sessionID)
    }

    func loadTodos(directory: String, sessionID: String) async throws -> [SessionTodo] {
        try await client.todos(directory: directory, sessionID: sessionID)
    }

    func loadStatuses(directory: String) async throws -> [String: SessionStatus] {
        try await client.sessionStatus(directory: directory)
    }

    func loadAgentCatalog() async throws -> AgentCatalog {
        try await client.agentCatalog()
    }

    func loadModelContextLimits() async throws -> [ModelContextKey: Int] {
        try await client.modelContextLimits()
    }

    func loadModelCatalog() async throws -> ModelCatalog {
        try await client.modelCatalog()
    }

    func sendMessage(directory: String, sessionID: String, text: String, agent: String?, model: ModelReference?, variant: String?) async throws {
        try await client.sendMessage(directory: directory, sessionID: sessionID, text: text, agent: agent, model: model, variant: variant)
    }

    func replyToPermission(directory: String, requestID: String, reply: PermissionReply) async throws {
        try await client.replyToPermission(directory: directory, requestID: requestID, reply: reply, message: nil)
    }

    func replyToQuestion(directory: String, requestID: String, answers: [[String]]) async throws {
        try await client.replyToQuestion(directory: directory, requestID: requestID, answers: answers)
    }

    func rejectQuestion(directory: String, requestID: String) async throws {
        try await client.rejectQuestion(directory: directory, requestID: requestID)
    }
}
