import Foundation
import OSLog
import SwiftUI

enum PerformanceInstrumentation {
    static let logger = Logger(subsystem: "ai.opencode.app", category: "performance")
    private static let clock = ContinuousClock()

    static var isEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["CI"] == nil
                && ProcessInfo.processInfo.environment["OPENCODE_DISABLE_PERF_LOGGING"] == nil
        #else
            false
        #endif
    }

    @discardableResult
    static func begin(_ name: String, details: @autoclosure () -> String = "") -> ContinuousClock.Instant {
        let start = clock.now
        if isEnabled {
            log("begin name=\(name) \(details())")
        }
        return start
    }

    static func end(
        _ name: String,
        from start: ContinuousClock.Instant,
        details: @autoclosure () -> String = "",
        thresholdMS: Double = 0
    ) {
        guard isEnabled else { return }
        let milliseconds = elapsedMilliseconds(since: start)
        guard milliseconds >= thresholdMS else { return }
        log("end name=\(name) durationMS=\(formatted(milliseconds)) \(details())")
    }

    static func measure<T>(
        _ name: String,
        thresholdMS: Double = 8,
        details: @autoclosure () -> String = "",
        _ body: () -> T
    ) -> T {
        guard isEnabled else { return body() }
        let start = clock.now
        let value = body()
        let milliseconds = elapsedMilliseconds(since: start)
        if milliseconds >= thresholdMS {
            log("measure name=\(name) durationMS=\(formatted(milliseconds)) \(details())")
        }
        return value
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        logger.notice("\(message, privacy: .public)")
    }

    private static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: clock.now).components
        let secondsMS = Double(components.seconds) * 1000
        let attosecondsMS = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsMS + attosecondsMS
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct PerformanceLayoutSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct PerformanceLayoutProbe: ViewModifier {
    let name: String
    let details: () -> String

    @State private var lastReportedSize: CGSize = .zero
    @State private var didReportFirstSize = false

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: PerformanceLayoutSizePreferenceKey.self, value: geometry.size)
                }
            )
            .onAppear {
                PerformanceInstrumentation.log("view-appear name=\(name) \(details())")
            }
            .onDisappear {
                PerformanceInstrumentation.log("view-disappear name=\(name) \(details())")
            }
            .onPreferenceChange(PerformanceLayoutSizePreferenceKey.self) { size in
                if !didReportFirstSize {
                    guard size != .zero else { return }
                    didReportFirstSize = true
                    lastReportedSize = size
                    PerformanceInstrumentation.log(
                        "view-first-size name=\(name) width=\(Int(size.width)) height=\(Int(size.height)) \(details())"
                    )
                    return
                }

                if size == .zero, lastReportedSize != .zero {
                    lastReportedSize = size
                    PerformanceInstrumentation.log("view-size-zero name=\(name) \(details())")
                    return
                }

                guard size != .zero else { return }

                guard abs(size.width - lastReportedSize.width) >= 24 || abs(size.height - lastReportedSize.height) >= 24 else {
                    return
                }

                lastReportedSize = size
                PerformanceInstrumentation.log(
                    "view-size-change name=\(name) width=\(Int(size.width)) height=\(Int(size.height)) \(details())"
                )
            }
    }
}

extension View {
    func performanceLayoutProbe(_ name: String, details: @escaping () -> String = { "" }) -> some View {
        modifier(PerformanceLayoutProbe(name: name, details: details))
    }
}
