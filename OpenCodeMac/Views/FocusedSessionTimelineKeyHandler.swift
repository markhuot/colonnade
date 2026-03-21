import AppKit
import SwiftUI

enum SessionTimelineScrollDirection: Equatable {
    case top
    case bottom
}

struct FocusedSessionTimelineKeyEvent {
    static func scrollDirection(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isTextInputActive: Bool
    ) -> SessionTimelineScrollDirection? {
        guard !isTextInputActive else { return nil }

        let activeModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard activeModifiers.intersection(disallowedModifiers).isEmpty else { return nil }

        switch keyCode {
        case 115:
            return .top
        case 119:
            return .bottom
        default:
            return nil
        }
    }
}

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
