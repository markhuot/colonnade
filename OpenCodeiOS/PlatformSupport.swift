#if canImport(UIKit)
import SwiftUI
import UIKit

private let iosPromptEditorMinimumHeight: CGFloat = 44
private let iosPromptEditorMaximumHeight: CGFloat = 220

enum PlatformModifierKeyState {
    static func shouldUpdateDefaultModel() -> Bool {
        false
    }
}

struct SelectableToolTextView: View {
    let text: String
    let textColor: UIColor

    var idealHeight: CGFloat {
        let lineCount = max(text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return min(max(CGFloat(lineCount) * 18 + 12, 30), 110)
    }

    var body: some View {
        ScrollView(.horizontal) {
            Text(verbatim: text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(uiColor: textColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.vertical, 6)
        }
    }
}

struct IOSPromptTextEditor<AccessoryContent: View>: UIViewRepresentable {
    typealias UIViewType = AccessoryHostingTextView

    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat
    @Binding var highlightedSuggestionIndex: Int?

    let focusRequestID: UUID?
    let textColor: UIColor
    let placeholderColor: UIColor
    let suggestions: [CommandOption]
    let allowsNewlines: Bool
    @ViewBuilder let accessoryContent: () -> AccessoryContent
    let onSelectSuggestion: (CommandOption) -> Void
    let onFocus: () -> Void
    let onSubmit: () -> Void
    let onKeyboardDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> AccessoryHostingTextView {
        let textView = AccessoryHostingTextView()
        textView.delegate = context.coordinator
        textView.onHighlightedSuggestionChange = { index in
            context.coordinator.parent.highlightedSuggestionIndex = index
        }
        textView.backgroundColor = .clear
        textView.textColor = textColor
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.returnKeyType = allowsNewlines ? .default : .send
        textView.enablesReturnKeyAutomatically = !allowsNewlines
        textView.allowsNewlines = allowsNewlines
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.layer.cornerRadius = 14
        textView.layer.masksToBounds = true
        textView.isScrollEnabled = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let placeholderLabel = UILabel()
        placeholderLabel.text = "Message"
        placeholderLabel.textColor = placeholderColor
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -16)
        ])
        context.coordinator.placeholderLabel = placeholderLabel
        context.coordinator.installKeyboardDismissGesture(on: textView)

        updateAccessory(for: textView, context: context)
        updateTextView(textView, context: context)
        context.coordinator.installSuggestions(suggestions, on: textView)
        updateMeasuredHeight(for: textView)
        return textView
    }

    func updateUIView(_ textView: AccessoryHostingTextView, context: Context) {
        context.coordinator.parent = self
        updateTextView(textView, context: context)
        updateAccessory(for: textView, context: context)
        textView.allowsNewlines = allowsNewlines
        textView.returnKeyType = allowsNewlines ? .default : .send
        textView.enablesReturnKeyAutomatically = !allowsNewlines
        context.coordinator.installSuggestions(suggestions, on: textView)
        updateMeasuredHeight(for: textView)

        if isFocused, !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        } else if !isFocused, textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.resignFirstResponder()
            }
        }
    }

    private func updateTextView(_ textView: AccessoryHostingTextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        textView.textColor = textColor
        textView.onHighlightedSuggestionChange = { index in
            context.coordinator.parent.highlightedSuggestionIndex = index
        }
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        textView.highlightedSuggestionIndex = highlightedSuggestionIndex

        if context.coordinator.lastAppliedFocusRequestID != focusRequestID, focusRequestID != nil {
            context.coordinator.lastAppliedFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    private func updateAccessory(for textView: AccessoryHostingTextView, context: Context) {
        let host = context.coordinator.accessoryHostController ?? UIHostingController(rootView: AnyView(accessoryContent()))
        host.rootView = AnyView(accessoryContent())
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.invalidateIntrinsicContentSize()
        context.coordinator.accessoryHostController = host

        let container = context.coordinator.accessoryContainerView ?? AccessoryInputContainerView()
        container.hostedContentView = host.view
        context.coordinator.accessoryContainerView = container
        textView.hostedAccessoryView = container
    }

    private func updateMeasuredHeight(for textView: UITextView) {
        let targetSize = CGSize(width: max(textView.bounds.width, 1), height: CGFloat.greatestFiniteMagnitude)
        let measuredContentHeight = ceil(textView.sizeThatFits(targetSize).height)
        let shouldScroll = measuredContentHeight > iosPromptEditorMaximumHeight
        if textView.isScrollEnabled != shouldScroll {
            textView.isScrollEnabled = shouldScroll
        }
        let height = min(max(iosPromptEditorMinimumHeight, measuredContentHeight), iosPromptEditorMaximumHeight)
        DispatchQueue.main.async {
            if abs(measuredHeight - height) > 0.5 {
                measuredHeight = height
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: IOSPromptTextEditor
        weak var placeholderLabel: UILabel?
        var accessoryHostController: UIHostingController<AnyView>?
        var accessoryContainerView: AccessoryInputContainerView?
        var lastAppliedFocusRequestID: UUID?

        init(_ parent: IOSPromptTextEditor) {
            self.parent = parent
        }

        func installKeyboardDismissGesture(on textView: UITextView) {
            let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleKeyboardDismissPan(_:)))
            gestureRecognizer.delegate = self
            gestureRecognizer.cancelsTouchesInView = false
            textView.addGestureRecognizer(gestureRecognizer)
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            placeholderLabel?.isHidden = !textView.text.isEmpty
            parent.updateMeasuredHeight(for: textView)
        }

        func installSuggestions(_ suggestions: [CommandOption], on textView: AccessoryHostingTextView) {
            let previousSuggestionIDs = textView.suggestions.map(\.id)
            let suggestionIDs = suggestions.map(\.id)
            textView.suggestions = suggestions

            let shouldResetSelection = suggestions.isEmpty
                || previousSuggestionIDs != suggestionIDs
                || textView.highlightedSuggestionIndex == nil
                || (textView.highlightedSuggestionIndex.map { !suggestions.indices.contains($0) } ?? false)

            if shouldResetSelection {
                textView.highlightedSuggestionIndex = suggestions.isEmpty ? nil : 0
            } else {
                textView.highlightedSuggestionIndex = parent.highlightedSuggestionIndex
            }

            parent.highlightedSuggestionIndex = textView.highlightedSuggestionIndex
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
            parent.onFocus()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let textView = textView as? AccessoryHostingTextView else { return }
            parent.highlightedSuggestionIndex = textView.highlightedSuggestionIndex
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard let textView = textView as? AccessoryHostingTextView else {
                if replacement == "\n" {
                    parent.onSubmit()
                    return false
                }
                return true
            }

            if replacement == "\n" {
                if let option = textView.highlightedSuggestion {
                    parent.onSelectSuggestion(option)
                    textView.highlightedSuggestionIndex = 0
                    parent.highlightedSuggestionIndex = 0
                    return false
                }

                guard !parent.allowsNewlines else {
                    return true
                }

                parent.onSubmit()
                return false
            }

            if replacement == "\t", let option = textView.highlightedSuggestion {
                parent.onSelectSuggestion(option)
                textView.highlightedSuggestionIndex = 0
                parent.highlightedSuggestionIndex = 0
                return false
            }

            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
                  let textView = panGestureRecognizer.view as? UITextView,
                  textView.isFirstResponder
            else {
                return false
            }

            let translation = panGestureRecognizer.translation(in: textView)
            return translation.y > 0 && abs(translation.y) > abs(translation.x)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc
        private func handleKeyboardDismissPan(_ gestureRecognizer: UIPanGestureRecognizer) {
            guard gestureRecognizer.state == .changed || gestureRecognizer.state == .ended,
                  let textView = gestureRecognizer.view as? UITextView,
                  textView.isFirstResponder
            else {
                return
            }

            let translation = gestureRecognizer.translation(in: textView)
            guard translation.y >= 24,
                  translation.y > abs(translation.x)
            else {
                return
            }

            textView.resignFirstResponder()
            parent.onKeyboardDismiss()
        }
    }
}

final class AccessoryHostingTextView: UITextView {
    private var accessoryStorage: UIView?
    var allowsNewlines = true
    var suggestions: [CommandOption] = []
    var onHighlightedSuggestionChange: ((Int?) -> Void)?
    var highlightedSuggestionIndex: Int? {
        didSet {
            guard highlightedSuggestionIndex != oldValue else { return }
            onHighlightedSuggestionChange?(highlightedSuggestionIndex)
            if isFirstResponder {
                reloadInputViews()
            }
        }
    }

    var highlightedSuggestion: CommandOption? {
        guard let highlightedSuggestionIndex, suggestions.indices.contains(highlightedSuggestionIndex) else { return nil }
        return suggestions[highlightedSuggestionIndex]
    }

    var hostedAccessoryView: UIView? {
        get { accessoryStorage }
        set {
            if accessoryStorage !== newValue {
                accessoryStorage = newValue
                reloadInputViews()
            }
        }
    }

    override var inputAccessoryView: UIView? {
        get { accessoryStorage }
        set { accessoryStorage = newValue }
    }

    override var keyCommands: [UIKeyCommand]? {
        guard !suggestions.isEmpty else { return super.keyCommands }

        return [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(selectPreviousSuggestion)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(selectNextSuggestion))
        ]
    }

    @objc
    private func selectPreviousSuggestion() {
        moveSuggestionSelection(offset: -1)
    }

    @objc
    private func selectNextSuggestion() {
        moveSuggestionSelection(offset: 1)
    }

    private func moveSuggestionSelection(offset: Int) {
        guard !suggestions.isEmpty else { return }
        let currentIndex = highlightedSuggestionIndex ?? 0
        highlightedSuggestionIndex = min(max(currentIndex + offset, 0), suggestions.count - 1)
    }
}

final class AccessoryInputContainerView: UIView {
    private var installedConstraints: [NSLayoutConstraint] = []

    var hostedContentView: UIView? {
        didSet {
            guard oldValue !== hostedContentView else { return }

            oldValue?.removeFromSuperview()
            installedConstraints.removeAll()

            guard let hostedContentView else {
                invalidateIntrinsicContentSize()
                return
            }

            addSubview(hostedContentView)
            installedConstraints = [
                hostedContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostedContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostedContentView.topAnchor.constraint(equalTo: topAnchor),
                hostedContentView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
            ]
            NSLayoutConstraint.activate(installedConstraints)
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        autoresizingMask = [.flexibleHeight]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        guard let hostedContentView else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }

        let fittingSize = hostedContentView.systemLayoutSizeFitting(
            CGSize(width: UIScreen.main.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        return CGSize(width: UIView.noIntrinsicMetric, height: fittingSize.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let hostedContentView else { return CGSize(width: size.width, height: 0) }

        let fittingSize = hostedContentView.systemLayoutSizeFitting(
            CGSize(width: size.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        return CGSize(width: size.width, height: fittingSize.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedContentView?.frame = bounds
    }
}
#endif
