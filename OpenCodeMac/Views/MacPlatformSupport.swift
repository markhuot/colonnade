import AppKit
import SwiftUI

enum MacModifierKeyState {
    static func isOptionPressed() -> Bool {
        NSEvent.modifierFlags.contains(.option)
    }
}

enum MacCursorStyle {
    static func pushPaneResize() {
        NSCursor.resizeLeftRight.push()
    }

    static func pop() {
        NSCursor.pop()
    }
}

struct SelectableToolTextView: NSViewRepresentable {
    let text: String
    let textColor: NSColor

    private static let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    private static let verticalPadding: CGFloat = 6
    private static let horizontalPadding: CGFloat = 2
    private static let maxHeight: CGFloat = 110

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: Self.horizontalPadding, height: Self.verticalPadding)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        update(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        update(textView)
    }

    var idealHeight: CGFloat {
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: Self.font))
        let lineCount = max(text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        let contentHeight = lineHeight * CGFloat(lineCount) + (Self.verticalPadding * 2)
        return min(max(contentHeight, lineHeight + (Self.verticalPadding * 2)), Self.maxHeight)
    }

    private func update(_ textView: NSTextView) {
        if textView.string != text {
            textView.string = text
        }

        textView.font = Self.font
        textView.textColor = textColor
    }
}

struct SessionListEscapeKeyHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> SessionListEscapeKeyMonitorView {
        let view = SessionListEscapeKeyMonitorView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: SessionListEscapeKeyMonitorView, context: Context) {
        nsView.onEscape = onEscape
    }
}

final class SessionListEscapeKeyMonitorView: NSView {
    var onEscape: (() -> Void)?

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

            let shouldRequestStop = SessionListEscapeKeyEvent.shouldRequestStop(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                isListFocused: isListFocused(in: window)
            )

            guard shouldRequestStop else { return event }
            onEscape?()
            return nil
        }
    }

    private func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func isListFocused(in window: NSWindow) -> Bool {
        guard let firstResponder = window.firstResponder as? NSView else { return false }

        if firstResponder is NSTableView || firstResponder is NSOutlineView {
            return true
        }

        return firstResponder.enclosingTableView != nil || firstResponder.enclosingOutlineView != nil
    }
}

private extension NSView {
    var enclosingTableView: NSTableView? {
        sequence(first: self as NSView?, next: { $0?.superview }).first { $0 is NSTableView } as? NSTableView
    }

    var enclosingOutlineView: NSOutlineView? {
        sequence(first: self as NSView?, next: { $0?.superview }).first { $0 is NSOutlineView } as? NSOutlineView
    }
}
