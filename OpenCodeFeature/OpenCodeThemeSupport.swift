import SwiftUI

#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#endif

extension OpenCodeThemeID: CaseIterable {
    static var allCases: [OpenCodeThemeID] {
        [.native] + OpenCodeThemeCatalogBridge.themeIDs
    }

    var displayName: String {
        if self == .native {
            return "Native"
        }

        return OpenCodeThemeCatalogBridge.displayName(for: self) ?? Self.fallbackDisplayName(for: rawValue)
    }

    var isSupported: Bool {
        self == .native || OpenCodeThemeCatalogBridge.contains(self)
    }

    private static func fallbackDisplayName(for rawValue: String) -> String {
        rawValue
            .split(separator: "-")
            .map { component in
                component.isEmpty ? "" : component.prefix(1).uppercased() + component.dropFirst()
            }
            .joined(separator: " ")
    }
}

struct OpenCodeTheme: Equatable {
    let id: OpenCodeThemeID
    let preferredColorScheme: ColorScheme?
    let windowBackgroundColor: PlatformColor
    let surfaceBackgroundColor: PlatformColor
    let mutedSurfaceBackgroundColor: PlatformColor
    let inputBackgroundColor: PlatformColor
    let primaryTextColor: PlatformColor
    let secondaryTextColor: PlatformColor
    let borderColor: PlatformColor
    let accentColor: PlatformColor
    let accentSubtleBackgroundColor: PlatformColor
    let assistantBubbleColor: PlatformColor
    let userBubbleColor: PlatformColor
    let codeBlockBackgroundColor: PlatformColor
    let toolCardBackgroundColor: PlatformColor
    let diffAdditionColor: PlatformColor
    let diffAdditionBackgroundColor: PlatformColor
    let diffDeletionColor: PlatformColor
    let diffDeletionBackgroundColor: PlatformColor
    let warningColor: PlatformColor
    let errorColor: PlatformColor
    let errorBackgroundColor: PlatformColor
    let positiveColor: PlatformColor

    static func == (lhs: OpenCodeTheme, rhs: OpenCodeTheme) -> Bool {
        lhs.id == rhs.id
    }

    static func resolve(_ id: OpenCodeThemeID) -> OpenCodeTheme {
        if id == .native {
            return nativeTheme
        }

        return OpenCodeThemeCatalogBridge.theme(for: id) ?? nativeTheme
    }

    #if os(macOS)
    private static let nativeTheme = OpenCodeTheme(
        id: .native,
        preferredColorScheme: nil,
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
    #else
    private static let nativeTheme = OpenCodeTheme(
        id: .native,
        preferredColorScheme: nil,
        windowBackgroundColor: .systemBackground,
        surfaceBackgroundColor: .secondarySystemBackground,
        mutedSurfaceBackgroundColor: .tertiarySystemBackground,
        inputBackgroundColor: .secondarySystemBackground,
        primaryTextColor: .label,
        secondaryTextColor: .secondaryLabel,
        borderColor: UIColor.separator.withAlphaComponent(0.7),
        accentColor: .systemBlue,
        accentSubtleBackgroundColor: UIColor.systemBlue.withAlphaComponent(0.14),
        assistantBubbleColor: .secondarySystemBackground,
        userBubbleColor: UIColor.systemBlue.withAlphaComponent(0.14),
        codeBlockBackgroundColor: .tertiarySystemBackground,
        toolCardBackgroundColor: .secondarySystemBackground,
        diffAdditionColor: .systemGreen,
        diffAdditionBackgroundColor: UIColor.systemGreen.withAlphaComponent(0.16),
        diffDeletionColor: .systemRed,
        diffDeletionBackgroundColor: UIColor.systemRed.withAlphaComponent(0.16),
        warningColor: .systemOrange,
        errorColor: .systemRed,
        errorBackgroundColor: UIColor.systemRed.withAlphaComponent(0.08),
        positiveColor: .systemGreen
    )
    #endif

    var displayName: String { id.displayName }

    #if os(macOS)
    var windowBackground: Color { Color(nsColor: windowBackgroundColor) }
    var surfaceBackground: Color { Color(nsColor: surfaceBackgroundColor) }
    var mutedSurfaceBackground: Color { Color(nsColor: mutedSurfaceBackgroundColor) }
    var opaqueMutedSurfaceBackground: Color { Color(nsColor: mutedSurfaceBackgroundColor.composited(over: windowBackgroundColor)) }
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
    #else
    var windowBackground: Color { Color(uiColor: windowBackgroundColor) }
    var surfaceBackground: Color { Color(uiColor: surfaceBackgroundColor) }
    var mutedSurfaceBackground: Color { Color(uiColor: mutedSurfaceBackgroundColor) }
    var opaqueMutedSurfaceBackground: Color { Color(uiColor: mutedSurfaceBackgroundColor.composited(over: windowBackgroundColor)) }
    var inputBackground: Color { Color(uiColor: inputBackgroundColor) }
    var primaryText: Color { Color(uiColor: primaryTextColor) }
    var secondaryText: Color { Color(uiColor: secondaryTextColor) }
    var border: Color { Color(uiColor: borderColor) }
    var accent: Color { Color(uiColor: accentColor) }
    var accentSubtleBackground: Color { Color(uiColor: accentSubtleBackgroundColor) }
    var assistantBubble: Color { Color(uiColor: assistantBubbleColor) }
    var userBubble: Color { Color(uiColor: userBubbleColor) }
    var codeBlockBackground: Color { Color(uiColor: codeBlockBackgroundColor) }
    var toolCardBackground: Color { Color(uiColor: toolCardBackgroundColor) }
    var diffAddition: Color { Color(uiColor: diffAdditionColor) }
    var diffAdditionBackground: Color { Color(uiColor: diffAdditionBackgroundColor) }
    var diffDeletion: Color { Color(uiColor: diffDeletionColor) }
    var diffDeletionBackground: Color { Color(uiColor: diffDeletionBackgroundColor) }
    var warning: Color { Color(uiColor: warningColor) }
    var error: Color { Color(uiColor: errorColor) }
    var errorBackground: Color { Color(uiColor: errorBackgroundColor) }
    var positive: Color { Color(uiColor: positiveColor) }
    #endif
}

extension ThemeController {
    var selectedTheme: OpenCodeTheme {
        OpenCodeTheme.resolve(selectedThemeID)
    }
}

private enum OpenCodeThemeCatalogBridge {
    static var themeIDs: [OpenCodeThemeID] {
        #if os(macOS)
        TextMateThemeCatalog.shared.themeIDs
        #else
        []
        #endif
    }

    static func displayName(for id: OpenCodeThemeID) -> String? {
        #if os(macOS)
        TextMateThemeCatalog.shared.displayName(for: id)
        #else
        nil
        #endif
    }

    static func contains(_ id: OpenCodeThemeID) -> Bool {
        #if os(macOS)
        TextMateThemeCatalog.shared.contains(id)
        #else
        false
        #endif
    }

    static func theme(for id: OpenCodeThemeID) -> OpenCodeTheme? {
        #if os(macOS)
        TextMateThemeCatalog.shared.theme(for: id)
        #else
        nil
        #endif
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

#if os(macOS)
private extension PlatformColor {
    var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    static func fromRGBA(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        PlatformColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
#else
private extension PlatformColor {
    var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red, green, blue, alpha)
        }

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: colorSpace, intent: .defaultIntent, options: nil),
            let components = converted.components
        else {
            return nil
        }

        switch components.count {
        case 4:
            return (components[0], components[1], components[2], components[3])
        case 2:
            return (components[0], components[0], components[0], components[1])
        default:
            return nil
        }
    }

    static func fromRGBA(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        PlatformColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif

private extension PlatformColor {
    func composited(over background: PlatformColor) -> PlatformColor {
        guard let foreground = rgbaComponents, let background = background.rgbaComponents else {
            return self
        }

        if foreground.alpha >= 1 {
            return self
        }

        return PlatformColor.fromRGBA(
            red: foreground.red * foreground.alpha + background.red * (1 - foreground.alpha),
            green: foreground.green * foreground.alpha + background.green * (1 - foreground.alpha),
            blue: foreground.blue * foreground.alpha + background.blue * (1 - foreground.alpha),
            alpha: 1
        )
    }
}

#if os(macOS)
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
#else
struct WindowThemeView: UIViewRepresentable {
    let theme: OpenCodeTheme

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            uiView.window?.backgroundColor = theme.windowBackgroundColor
        }
    }
}
#endif

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
