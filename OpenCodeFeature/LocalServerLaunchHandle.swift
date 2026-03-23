import Foundation
import OSLog

struct LocalServerLaunchHandle: @unchecked Sendable {
    let storage: Any?

    init(_ storage: Any? = nil) {
        self.storage = storage
    }
}

enum LocalServerLaunchError: LocalizedError {
    case executableNotFound(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(path):
            return "The opencode executable could not be found at \(path)."
        case let .launchFailed(reason):
            return "The local opencode server failed to launch. \(reason)"
        }
    }
}

enum LocalServerLauncher {
    static func launch(opencodePath: String, logger: Logger? = nil) throws -> LocalServerLaunchHandle {
        let expandedPath = NSString(string: opencodePath).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
            throw LocalServerLaunchError.executableNotFound(expandedPath)
        }

        let parentPID = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            #"parent_pid="$1"; opencode_path="$2"; trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true' EXIT HUP INT TERM; "$opencode_path" serve --hostname 127.0.0.1 --port 4096 --print-logs --log-level DEBUG & child=$!; while kill -0 "$parent_pid" 2>/dev/null && kill -0 "$child" 2>/dev/null; do sleep 1; done; kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true"#,
            "sh",
            String(parentPID),
            expandedPath
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let source = DispatchSource.makeReadSource(fileDescriptor: outputPipe.fileHandleForReading.fileDescriptor, queue: .global(qos: .utility))
        source.setEventHandler {
            let data = outputPipe.fileHandleForReading.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \ .isNewline) {
                logger?.notice("Local server: \(String(line))")
            }
        }
        source.setCancelHandler {
            try? outputPipe.fileHandleForReading.close()
        }
        source.resume()

        process.terminationHandler = { process in
            logger?.error("Local server exited status=\(process.terminationStatus)")
            source.cancel()
        }

        do {
            try process.run()
            logger?.notice("Started local server pid=\(process.processIdentifier) path=\(expandedPath)")
            let storage = LocalServerProcessStorage(process: process, outputSource: source, logger: logger)
            LocalServerLifecycle.shared.register(storage)
            return LocalServerLaunchHandle(storage)
        } catch {
            source.cancel()
            throw LocalServerLaunchError.launchFailed(error.localizedDescription)
        }
    }

    static func shutdownAll() {
        LocalServerLifecycle.shared.shutdownAll()
    }
}

final class LocalServerProcessStorage: @unchecked Sendable {
    let process: Process
    let outputSource: DispatchSourceRead
    private let logger: Logger?
    private let onShutdown: (@Sendable (ObjectIdentifier) -> Void)?
    let identifier = ObjectIdentifier(UUIDBox())
    private let lock = NSLock()
    private var didShutdown = false

    init(
        process: Process,
        outputSource: DispatchSourceRead,
        logger: Logger?,
        onShutdown: (@Sendable (ObjectIdentifier) -> Void)? = { LocalServerLifecycle.shared.unregister(identifier: $0) }
    ) {
        self.process = process
        self.outputSource = outputSource
        self.logger = logger
        self.onShutdown = onShutdown
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        lock.lock()
        if didShutdown {
            lock.unlock()
            return
        }
        didShutdown = true
        lock.unlock()

        outputSource.cancel()
        if process.isRunning {
            logger?.notice("Stopping local server pid=\(self.process.processIdentifier)")
            self.process.terminate()
        }
        onShutdown?(identifier)
    }
}

final class LocalServerLifecycle: @unchecked Sendable {
    static let shared = LocalServerLifecycle()

    private let lock = NSLock()
    private var storages: [ObjectIdentifier: LocalServerProcessStorage] = [:]

    func register(_ storage: LocalServerProcessStorage) {
        lock.lock()
        storages[storage.identifier] = storage
        lock.unlock()
    }

    func unregister(identifier: ObjectIdentifier) {
        lock.lock()
        storages.removeValue(forKey: identifier)
        lock.unlock()
    }

    func shutdownAll() {
        lock.lock()
        let allStorages = Array(storages.values)
        storages.removeAll()
        lock.unlock()

        for storage in allStorages {
            storage.shutdown()
        }
    }
}

private final class UUIDBox {}
