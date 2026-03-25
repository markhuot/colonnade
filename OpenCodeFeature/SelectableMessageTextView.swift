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

    @State private var measuredHeight: CGFloat = 1

    var body: some View {
        PlatformSelectableMessageTextView(
            attributedText: attributedText,
            linkColor: linkColor,
            measuredHeight: $measuredHeight
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: measuredHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if os(macOS)
private final class InstrumentedMessageScrollView: NSScrollView {
    var instanceID = ""

    private var lastLoggedStateByEvent: [String: String] = [:]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        logState(event: "scroll-viewDidMoveToWindow", includeAncestors: true)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        logState(event: "scroll-viewDidMoveToSuperview", includeAncestors: true)
    }

    override func layout() {
        super.layout()
        logState(event: "scroll-layout")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        logState(event: "scroll-setFrameSize")
    }

    override func tile() {
        super.tile()
        logState(event: "scroll-tile")
    }

    private func logState(event: String, includeAncestors: Bool = false) {
        let state = scrollGeometryDescription(includeAncestors: includeAncestors)
        guard lastLoggedStateByEvent[event] != state else { return }
        lastLoggedStateByEvent[event] = state
        PerformanceInstrumentation.log("mac-message-text-view-state id=\(instanceID) event=\(event) \(state)")
    }

    fileprivate func scrollGeometryDescription(includeAncestors: Bool = false) -> String {
        let clipView = contentView
        let documentWidth = documentView?.frame.width ?? 0
        let superviewWidth = superview?.bounds.width ?? 0
        let windowWidth = window?.contentLayoutRect.width ?? 0
        let windowVisible = window?.occlusionState.contains(.visible) ?? false
        let ancestorSummary = includeAncestors ? " ancestors=\(ancestorTypeSummary())" : ""
        return [
            "contentWidth=\(formatted(contentSize.width))",
            "frameWidth=\(formatted(frame.width))",
            "boundsWidth=\(formatted(bounds.width))",
            "visibleRectWidth=\(formatted(visibleRect.width))",
            "clipWidth=\(formatted(clipView.bounds.width))",
            "docVisibleWidth=\(formatted(clipView.documentVisibleRect.width))",
            "documentWidth=\(formatted(documentWidth))",
            "superviewWidth=\(formatted(superviewWidth))",
            "windowWidth=\(formatted(windowWidth))",
            "hasWindow=\(window != nil)",
            "windowVisible=\(windowVisible)",
            "hidden=\(isHiddenOrHasHiddenAncestor)",
            "firstResponder=\(window?.firstResponder === documentView)",
            "scrollAmbiguous=\(hasAmbiguousLayout)"
        ].joined(separator: " ") + ancestorSummary
    }

    private func ancestorTypeSummary() -> String {
        sequence(first: superview, next: { $0?.superview })
            .prefix(5)
            .map { String(describing: type(of: $0)) }
            .joined(separator: ">")
    }

    private func formatted(_ value: CGFloat) -> String {
        formatGeometryValue(value)
    }
}

private final class InstrumentedMessageTextView: NSTextView {
    var instanceID = ""

    private var lastLoggedStateByEvent: [String: String] = [:]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        logState(event: "text-viewDidMoveToWindow", includeAncestors: true)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        logState(event: "text-viewDidMoveToSuperview", includeAncestors: true)
    }

    override func layout() {
        super.layout()
        logState(event: "text-layout")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        logState(event: "text-setFrameSize")
    }

    private func logState(event: String, includeAncestors: Bool = false) {
        let state = textGeometryDescription(includeAncestors: includeAncestors)
        guard lastLoggedStateByEvent[event] != state else { return }
        lastLoggedStateByEvent[event] = state
        PerformanceInstrumentation.log("mac-message-text-view-state id=\(instanceID) event=\(event) \(state)")
    }

    fileprivate func textGeometryDescription(includeAncestors: Bool = false) -> String {
        let containerWidth = textContainer?.containerSize.width ?? 0
        let enclosingScrollWidth = enclosingScrollView?.contentSize.width ?? 0
        let windowVisible = window?.occlusionState.contains(.visible) ?? false
        let ancestorSummary = includeAncestors ? " ancestors=\(ancestorTypeSummary())" : ""
        return [
            "frameWidth=\(formatted(frame.width))",
            "boundsWidth=\(formatted(bounds.width))",
            "visibleRectWidth=\(formatted(visibleRect.width))",
            "containerWidth=\(formatted(containerWidth))",
            "enclosingScrollWidth=\(formatted(enclosingScrollWidth))",
            "hasWindow=\(window != nil)",
            "windowVisible=\(windowVisible)",
            "hidden=\(isHiddenOrHasHiddenAncestor)",
            "textAmbiguous=\(hasAmbiguousLayout)"
        ].joined(separator: " ") + ancestorSummary
    }

    private func ancestorTypeSummary() -> String {
        sequence(first: superview, next: { $0?.superview })
            .prefix(5)
            .map { String(describing: type(of: $0)) }
            .joined(separator: ">")
    }

    private func formatted(_ value: CGFloat) -> String {
        formatGeometryValue(value)
    }
}

private struct PlatformSelectableMessageTextView: NSViewRepresentable {
    final class Coordinator {
        let instanceID = "msgtext-\(UUID().uuidString)"
        var lastAppliedString = ""
        var lastAppliedLength = 0
        var lastAppliedWidth: CGFloat = 0
        var lastMeasuredHeight: CGFloat = 1
        var updateCount = 0
        var skippedNoopUpdates = 0
        var lastSmallWidthLogSignature = ""
        var lastOffscreenUpdateSignature = ""
        var lastWidthStableLogWidth: CGFloat = 0
    }

    let attributedText: NSAttributedString
    let linkColor: NSColor
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let scrollView = InstrumentedMessageScrollView(frame: .zero)
        scrollView.instanceID = coordinator.instanceID
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = InstrumentedMessageTextView(frame: .zero)
        textView.instanceID = coordinator.instanceID
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
        scrollView.documentView = textView
        PerformanceInstrumentation.log(
            "mac-message-text-make-view id=\(coordinator.instanceID) initialBytes=\(attributedText.string.utf8.count)"
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.updateCount += 1

        let rawWidth = scrollView.contentSize.width
        let width = max(rawWidth, 1)
        let string = attributedText.string
        let textBytes = string.utf8.count
        let textLength = attributedText.length
        let widthChanged = abs(coordinator.lastAppliedWidth - width) > 0.5
        let textChanged = coordinator.lastAppliedLength != textLength || coordinator.lastAppliedString != string
        let isWindowVisible = scrollView.window?.occlusionState.contains(.visible) ?? false
        let isOffscreen = scrollView.window == nil
            || !isWindowVisible
            || scrollView.isHiddenOrHasHiddenAncestor
            || scrollView.visibleRect.isEmpty
            || scrollView.contentView.documentVisibleRect.isEmpty

        if textChanged || widthChanged {
            let offscreenSignature = [
                "offscreen=\(isOffscreen)",
                "hasWindow=\(scrollView.window != nil)",
                "windowVisible=\(isWindowVisible)",
                "hidden=\(scrollView.isHiddenOrHasHiddenAncestor)",
                "visibleRectWidth=\(formatGeometryValue(scrollView.visibleRect.width))",
                "docVisibleWidth=\(formatGeometryValue(scrollView.contentView.documentVisibleRect.width))",
                "textFrameWidth=\(formatGeometryValue(textView.frame.width))",
                "contentWidth=\(formatGeometryValue(scrollView.contentSize.width))"
            ].joined(separator: " ")
            if offscreenSignature != coordinator.lastOffscreenUpdateSignature {
                coordinator.lastOffscreenUpdateSignature = offscreenSignature
                PerformanceInstrumentation.log(
                    "mac-message-text-update-context id=\(coordinator.instanceID) updates=\(coordinator.updateCount) bytes=\(textBytes) textChanged=\(textChanged) widthChanged=\(widthChanged) \(offscreenSignature)"
                )
            }
        }

        if rawWidth <= 1 {
            let signature = smallWidthSignature(scrollView: scrollView, textView: textView)
            if signature != coordinator.lastSmallWidthLogSignature {
                coordinator.lastSmallWidthLogSignature = signature
                PerformanceInstrumentation.log(
                    "mac-message-text-width-too-small id=\(coordinator.instanceID) updates=\(coordinator.updateCount) bytes=\(textBytes) textChanged=\(textChanged) widthChanged=\(widthChanged) details=\(signature)"
                )
            }
            return
        }

        if coordinator.lastAppliedWidth <= 1, width > 1 {
            PerformanceInstrumentation.log(
                "mac-message-text-width-recovered id=\(coordinator.instanceID) updates=\(coordinator.updateCount) bytes=\(textBytes) width=\(formatGeometryValue(width)) previousWidth=\(formatGeometryValue(coordinator.lastAppliedWidth)) details=\(smallWidthSignature(scrollView: scrollView, textView: textView))"
            )
        }

        if coordinator.lastAppliedWidth > 1, width > 1, abs(coordinator.lastAppliedWidth - width) > 0.5 {
            PerformanceInstrumentation.log(
                "mac-message-text-width-changed-after-stable id=\(coordinator.instanceID) updates=\(coordinator.updateCount) bytes=\(textBytes) oldWidth=\(formatGeometryValue(coordinator.lastAppliedWidth)) newWidth=\(formatGeometryValue(width)) details=\(smallWidthSignature(scrollView: scrollView, textView: textView))"
            )
        }

        if width > 1, abs(coordinator.lastWidthStableLogWidth - width) > 0.5 {
            coordinator.lastWidthStableLogWidth = width
            PerformanceInstrumentation.log(
                "mac-message-text-width-stable-snapshot id=\(coordinator.instanceID) updates=\(coordinator.updateCount) bytes=\(textBytes) width=\(formatGeometryValue(width)) viewFrame=\(formatGeometryValue(scrollView.frame.width)) docVisible=\(formatGeometryValue(scrollView.contentView.documentVisibleRect.width)) textFrame=\(formatGeometryValue(textView.frame.width))"
            )
        }

        coordinator.lastSmallWidthLogSignature = ""

        if !textChanged, !widthChanged {
            coordinator.skippedNoopUpdates += 1
            if coordinator.skippedNoopUpdates == 1 || coordinator.skippedNoopUpdates.isMultiple(of: 25) {
                PerformanceInstrumentation.log(
                    "mac-message-text-skip-noop id=\(coordinator.instanceID) updates=\(coordinator.updateCount) skips=\(coordinator.skippedNoopUpdates) bytes=\(textBytes) width=\(formatGeometryValue(width)) height=\(formatGeometryValue(coordinator.lastMeasuredHeight))"
                )
            }
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

        if textChanged {
            coordinator.skippedNoopUpdates = 0
            let setAttributedTextStart = PerformanceInstrumentation.begin(
                "mac-message-text-set-attributed",
                details: "id=\(coordinator.instanceID) bytes=\(textBytes) length=\(textLength) width=\(formatGeometryValue(width)) offscreen=\(isOffscreen) reason=textChanged"
            )
            textView.textStorage?.setAttributedString(attributedText)
            PerformanceInstrumentation.end(
                "mac-message-text-set-attributed",
                from: setAttributedTextStart,
                details: "id=\(coordinator.instanceID) bytes=\(textBytes) length=\(textLength) width=\(formatGeometryValue(width)) offscreen=\(isOffscreen) reason=textChanged",
                thresholdMS: 1
            )
        }

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        let layoutStart = PerformanceInstrumentation.begin(
            "mac-message-text-layout",
            details: "id=\(coordinator.instanceID) bytes=\(textBytes) length=\(textLength) width=\(formatGeometryValue(width)) offscreen=\(isOffscreen) reason=\(textChanged ? "textChanged" : "widthChanged")"
        )
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = ceil(usedRect.height)
        textView.frame.size.height = height
        PerformanceInstrumentation.end(
            "mac-message-text-layout",
            from: layoutStart,
            details: "id=\(coordinator.instanceID) bytes=\(textBytes) length=\(textLength) width=\(formatGeometryValue(width)) height=\(formatGeometryValue(height)) offscreen=\(isOffscreen) reason=\(textChanged ? "textChanged" : "widthChanged")",
            thresholdMS: 1
        )

        coordinator.lastAppliedString = string
        coordinator.lastAppliedLength = textLength
        coordinator.lastAppliedWidth = width
        coordinator.lastMeasuredHeight = height

        DispatchQueue.main.async {
            if abs(measuredHeight - height) > 0.5 {
                PerformanceInstrumentation.log(
                    "mac-message-text-height-change id=\(coordinator.instanceID) bytes=\(textBytes) oldHeight=\(formatGeometryValue(measuredHeight)) newHeight=\(formatGeometryValue(height)) width=\(formatGeometryValue(width)) offscreen=\(isOffscreen)"
                )
                measuredHeight = max(height, 1)
            }
        }
    }

    private func smallWidthSignature(scrollView: NSScrollView, textView: NSTextView) -> String {
        let scrollDetails: String
        if let instrumentedScrollView = scrollView as? InstrumentedMessageScrollView {
            scrollDetails = instrumentedScrollView.scrollGeometryDescription(includeAncestors: true)
        } else {
            scrollDetails = "contentWidth=\(formatGeometryValue(scrollView.contentSize.width)) hasWindow=\(scrollView.window != nil)"
        }

        let textDetails: String
        if let instrumentedTextView = textView as? InstrumentedMessageTextView {
            textDetails = instrumentedTextView.textGeometryDescription(includeAncestors: true)
        } else {
            textDetails = "textFrameWidth=\(formatGeometryValue(textView.frame.width)) textAmbiguous=\(textView.hasAmbiguousLayout)"
        }

        return "scroll{\(scrollDetails)} text{\(textDetails)}"
    }
}

private func formatGeometryValue(_ value: CGFloat) -> String {
    guard value.isFinite else {
        return value.isNaN ? "nan" : (value.sign == .minus ? "-inf" : "inf")
    }

    let clamped = max(min(Double(value), 999_999), -999_999)
    return String(Int(clamped.rounded()))
}
#else
private struct PlatformSelectableMessageTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let linkColor: UIColor
    @Binding var measuredHeight: CGFloat

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
        let setAttributedTextStart = PerformanceInstrumentation.begin(
            "ios-message-text-set-attributed",
            details: "bytes=\(attributedText.string.utf8.count) length=\(attributedText.length) width=\(Int(textView.bounds.width))"
        )
        textView.attributedText = attributedText
        PerformanceInstrumentation.end(
            "ios-message-text-set-attributed",
            from: setAttributedTextStart,
            details: "bytes=\(attributedText.string.utf8.count) length=\(attributedText.length) width=\(Int(textView.bounds.width))",
            thresholdMS: 1
        )
        textView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let width = max(textView.bounds.width, 1)
        let fittingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let sizeThatFitsStart = PerformanceInstrumentation.begin(
            "ios-message-text-size-that-fits",
            details: "bytes=\(attributedText.string.utf8.count) length=\(attributedText.length) width=\(Int(width))"
        )
        let height = ceil(textView.sizeThatFits(fittingSize).height)
        PerformanceInstrumentation.end(
            "ios-message-text-size-that-fits",
            from: sizeThatFitsStart,
            details: "bytes=\(attributedText.string.utf8.count) length=\(attributedText.length) width=\(Int(width)) height=\(Int(height))",
            thresholdMS: 1
        )
        DispatchQueue.main.async {
            if abs(measuredHeight - height) > 0.5 {
                PerformanceInstrumentation.log(
                    "ios-message-text-height-change bytes=\(attributedText.string.utf8.count) oldHeight=\(Int(measuredHeight)) newHeight=\(Int(height)) width=\(Int(width))"
                )
                measuredHeight = max(height, 1)
            }
        }
    }
}
#endif
