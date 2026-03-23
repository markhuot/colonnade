import AppKit
import Foundation

enum SessionPaneDrag {
    static func itemProvider(for sessionID: String) -> NSItemProvider {
        NSItemProvider(object: sessionID as NSString)
    }
}
