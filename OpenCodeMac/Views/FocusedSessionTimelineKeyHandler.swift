import AppKit
import SwiftUI

struct FocusedSessionTimelineKeyHandler: NSViewRepresentable {
    let onDirection: (SessionTimelineScrollDirection) -> Void

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        view.onDirection = onDirection
        return view
    }

    func updateNSView(_ nsView: KeyMonitorView, context: Context) {
        nsView.onDirection = onDirection
    }
}

final class KeyMonitorView: NSView {
    var onDirection: ((SessionTimelineScrollDirection) -> Void)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func installMonitor() {
        removeMonitor()

        guard let window else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }

            let direction = FocusedSessionTimelineKeyEvent.scrollDirection(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                isTextInputActive: window.firstResponder is NSTextView
            )

            guard let direction else { return event }
            self.onDirection?(direction)
            return nil
        }
    }

    private func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
