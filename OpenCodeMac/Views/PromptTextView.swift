import AppKit
import SwiftUI

struct PromptTextView: NSViewRepresentable {
    static let defaultHeight: CGFloat = 40

    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @Binding var highlightedSuggestionIndex: Int?
    let suggestions: [CommandOption]
    @Binding var suggestionAnchor: CGRect
    let placeholder: String
    let textColor: NSColor
    let insertionPointColor: NSColor
    let placeholderColor: NSColor
    let focusRequestID: UUID?
    let onSelectSuggestion: (CommandOption) -> Void
    let onFocus: () -> Void
    let onSubmit: () -> Void

    private let minLineCount = 2
    private let maxLineCount = 15
    private let textInsets = NSSize(width: 2, height: 4)

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            measuredHeight: $measuredHeight,
            highlightedSuggestionIndex: $highlightedSuggestionIndex,
            suggestionAnchor: $suggestionAnchor,
            minLineCount: minLineCount,
            maxLineCount: maxLineCount,
            textInsets: textInsets,
            suggestions: suggestions,
            placeholder: placeholder,
            textColor: textColor,
            insertionPointColor: insertionPointColor,
            placeholderColor: placeholderColor,
            focusRequestID: focusRequestID,
            onSelectSuggestion: onSelectSuggestion,
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
        textView.onHighlightedSuggestionChange = context.coordinator.updateHighlightedSuggestionIndex
        textView.placeholder = placeholder
        textView.onSelectSuggestion = context.coordinator.selectHighlightedSuggestion
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
        context.coordinator.installSuggestions(suggestions, for: textView)

        scrollView.documentView = textView
        context.coordinator.updateHeight(for: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PromptNSTextView else { return }
        textView.onFocus = context.coordinator.onFocus
        textView.onSubmit = onSubmit
        textView.onHighlightedSuggestionChange = context.coordinator.updateHighlightedSuggestionIndex
        textView.placeholder = placeholder
        textView.onSelectSuggestion = context.coordinator.selectHighlightedSuggestion
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
        textView.placeholderColor = placeholderColor
        if textView.string != text {
            context.coordinator.applyText(text, to: textView)
        }
        context.coordinator.installSuggestions(suggestions, for: textView)
        context.coordinator.applyFocusRequestIfNeeded(focusRequestID, to: textView)
        context.coordinator.updateHeight(for: nsView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var measuredHeight: CGFloat
        @Binding var highlightedSuggestionIndex: Int?
        @Binding var suggestionAnchor: CGRect
        let minLineCount: Int
        let maxLineCount: Int
        let textInsets: NSSize
        private var suggestions: [CommandOption]
        let placeholder: String
        let textColor: NSColor
        let insertionPointColor: NSColor
        let placeholderColor: NSColor
        private var lastAppliedFocusRequestID: UUID?
        private let onSelectSuggestion: (CommandOption) -> Void
        let onFocus: () -> Void
        let onSubmit: () -> Void

        init(
            text: Binding<String>,
            measuredHeight: Binding<CGFloat>,
            highlightedSuggestionIndex: Binding<Int?>,
            suggestionAnchor: Binding<CGRect>,
            minLineCount: Int,
            maxLineCount: Int,
            textInsets: NSSize,
            suggestions: [CommandOption],
            placeholder: String,
            textColor: NSColor,
            insertionPointColor: NSColor,
            placeholderColor: NSColor,
            focusRequestID: UUID?,
            onSelectSuggestion: @escaping (CommandOption) -> Void,
            onFocus: @escaping () -> Void,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _measuredHeight = measuredHeight
            _highlightedSuggestionIndex = highlightedSuggestionIndex
            _suggestionAnchor = suggestionAnchor
            self.minLineCount = minLineCount
            self.maxLineCount = maxLineCount
            self.textInsets = textInsets
            self.suggestions = suggestions
            self.placeholder = placeholder
            self.textColor = textColor
            self.insertionPointColor = insertionPointColor
            self.placeholderColor = placeholderColor
            lastAppliedFocusRequestID = nil
            self.onSelectSuggestion = onSelectSuggestion
            self.onFocus = onFocus
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            guard let scrollView = textView.enclosingScrollView else { return }
            updateHeight(for: scrollView)
        }

        func installSuggestions(_ suggestions: [CommandOption], for textView: PromptNSTextView) {
            self.suggestions = suggestions
            textView.suggestions = suggestions
            textView.highlightedSuggestionIndex = highlightedSuggestionIndex ?? (suggestions.isEmpty ? nil : 0)
            updateSuggestionAnchor(for: textView)
        }

        func updateHighlightedSuggestionIndex(_ index: Int?) {
            highlightedSuggestionIndex = index
        }

        func selectHighlightedSuggestion() {
            guard let textView = NSApp.keyWindow?.firstResponder as? PromptNSTextView,
                  textView.isSelectingSuggestion,
                  let option = textView.highlightedSuggestion else { return }
            onSelectSuggestion(option)
            textView.highlightedSuggestionIndex = 0
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

            if let promptTextView = textView as? PromptNSTextView {
                updateSuggestionAnchor(for: promptTextView)
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

        private func updateSuggestionAnchor(for textView: PromptNSTextView) {
            guard let window = textView.window else {
                suggestionAnchor = .zero
                return
            }

            let boundsInWindow = textView.convert(textView.bounds, to: nil)
            let boundsOnScreen = window.convertToScreen(boundsInWindow)
            suggestionAnchor = boundsOnScreen
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
    var onSelectSuggestion: (() -> Void)?
    var onHighlightedSuggestionChange: ((Int?) -> Void)?
    var placeholderColor: NSColor = .placeholderTextColor
    var suggestions: [CommandOption] = [] {
        didSet {
            if let currentIndex = highlightedSuggestionIndex, currentIndex >= suggestions.count {
                self.highlightedSuggestionIndex = suggestions.isEmpty ? nil : 0
            } else if highlightedSuggestionIndex == nil, !suggestions.isEmpty {
                highlightedSuggestionIndex = 0
            }
        }
    }
    var highlightedSuggestionIndex: Int? {
        didSet {
            onHighlightedSuggestionChange?(highlightedSuggestionIndex)
        }
    }

    var highlightedSuggestion: CommandOption? {
        guard let highlightedSuggestionIndex, suggestions.indices.contains(highlightedSuggestionIndex) else { return nil }
        return suggestions[highlightedSuggestionIndex]
    }

    var isSelectingSuggestion: Bool {
        highlightedSuggestionIndex != nil && !suggestions.isEmpty
    }
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

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            highlightedSuggestionIndex = suggestions.isEmpty ? nil : 0
        }
        return didResign
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

        if suggestions.isEmpty == false {
            switch event.keyCode {
            case 125:
                moveSuggestionSelection(offset: 1)
                return
            case 126:
                moveSuggestionSelection(offset: -1)
                return
            case 36, 76:
                onSelectSuggestion?()
                return
            case 48:
                onSelectSuggestion?()
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

    private func moveSuggestionSelection(offset: Int) {
        guard !suggestions.isEmpty else { return }
        let currentIndex = highlightedSuggestionIndex ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), suggestions.count - 1)
        highlightedSuggestionIndex = nextIndex
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
