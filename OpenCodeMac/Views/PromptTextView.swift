import AppKit
import SwiftUI

struct PromptTextView: NSViewRepresentable {
    static let defaultHeight: CGFloat = 40

    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let placeholder: String
    let textColor: NSColor
    let insertionPointColor: NSColor
    let placeholderColor: NSColor
    let focusRequestID: UUID?
    let onFocus: () -> Void
    let onSubmit: () -> Void

    private let minLineCount = 2
    private let maxLineCount = 15
    private let textInsets = NSSize(width: 2, height: 4)

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            minLineCount: minLineCount,
            maxLineCount: maxLineCount,
            textInsets: textInsets,
            placeholder: placeholder,
            textColor: textColor,
            insertionPointColor: insertionPointColor,
            placeholderColor: placeholderColor,
            focusRequestID: focusRequestID,
            onFocus: onFocus,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PromptScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let coordinator, let scrollView else { return }
            coordinator.updateHeight(for: scrollView)
        }

        let textView = PromptNSTextView()
        textView.delegate = context.coordinator
        textView.onFocus = context.coordinator.onFocus
        textView.onSubmit = onSubmit
        textView.placeholder = placeholder
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
        textView.placeholderColor = placeholderColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = textInsets
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.updateHeight(for: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PromptNSTextView else { return }
        textView.onFocus = context.coordinator.onFocus
        textView.onSubmit = onSubmit
        textView.placeholder = placeholder
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
        textView.placeholderColor = placeholderColor
        if textView.string != text {
            context.coordinator.applyText(text, to: textView)
        }
        context.coordinator.applyFocusRequestIfNeeded(focusRequestID, to: textView)
        context.coordinator.updateHeight(for: nsView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var measuredHeight: CGFloat
        let minLineCount: Int
        let maxLineCount: Int
        let textInsets: NSSize
        let placeholder: String
        let textColor: NSColor
        let insertionPointColor: NSColor
        let placeholderColor: NSColor
        private var lastAppliedFocusRequestID: UUID?
        let onFocus: () -> Void
        let onSubmit: () -> Void

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            minLineCount: Int,
            maxLineCount: Int,
            textInsets: NSSize,
            placeholder: String,
            textColor: NSColor,
            insertionPointColor: NSColor,
            placeholderColor: NSColor,
            focusRequestID: UUID?,
            onFocus: @escaping () -> Void,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _measuredHeight = measuredHeight
            self.minLineCount = minLineCount
            self.maxLineCount = maxLineCount
            self.textInsets = textInsets
            self.placeholder = placeholder
            self.textColor = textColor
            self.insertionPointColor = insertionPointColor
            self.placeholderColor = placeholderColor
            lastAppliedFocusRequestID = nil
            self.onFocus = onFocus
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            guard let scrollView = textView.enclosingScrollView else { return }
            updateHeight(for: scrollView)
        }

        func updateHeight(for scrollView: NSScrollView) {
            guard let textView = scrollView.documentView as? NSTextView else { return }

            let targetHeight = Self.height(
                for: textView,
                minLineCount: minLineCount,
                maxLineCount: maxLineCount,
                textInsets: textInsets
            )

            if abs(measuredHeight - targetHeight) > 0.5 {
                measuredHeight = targetHeight
            }

            let shouldScroll = targetHeight >= Self.maximumHeight(
                for: textView,
                maxLineCount: maxLineCount,
                textInsets: textInsets
            )
            if scrollView.hasVerticalScroller != shouldScroll {
                scrollView.hasVerticalScroller = shouldScroll
            }
        }

        func applyText(_ newValue: String, to textView: NSTextView) {
            textView.string = newValue
            textView.setSelectedRange(NSRange(location: newValue.utf16.count, length: 0))
            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.needsDisplay = true

            if let scrollView = textView.enclosingScrollView {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                updateHeight(for: scrollView)
            }
        }

        func applyFocusRequestIfNeeded(_ focusRequestID: UUID?, to textView: NSTextView) {
            guard let focusRequestID, focusRequestID != lastAppliedFocusRequestID else { return }
            lastAppliedFocusRequestID = focusRequestID

            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        private static func height(
            for textView: NSTextView,
            minLineCount: Int,
            maxLineCount: Int,
            textInsets: NSSize
        ) -> CGFloat {
            let contentHeight = contentHeight(for: textView, textInsets: textInsets)
            let minimumHeight = minimumHeight(for: textView, lineCount: minLineCount, textInsets: textInsets)
            let maximumHeight = maximumHeight(for: textView, maxLineCount: maxLineCount, textInsets: textInsets)
            return min(max(contentHeight, minimumHeight), maximumHeight)
        }

        private static func minimumHeight(for textView: NSTextView, lineCount: Int, textInsets: NSSize) -> CGFloat {
            lineHeight(for: textView) * CGFloat(lineCount) + textInsets.height * 2
        }

        private static func maximumHeight(for textView: NSTextView, maxLineCount: Int, textInsets: NSSize) -> CGFloat {
            lineHeight(for: textView) * CGFloat(maxLineCount) + textInsets.height * 2
        }

        private static func contentHeight(for textView: NSTextView, textInsets: NSSize) -> CGFloat {
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
                return minimumHeight(for: textView, lineCount: 2, textInsets: textInsets)
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            return ceil(usedRect.height) + textInsets.height * 2
        }

        private static func lineHeight(for textView: NSTextView) -> CGFloat {
            let font = textView.font ?? .preferredFont(forTextStyle: .body)
            let layoutManager = textView.layoutManager ?? NSLayoutManager()
            return ceil(layoutManager.defaultLineHeight(for: font))
        }
    }
}

final class PromptScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class PromptNSTextView: NSTextView {
    var onFocus: (() -> Void)?
    var onSubmit: (() -> Void)?
    var placeholderColor: NSColor = .placeholderTextColor
    var placeholder = "" {
        didSet {
            needsDisplay = true
        }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocus?()
        }
        return didBecomeFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let insertsNewline = modifiers.contains(.shift) || modifiers.contains(.option)

        if modifiers == [.control], let character = event.charactersIgnoringModifiers?.lowercased() {
            switch character {
            case "a":
                moveToBeginningOfLine(self)
                return
            case "e":
                moveToEndOfLine(self)
                return
            case "c":
                string = ""
                setSelectedRange(NSRange(location: 0, length: 0))
                didChangeText()
                return
            default:
                break
            }
        }

        if isReturn && !insertsNewline {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }

        let font = font ?? .preferredFont(forTextStyle: .body)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: placeholderColor
        ]

        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholder.draw(at: origin, withAttributes: attributes)
    }
}
