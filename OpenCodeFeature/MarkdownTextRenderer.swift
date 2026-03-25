import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MarkdownTextStyle {
    enum BaseStyle {
        case body
        case callout
    }

    let baseStyle: BaseStyle
    let foregroundColor: PlatformColor

    static func body(theme: OpenCodeTheme) -> Self {
        .init(baseStyle: .body, foregroundColor: theme.primaryTextColor)
    }

    static func callout(theme: OpenCodeTheme, foregroundColor: PlatformColor? = nil) -> Self {
        .init(baseStyle: .callout, foregroundColor: foregroundColor ?? theme.secondaryTextColor)
    }
}

enum MarkdownTextRenderer {
    static func render(
        text: String,
        rendersMarkdown: Bool,
        theme: OpenCodeTheme,
        style: MarkdownTextStyle
    ) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString(string: "") }

        let styleName: String = switch style.baseStyle {
        case .body:
            "body"
        case .callout:
            "callout"
        }

        guard rendersMarkdown, let markdown = try? AttributedString(markdown: text) else {
            return PerformanceInstrumentation.measure(
                "markdown-render-plain-text",
                thresholdMS: 1,
                details: "style=\(styleName) bytes=\(text.utf8.count)"
            ) {
                plainText(text, theme: theme, style: style)
            }
        }

        let blocks = PerformanceInstrumentation.measure(
            "markdown-render-collect-blocks",
            thresholdMS: 1,
            details: "style=\(styleName) bytes=\(text.utf8.count)"
        ) {
            collectBlocks(from: markdown)
        }
        guard !blocks.isEmpty else {
            return PerformanceInstrumentation.measure(
                "markdown-render-fallback-plain-text",
                thresholdMS: 1,
                details: "style=\(styleName) bytes=\(text.utf8.count)"
            ) {
                plainText(text, theme: theme, style: style)
            }
        }

        return PerformanceInstrumentation.measure(
            "markdown-render-compose",
            thresholdMS: 1,
            details: "style=\(styleName) bytes=\(text.utf8.count) blocks=\(blocks.count)"
        ) {
            compose(blocks: blocks, theme: theme, style: style)
        }
    }

    private static func plainText(_ text: String, theme: OpenCodeTheme, style: MarkdownTextStyle) -> NSAttributedString {
        NSAttributedString(string: text, attributes: baseAttributes(theme: theme, style: style))
    }

    private static func compose(blocks: [MarkdownBlock], theme: OpenCodeTheme, style: MarkdownTextStyle) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: separator(between: blocks[index - 1].kind, and: block.kind)))
            }

            output.append(attributedString(for: block, theme: theme, style: style))
        }

        return output
    }

    private static func separator(between previous: MarkdownBlock.Kind, and next: MarkdownBlock.Kind) -> String {
        switch (previous, next) {
        case (.listItem(_, _, _), .listItem(_, _, _)):
            return "\n"
        default:
            return "\n\n"
        }
    }

    private static func attributedString(for block: MarkdownBlock, theme: OpenCodeTheme, style: MarkdownTextStyle) -> NSAttributedString {
        let content = NSMutableAttributedString()

        switch block.kind {
        case .codeBlock:
            for segment in block.segments {
                content.append(NSAttributedString(string: segment.text, attributes: codeBlockAttributes(theme: theme, style: style)))
            }

            while content.string.hasSuffix("\n") {
                content.deleteCharacters(in: NSRange(location: content.length - 1, length: 1))
            }

            let paragraphStyle = paragraphStyle()
            paragraphStyle.paragraphSpacing = 2
            paragraphStyle.paragraphSpacingBefore = 2
            paragraphStyle.firstLineHeadIndent = 10
            paragraphStyle.headIndent = 10

            content.addAttributes([
                .paragraphStyle: paragraphStyle,
                .backgroundColor: theme.codeBlockBackgroundColor,
                .foregroundColor: theme.primaryTextColor
            ], range: NSRange(location: 0, length: content.length))

        case let .listItem(ordered, ordinal, depth):
            let prefix = listPrefix(ordered: ordered, ordinal: ordinal, depth: depth)
            let prefixAttributes = baseAttributes(theme: theme, style: style)
            content.append(NSAttributedString(string: prefix, attributes: prefixAttributes))

            for segment in block.segments {
                content.append(attributedString(for: segment, theme: theme, style: style))
            }

            let paragraphStyle = paragraphStyle()
            paragraphStyle.paragraphSpacing = 2
            let headIndent = measuredWidth(for: prefix, font: baseFont(for: style.baseStyle))
            paragraphStyle.headIndent = headIndent

            content.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: content.length))

        case .paragraph:
            for segment in block.segments {
                content.append(attributedString(for: segment, theme: theme, style: style))
            }

            let paragraphStyle = paragraphStyle()
            paragraphStyle.paragraphSpacing = 2
            content.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: content.length))
        }

        return content
    }

    private static func attributedString(for segment: MarkdownSegment, theme: OpenCodeTheme, style: MarkdownTextStyle) -> NSAttributedString {
        var attributes = baseAttributes(theme: theme, style: style)

        if let intent = segment.inlineIntent {
            if intent.contains(.stronglyEmphasized) {
                attributes[.font] = boldFont(for: style.baseStyle)
            }

            if intent.contains(.emphasized) {
                let currentFont = (attributes[.font] as? PlatformFont) ?? baseFont(for: style.baseStyle)
                attributes[.font] = italicized(font: currentFont)
            }

            if intent.contains(.code) {
                attributes[.font] = monospacedFont(for: style.baseStyle)
                attributes[.backgroundColor] = theme.codeBlockBackgroundColor
                attributes[.foregroundColor] = theme.primaryTextColor
            }
        }

        if let link = segment.link {
            attributes[.link] = link
            attributes[.foregroundColor] = theme.accentColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return NSAttributedString(string: segment.text, attributes: attributes)
    }

    private static func collectBlocks(from attributed: AttributedString) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentDescriptor: MarkdownBlockDescriptor?
        var currentSegments: [MarkdownSegment] = []

        func flushCurrentBlock() {
            guard let currentDescriptor, !currentSegments.isEmpty else { return }
            blocks.append(MarkdownBlock(kind: currentDescriptor.kind, segments: currentSegments))
            currentSegments = []
        }

        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            guard !text.isEmpty else { continue }

            let descriptor = blockDescriptor(for: run.presentationIntent)
            if descriptor != currentDescriptor {
                flushCurrentBlock()
                currentDescriptor = descriptor
            }

            currentSegments.append(MarkdownSegment(text: text, inlineIntent: run.inlinePresentationIntent, link: run.link))
        }

        flushCurrentBlock()
        return blocks
    }

    private static func blockDescriptor(for presentationIntent: PresentationIntent?) -> MarkdownBlockDescriptor {
        let components = presentationIntent?.components ?? []

        if let codeBlock = components.first(where: { component in
            if case .codeBlock = component.kind { return true }
            return false
        }), case let .codeBlock(language) = codeBlock.kind {
            return MarkdownBlockDescriptor(identity: codeBlock.identity, kind: .codeBlock(language: language))
        }

        let listDepth = components.filter { component in
            switch component.kind {
            case .orderedList, .unorderedList:
                return true
            default:
                return false
            }
        }.count

        let isOrderedList = components.contains { component in
            if case .orderedList = component.kind { return true }
            return false
        }

        if let listItem = components.first(where: { component in
            if case .listItem = component.kind { return true }
            return false
        }), case let .listItem(ordinal) = listItem.kind {
            let identity = components.first(where: { component in
                if case .paragraph = component.kind { return true }
                return false
            })?.identity ?? listItem.identity

            return MarkdownBlockDescriptor(
                identity: identity,
                kind: .listItem(ordered: isOrderedList, ordinal: ordinal, depth: max(listDepth, 1))
            )
        }

        let paragraphIdentity = components.first(where: { component in
            if case .paragraph = component.kind { return true }
            return false
        })?.identity ?? 0

        return MarkdownBlockDescriptor(identity: paragraphIdentity, kind: .paragraph)
    }

    private static func listPrefix(ordered: Bool, ordinal: Int, depth: Int) -> String {
        let indent = String(repeating: "    ", count: max(depth - 1, 0))
        let marker = ordered ? "\(ordinal)." : "-"
        return indent + marker + " "
    }

    private static func paragraphStyle() -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineHeightMultiple = 1.2
        return paragraphStyle
    }

    private static func baseAttributes(theme: OpenCodeTheme, style: MarkdownTextStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont(for: style.baseStyle),
            .foregroundColor: style.foregroundColor
        ]
    }

    private static func codeBlockAttributes(theme: OpenCodeTheme, style: MarkdownTextStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: monospacedFont(for: style.baseStyle),
            .foregroundColor: theme.primaryTextColor,
            .backgroundColor: theme.codeBlockBackgroundColor
        ]
    }

    private static func measuredWidth(for text: String, font: PlatformFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func baseFont(for style: MarkdownTextStyle.BaseStyle) -> PlatformFont {
        #if os(macOS)
        switch style {
        case .body:
            return .systemFont(ofSize: 14)
        case .callout:
            return .systemFont(ofSize: 13)
        }
        #else
        switch style {
        case .body:
            return .preferredFont(forTextStyle: .body)
        case .callout:
            return .preferredFont(forTextStyle: .callout)
        }
        #endif
    }

    private static func boldFont(for style: MarkdownTextStyle.BaseStyle) -> PlatformFont {
        let font = baseFont(for: style)
        #if os(macOS)
        return .systemFont(ofSize: font.pointSize, weight: .semibold)
        #else
        return .systemFont(ofSize: font.pointSize, weight: .semibold)
        #endif
    }

    private static func italicized(font: PlatformFont) -> PlatformFont {
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #else
        guard let descriptor = font.fontDescriptor.withSymbolicTraits([font.fontDescriptor.symbolicTraits, .traitItalic]) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #endif
    }

    private static func monospacedFont(for style: MarkdownTextStyle.BaseStyle) -> PlatformFont {
        let font = baseFont(for: style)
        #if os(macOS)
        return .monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular)
        #else
        return .monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular)
        #endif
    }
}

private struct MarkdownBlockDescriptor: Equatable {
    let identity: Int
    let kind: MarkdownBlock.Kind
}

private struct MarkdownBlock {
    enum Kind: Equatable {
        case paragraph
        case listItem(ordered: Bool, ordinal: Int, depth: Int)
        case codeBlock(language: String?)
    }

    let kind: Kind
    let segments: [MarkdownSegment]
}

private struct MarkdownSegment {
    let text: String
    let inlineIntent: InlinePresentationIntent?
    let link: URL?
}
