import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SelectableMessageTextView: View {
    let attributedText: NSAttributedString
    let linkColor: PlatformColor
    var onInteraction: (() -> Void)? = nil

    @State private var measuredHeight: CGFloat = 1

    var body: some View {
        PlatformSelectableMessageTextView(
            attributedText: attributedText,
            linkColor: linkColor,
            measuredHeight: $measuredHeight,
            onInteraction: onInteraction
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: measuredHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if os(macOS)
private final class MessageTextView: NSTextView {
    var onInteraction: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        super.mouseDown(with: event)
    }
}

private struct PlatformSelectableMessageTextView: NSViewRepresentable {
    final class Coordinator {
        var lastAppliedString = ""
        var lastAppliedLength = 0
        var lastAppliedWidth: CGFloat = 0
        var lastMeasuredHeight: CGFloat = 1
    }

    let attributedText: NSAttributedString
    let linkColor: NSColor
    @Binding var measuredHeight: CGFloat
    let onInteraction: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = MessageTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.onInteraction = onInteraction
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MessageTextView else { return }
        let coordinator = context.coordinator

        let rawWidth = scrollView.contentSize.width
        let width = max(rawWidth, 1)
        let string = attributedText.string
        let textLength = attributedText.length
        let widthChanged = abs(coordinator.lastAppliedWidth - width) > 0.5
        let textChanged = coordinator.lastAppliedLength != textLength || coordinator.lastAppliedString != string

        if rawWidth <= 1 {
            return
        }

        if !textChanged, !widthChanged {
            return
        }

        textView.minSize = NSSize(width: width, height: 1)
        textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.frame.size.width = width
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.onInteraction = onInteraction

        if textChanged {
            textView.textStorage?.setAttributedString(attributedText)
        }

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = ceil(usedRect.height)
        textView.frame.size.height = height

        coordinator.lastAppliedString = string
        coordinator.lastAppliedLength = textLength
        coordinator.lastAppliedWidth = width
        coordinator.lastMeasuredHeight = height

        DispatchQueue.main.async {
            if abs(measuredHeight - height) > 0.5 {
                measuredHeight = max(height, 1)
            }
        }
    }
}
#else
private struct PlatformSelectableMessageTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let linkColor: UIColor
    @Binding var measuredHeight: CGFloat
    let onInteraction: (() -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero)
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.dataDetectorTypes = []
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = attributedText
        textView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let width = max(textView.bounds.width, 1)
        let fittingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let height = ceil(textView.sizeThatFits(fittingSize).height)
        DispatchQueue.main.async {
            if abs(measuredHeight - height) > 0.5 {
                measuredHeight = max(height, 1)
            }
        }
    }
}
#endif
