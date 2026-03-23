import Foundation
import OSLog

protocol OpenCodeAPIClientProtocol: Sendable {
    func health() async throws -> OpenCodeServerHealth
    func projects() async throws -> [OpenCodeProject]
    func agentCatalog() async throws -> AgentCatalog
    func sessions(directory: String) async throws -> [OpenCodeSession]
    func sessionStatus(directory: String) async throws -> [String: SessionStatus]
    func messages(directory: String, sessionID: String) async throws -> [MessageEnvelope]
    func todos(directory: String, sessionID: String) async throws -> [SessionTodo]
    func createSession(directory: String, title: String?, parentID: String?) async throws -> OpenCodeSession
    func archiveSession(directory: String, sessionID: String, archivedAtMS: Double) async throws -> OpenCodeSession
    func abortSession(directory: String, sessionID: String) async throws
    func sendMessage(directory: String, sessionID: String, text: String, agent: String?, model: ModelReference?, variant: String?) async throws
    func modelCatalog() async throws -> ModelCatalog
    func questions(directory: String) async throws -> [QuestionRequest]
    func permissions(directory: String) async throws -> [PermissionRequest]
    func modelContextLimits() async throws -> [ModelContextKey: Int]
    func replyToQuestion(directory: String, requestID: String, answers: [[String]]) async throws
    func rejectQuestion(directory: String, requestID: String) async throws
    func replyToPermission(directory: String, requestID: String, reply: PermissionReply, message: String?) async throws
    func openEventStream(directory: String) async throws -> OpenCodeAPIClient.EventStreamConnection
}

struct OpenCodeAPIClient: @unchecked Sendable {
    let baseURL: URL
    private let logger = Logger(subsystem: "ai.opencode.app", category: "network")
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    struct EventStreamConnection {
        let bytes: URLSession.AsyncBytes
        let response: HTTPURLResponse
    }

    init(baseURL: URL = URL(string: "http://127.0.0.1:4096")!) {
        self.baseURL = baseURL
        session = URLSession(configuration: .default)
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func sessions(directory: String) async throws -> [OpenCodeSession] {
        try await get("/session", directory: directory)
    }

    func health() async throws -> OpenCodeServerHealth {
        try await globalGet("/global/health")
    }

    func projects() async throws -> [OpenCodeProject] {
        try await globalGet("/project")
    }

    func agentCatalog() async throws -> AgentCatalog {
        let candidatePaths = ["/agent", "/global/agent"]
        var lastError: Error?

        for path in candidatePaths {
            do {
                return try await globalGet(path)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    func sessionStatus(directory: String) async throws -> [String: SessionStatus] {
        try await get("/session/status", directory: directory)
    }

    func messages(directory: String, sessionID: String) async throws -> [MessageEnvelope] {
        try await get("/session/\(sessionID)/message", directory: directory)
    }

    func todos(directory: String, sessionID: String) async throws -> [SessionTodo] {
        try await get("/session/\(sessionID)/todo", directory: directory)
    }

    func createSession(directory: String, title: String? = nil, parentID: String? = nil) async throws -> OpenCodeSession {
        struct Body: Encodable {
            let parentID: String?
            let title: String?
        }

        let parentDescription = parentID ?? "nil"
        logger.notice(
            "Create session request directory=\(directory, privacy: .public) parentID=\(parentDescription, privacy: .public) titleProvided=\(title != nil, privacy: .public)"
        )

        let session: OpenCodeSession = try await send(
            path: "/session",
            method: "POST",
            directory: directory,
            body: Body(parentID: parentID, title: title),
            responseType: OpenCodeSession.self
        )

        logger.notice(
            "Create session succeeded directory=\(directory, privacy: .public) sessionID=\(session.id, privacy: .public)"
        )

        return session
    }

    func archiveSession(directory: String, sessionID: String, archivedAtMS: Double = Date().timeIntervalSince1970 * 1000) async throws -> OpenCodeSession {
        struct TimeBody: Encodable {
            let archived: Double
        }

        struct Body: Encodable {
            let time: TimeBody
        }

        return try await send(
            path: "/session/\(sessionID)",
            method: "PATCH",
            directory: directory,
            body: Body(time: TimeBody(archived: archivedAtMS)),
            responseType: OpenCodeSession.self
        )
    }

    func abortSession(directory: String, sessionID: String) async throws {
        _ = try await send(
            path: "/session/\(sessionID)/abort",
            method: "POST",
            directory: directory,
            body: Optional<String>.none,
            responseType: Bool.self,
            allowNoBody: true
        )
    }

    func sendMessage(directory: String, sessionID: String, text: String, agent: String?, model: ModelReference?, variant: String?) async throws {
        struct TextPartInput: Encodable {
            let type: MessagePartKind = .text
            let text: String
        }

        struct Body: Encodable {
            let parts: [TextPartInput]
            let agent: String?
            let model: ModelReference?
            let variant: String?
        }

        let agentDescription = agent ?? "nil"
        let variantDescription = variant ?? "nil"
        logger.notice(
            "Send message request directory=\(directory, privacy: .public) sessionID=\(sessionID, privacy: .public) textBytes=\(text.utf8.count, privacy: .public) agent=\(agentDescription, privacy: .public) model=\(modelDescription(model), privacy: .public) variant=\(variantDescription, privacy: .public)"
        )

        _ = try await send(
            path: "/session/\(sessionID)/prompt_async",
            method: "POST",
            directory: directory,
            body: Body(parts: [TextPartInput(text: text)], agent: agent, model: model, variant: variant),
            responseType: EmptyResponse.self,
            acceptEmptyResponse: true
        )

        logger.notice(
            "Send message accepted directory=\(directory, privacy: .public) sessionID=\(sessionID, privacy: .public)"
        )
    }

    func modelCatalog() async throws -> ModelCatalog {
        var request = URLRequest(url: globalURL(path: "/provider"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, requestURL: request.url)
        return try decoder.decode(ModelCatalog.self, from: data)
    }

    func questions(directory: String) async throws -> [QuestionRequest] {
        try await get("/question", directory: directory)
    }

    func permissions(directory: String) async throws -> [PermissionRequest] {
        try await get("/permission", directory: directory)
    }

    func modelContextLimits() async throws -> [ModelContextKey: Int] {
        let catalog = try await modelCatalog()
        var limits: [ModelContextKey: Int] = [:]

        for provider in catalog.providers {
            for (fallbackModelID, model) in provider.models {
                let providerID = model.providerID
                let modelID = model.id.isEmpty ? fallbackModelID : model.id

                if let contextLimit = model.limit?.context, contextLimit > 0 {
                    limits[ModelContextKey(providerID: providerID, modelID: modelID)] = contextLimit
                }
            }
        }

        return limits
    }

    func replyToQuestion(directory: String, requestID: String, answers: [[String]]) async throws {
        struct Body: Encodable {
            let answers: [[String]]
        }

        _ = try await send(
            path: "/question/\(requestID)/reply",
            method: "POST",
            directory: directory,
            body: Body(answers: answers),
            responseType: Bool.self
        )
    }

    func rejectQuestion(directory: String, requestID: String) async throws {
        _ = try await send(
            path: "/question/\(requestID)/reject",
            method: "POST",
            directory: directory,
            body: Optional<String>.none,
            responseType: Bool.self,
            allowNoBody: true
        )
    }

    func replyToPermission(directory: String, requestID: String, reply: PermissionReply, message: String? = nil) async throws {
        struct Body: Encodable {
            let reply: PermissionReply
            let message: String?
        }

        _ = try await send(
            path: "/permission/\(requestID)/reply",
            method: "POST",
            directory: directory,
            body: Body(reply: reply, message: message),
            responseType: Bool.self
        )
    }

    func openEventStream(directory: String) async throws -> EventStreamConnection {
        var request = URLRequest(url: url(path: "/event", directory: directory))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 60 * 60 * 24
        let requestURLString = request.url?.absoluteString ?? "nil"

        logger.notice(
            "Opening event stream directory=\(directory, privacy: .public) url=\(requestURLString, privacy: .public)"
        )

        do {
            let (bytes, response) = try await session.bytes(for: request)
            try validate(response: response, requestURL: request.url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            logger.notice(
                "Event stream opened directory=\(directory, privacy: .public) status=\(httpResponse.statusCode, privacy: .public) contentType=\(contentType, privacy: .public)"
            )
            if !contentType.localizedCaseInsensitiveContains("text/event-stream") {
                logger.error(
                    "Event stream content type mismatch directory=\(directory, privacy: .public) contentType=\(contentType, privacy: .public)"
                )
            }

            return EventStreamConnection(bytes: bytes, response: httpResponse)
        } catch {
            logger.error(
                "Open event stream failed directory=\(directory, privacy: .public) url=\(requestURLString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func get<T: Decodable>(_ path: String, directory: String) async throws -> T {
        try await send(path: path, method: "GET", directory: directory, body: Optional<String>.none, responseType: T.self, allowNoBody: true)
    }

    private func globalGet<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: globalURL(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, requestURL: request.url)
        return try decoder.decode(T.self, from: data)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        directory: String,
        body: Body?,
        responseType: Response.Type,
        acceptEmptyResponse: Bool = false,
        allowNoBody: Bool = false
    ) async throws -> Response {
        var request = URLRequest(url: url(path: path, directory: directory))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if !allowNoBody && method != "GET" {
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, requestURL: request.url)

        if acceptEmptyResponse, data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }

        if Response.self == EmptyResponse.self, data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func url(path: String, directory: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "directory", value: directory)
        ]
        return components.url!
    }

    private func globalURL(path: String) -> URL {
        baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func validate(response: URLResponse, data: Data? = nil, requestURL: URL? = nil) throws {
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ..< 300).contains(response.statusCode) else {
            let bodySnippet = responseBodySnippet(from: data)
            throw APIError.httpStatus(code: response.statusCode, path: requestURL?.path, bodySnippet: bodySnippet)
        }
    }

    private func responseBodySnippet(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return String(value.prefix(300))
    }

    private func modelDescription(_ model: ModelReference?) -> String {
        guard let model else { return "nil" }
        return "\(model.providerID)/\(model.modelID)"
    }
}

extension OpenCodeAPIClient: OpenCodeAPIClientProtocol {}

enum APIError: LocalizedError {
    case invalidResponse
    case httpStatus(code: Int, path: String?, bodySnippet: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The opencode server returned an invalid response."
        case let .httpStatus(statusCode, path, bodySnippet):
            let pathSegment = path.map { " for \($0)" } ?? ""
            let bodySegment = bodySnippet.map { " Response: \($0)" } ?? ""
            return "The opencode server returned HTTP \(statusCode)\(pathSegment).\(bodySegment)"
        }
    }
}

private struct EmptyResponse: Codable {
    init() {}
}
