import Foundation
import OSLog

enum ServerStartupWaitResult {
    case reached
    case timedOut(lastFailureDescription: String?)
}

enum StartupError: LocalizedError {
    case invalidServerURL
    case serverUnhealthy
    case serverStartTimedOut(String?)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid http:// or https:// server URL."
        case .serverUnhealthy:
            return "The remote opencode server did not report as healthy."
        case let .serverStartTimedOut(lastFailureDescription):
            var message = "The local opencode server did not start on :4096 in time."
            if let lastFailureDescription, !lastFailureDescription.isEmpty {
                message += "\n\nLast health check: \(lastFailureDescription)"
            }
            return message
        }
    }
}

struct RemoteServerConnectionResult: Equatable {
    let serverURL: URL
    let normalizedURLText: String
    let projectSuggestions: [String]
}

struct WorkspaceServerController {
    typealias APIClientProvider = @Sendable (URL) -> any OpenCodeAPIClientProtocol
    typealias LocalServerStarter = @Sendable (String) throws -> LocalServerLaunchHandle
    typealias LocalServerExecutablePathProvider = @Sendable () -> String
    typealias ServerWaiter = @Sendable (URL, Duration) async -> ServerStartupWaitResult

    private let logger = Logger(subsystem: "ai.opencode.app", category: "workspace-server")

    private let apiClientProvider: APIClientProvider
    private let localServerStarter: LocalServerStarter
    private let localServerExecutablePathProvider: LocalServerExecutablePathProvider
    private let serverWaiter: ServerWaiter?

    init(
        apiClientProvider: @escaping APIClientProvider,
        localServerStarter: @escaping LocalServerStarter,
        localServerExecutablePathProvider: @escaping LocalServerExecutablePathProvider,
        serverWaiter: ServerWaiter? = nil
    ) {
        self.apiClientProvider = apiClientProvider
        self.localServerStarter = localServerStarter
        self.localServerExecutablePathProvider = localServerExecutablePathProvider
        self.serverWaiter = serverWaiter
    }

    func startLocalServerIfNeeded(at url: URL) async throws -> LocalServerLaunchHandle? {
        let status = await serverReachabilityStatus(at: url)
        guard !status.isReachable else { return nil }

        let executablePath = localServerExecutablePathProvider()
        logger.notice("Starting local server from \(executablePath, privacy: .public)")
        let handle = try localServerStarter(executablePath)
        let waitResult = if let serverWaiter {
            await serverWaiter(url, .seconds(10))
        } else {
            await waitForServer(at: url, timeout: .seconds(10))
        }

        switch waitResult {
        case .reached:
            return handle
        case let .timedOut(lastFailureDescription):
            throw StartupError.serverStartTimedOut(lastFailureDescription)
        }
    }

    func connectToRemoteServer(from urlText: String) async throws -> RemoteServerConnectionResult {
        let resolvedURL = try normalizedServerURL(from: urlText)
        let client = apiClientProvider(resolvedURL)
        let health = try await client.health()
        guard health.healthy else {
            throw StartupError.serverUnhealthy
        }

        let projects = try await client.projects()
        return RemoteServerConnectionResult(
            serverURL: resolvedURL,
            normalizedURLText: resolvedURL.absoluteString,
            projectSuggestions: projects.map { $0.worktree }.sorted()
        )
    }

    func refreshRemoteProjectSuggestions(serverURL: URL) async -> [String] {
        do {
            let projects = try await apiClientProvider(serverURL).projects()
            return projects.map { $0.worktree }.sorted()
        } catch {
            logger.notice("Project suggestions unavailable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func normalizedServerURL(from text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StartupError.invalidServerURL
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            throw StartupError.invalidServerURL
        }

        components.path = components.path.isEmpty ? "" : components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = components.url else {
            throw StartupError.invalidServerURL
        }

        return url
    }

    private func serverReachabilityStatus(at url: URL) async -> (isReachable: Bool, failureDescription: String?) {
        do {
            let health = try await apiClientProvider(url).health()
            guard health.healthy else {
                let detail = if health.version.isEmpty {
                    "Health check reported an unhealthy server."
                } else {
                    "Health check reported an unhealthy server (version \(health.version))."
                }
                return (false, detail)
            }

            return (true, nil)
        } catch {
            return (false, describeServerReachabilityFailure(error, url: url))
        }
    }

    private func waitForServer(at url: URL, timeout: Duration) async -> ServerStartupWaitResult {
        let clock = ContinuousClock()
        let start = clock.now
        var lastFailureDescription: String?

        while start.duration(to: clock.now) < timeout {
            let status = await serverReachabilityStatus(at: url)
            if status.isReachable {
                return .reached
            }

            if let failureDescription = status.failureDescription {
                lastFailureDescription = failureDescription
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return .timedOut(lastFailureDescription: lastFailureDescription)
            }
        }

        return .timedOut(lastFailureDescription: lastFailureDescription)
    }

    private func describeServerReachabilityFailure(_ error: Error, url: URL) -> String {
        let endpoint = url.appendingPathComponent("global/health").absoluteString
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if description.isEmpty {
            return "Health check at \(endpoint) failed with an unknown error."
        }

        return "Health check at \(endpoint) failed: \(description)"
    }
}
