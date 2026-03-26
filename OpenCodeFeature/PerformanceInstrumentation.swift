import Foundation
import OSLog

enum DebugRuntime {
    static let isDevelopmentBuild: Bool = {
        #if DEBUG
            true
        #else
            false
        #endif
    }()

    static let isVerboseLoggingEnabled: Bool = {
        isDevelopmentBuild
            && ProcessInfo.processInfo.environment["CI"] == nil
            && ProcessInfo.processInfo.environment["OPENCODE_ENABLE_DEBUG_LOGGING"] != nil
    }()

    static let isViewRenderCountersEnabled: Bool = {
        isDevelopmentBuild
            && ProcessInfo.processInfo.environment["CI"] == nil
            && ProcessInfo.processInfo.environment["OPENCODE_ENABLE_VIEW_RENDER_COUNTERS"] != nil
    }()

}

enum DebugLogging {
    static func notice(_ logger: Logger, _ message: @autoclosure () -> String) {
        guard DebugRuntime.isVerboseLoggingEnabled else { return }
        let renderedMessage = message()
        logger.notice("\(renderedMessage, privacy: .public)")
    }

    static func info(_ logger: Logger, _ message: @autoclosure () -> String) {
        guard DebugRuntime.isVerboseLoggingEnabled else { return }
        let renderedMessage = message()
        logger.info("\(renderedMessage, privacy: .public)")
    }
}
