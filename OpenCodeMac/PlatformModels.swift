import AppKit
import SwiftUI
import Textual

extension OpenCodeThemeID: CaseIterable {
    static var allCases: [OpenCodeThemeID] {
        [.native] + TextMateThemeCatalog.shared.themeIDs
    }

    var displayName: String {
        if self == .native {
            return "Native"
        }

        return TextMateThemeCatalog.shared.displayName(for: self) ?? rawValue.humanizedThemeName
    }

    var isSupported: Bool {
        self == .native || TextMateThemeCatalog.shared.contains(self)
    }
}

struct OpenCodeTheme: Equatable {
    let id: OpenCodeThemeID
    let preferredColorScheme: ColorScheme?
    let highlighterTheme: StructuredText.HighlighterTheme
    let windowBackgroundColor: NSColor
    let surfaceBackgroundColor: NSColor
    let mutedSurfaceBackgroundColor: NSColor
    let inputBackgroundColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let borderColor: NSColor
    let accentColor: NSColor
    let accentSubtleBackgroundColor: NSColor
    let assistantBubbleColor: NSColor
    let userBubbleColor: NSColor
    let codeBlockBackgroundColor: NSColor
    let toolCardBackgroundColor: NSColor
    let diffAdditionColor: NSColor
    let diffAdditionBackgroundColor: NSColor
    let diffDeletionColor: NSColor
    let diffDeletionBackgroundColor: NSColor
    let warningColor: NSColor
    let errorColor: NSColor
    let errorBackgroundColor: NSColor
    let positiveColor: NSColor

    static func == (lhs: OpenCodeTheme, rhs: OpenCodeTheme) -> Bool {
        lhs.id == rhs.id
    }

    static func resolve(_ id: OpenCodeThemeID) -> OpenCodeTheme {
        if id == .native {
            return nativeTheme
        }

        return TextMateThemeCatalog.shared.theme(for: id) ?? nativeTheme
    }

    private static let nativeTheme = OpenCodeTheme(
        id: .native,
        preferredColorScheme: nil,
        highlighterTheme: .default,
        windowBackgroundColor: .windowBackgroundColor,
        surfaceBackgroundColor: .windowBackgroundColor,
        mutedSurfaceBackgroundColor: .controlBackgroundColor,
        inputBackgroundColor: .textBackgroundColor,
        primaryTextColor: .labelColor,
        secondaryTextColor: .secondaryLabelColor,
        borderColor: .separatorColor.withAlphaComponent(0.7),
        accentColor: .controlAccentColor,
        accentSubtleBackgroundColor: .controlAccentColor.withAlphaComponent(0.14),
        assistantBubbleColor: .controlBackgroundColor,
        userBubbleColor: .controlAccentColor.withAlphaComponent(0.14),
        codeBlockBackgroundColor: .controlBackgroundColor,
        toolCardBackgroundColor: .underPageBackgroundColor,
        diffAdditionColor: .systemGreen,
        diffAdditionBackgroundColor: .systemGreen.withAlphaComponent(0.16),
        diffDeletionColor: .systemRed,
        diffDeletionBackgroundColor: .systemRed.withAlphaComponent(0.16),
        warningColor: .systemOrange,
        errorColor: .systemRed,
        errorBackgroundColor: .systemRed.withAlphaComponent(0.08),
        positiveColor: .systemGreen
    )

    var displayName: String { id.displayName }
    var windowBackground: Color { Color(nsColor: windowBackgroundColor) }
    var surfaceBackground: Color { Color(nsColor: surfaceBackgroundColor) }
    var mutedSurfaceBackground: Color { Color(nsColor: mutedSurfaceBackgroundColor) }
    var inputBackground: Color { Color(nsColor: inputBackgroundColor) }
    var primaryText: Color { Color(nsColor: primaryTextColor) }
    var secondaryText: Color { Color(nsColor: secondaryTextColor) }
    var border: Color { Color(nsColor: borderColor) }
    var accent: Color { Color(nsColor: accentColor) }
    var accentSubtleBackground: Color { Color(nsColor: accentSubtleBackgroundColor) }
    var assistantBubble: Color { Color(nsColor: assistantBubbleColor) }
    var userBubble: Color { Color(nsColor: userBubbleColor) }
    var codeBlockBackground: Color { Color(nsColor: codeBlockBackgroundColor) }
    var toolCardBackground: Color { Color(nsColor: toolCardBackgroundColor) }
    var diffAddition: Color { Color(nsColor: diffAdditionColor) }
    var diffAdditionBackground: Color { Color(nsColor: diffAdditionBackgroundColor) }
    var diffDeletion: Color { Color(nsColor: diffDeletionColor) }
    var diffDeletionBackground: Color { Color(nsColor: diffDeletionBackgroundColor) }
    var warning: Color { Color(nsColor: warningColor) }
    var error: Color { Color(nsColor: errorColor) }
    var errorBackground: Color { Color(nsColor: errorBackgroundColor) }
    var positive: Color { Color(nsColor: positiveColor) }

}

extension ThemeController {
    var selectedTheme: OpenCodeTheme {
        OpenCodeTheme.resolve(selectedThemeID)
    }
}

private struct OpenCodeThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = OpenCodeTheme.resolve(.native)
}

extension EnvironmentValues {
    var openCodeTheme: OpenCodeTheme {
        get { self[OpenCodeThemeEnvironmentKey.self] }
        set { self[OpenCodeThemeEnvironmentKey.self] = newValue }
    }
}

extension View {
    func themedWindow(_ theme: OpenCodeTheme) -> some View {
        background(WindowThemeView(theme: theme))
    }
}

struct WindowThemeView: NSViewRepresentable {
    let theme: OpenCodeTheme

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.backgroundColor = theme.windowBackgroundColor
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct SessionWindowContext: Codable, Hashable {
    let connection: WorkspaceConnection
    let sessionID: String
}

extension SessionIndicator {
    func color() -> Color {
        switch tint {
        case .idle:
            return .green
        case .busy, .retry:
            return .yellow
        case .permission:
            return .red
        }
    }
}
