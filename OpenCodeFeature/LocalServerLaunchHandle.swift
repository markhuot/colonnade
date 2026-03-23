import Foundation

struct LocalServerLaunchHandle: @unchecked Sendable {
    let storage: Any?

    init(_ storage: Any? = nil) {
        self.storage = storage
    }
}
