import AppKit
import SwiftUI

enum OpenCodeThemeID: String, CaseIterable, Identifiable, Codable {
    case native
    case githubLight = "github-light"
    case githubDark = "github-dark"
    case nord
    case oneDarkPro = "one-dark-pro"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native:
            return "Native"
        case .githubLight:
            return "GitHub Light"
        case .githubDark:
            return "GitHub Dark"
        case .nord:
            return "Nord"
        case .oneDarkPro:
            return "One Dark Pro"
        }
    }
}

struct OpenCodeTheme: Equatable {
    let id: OpenCodeThemeID
    let preferredColorScheme: ColorScheme?
    let windowBackgroundColor: NSColor
    let surfaceBackgroundColor: NSColor
    let mutedSurfaceBackgroundColor: NSColor
    let inputBackgroundColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let borderColor: NSColor
    let assistantBubbleColor: NSColor
    let codeBlockBackgroundColor: NSColor
    let toolCardBackgroundColor: NSColor
    let diffAdditionColor: NSColor
    let diffAdditionBackgroundColor: NSColor
    let diffDeletionColor: NSColor
    let diffDeletionBackgroundColor: NSColor

    static func == (lhs: OpenCodeTheme, rhs: OpenCodeTheme) -> Bool {
        lhs.id == rhs.id
    }

    static func resolve(_ id: OpenCodeThemeID) -> OpenCodeTheme {
        switch id {
        case .native:
            return OpenCodeTheme(
                id: .native,
                preferredColorScheme: nil,
                windowBackgroundColor: .windowBackgroundColor,
                surfaceBackgroundColor: .windowBackgroundColor,
                mutedSurfaceBackgroundColor: .controlBackgroundColor,
                inputBackgroundColor: .textBackgroundColor,
                primaryTextColor: .labelColor,
                secondaryTextColor: .secondaryLabelColor,
                borderColor: .separatorColor.withAlphaComponent(0.7),
                assistantBubbleColor: .controlBackgroundColor,
                codeBlockBackgroundColor: .controlBackgroundColor,
                toolCardBackgroundColor: .controlBackgroundColor,
                diffAdditionColor: .systemGreen,
                diffAdditionBackgroundColor: .systemGreen.withAlphaComponent(0.16),
                diffDeletionColor: .systemRed,
                diffDeletionBackgroundColor: .systemRed.withAlphaComponent(0.16)
            )
        case .githubLight:
            return OpenCodeTheme(
                id: .githubLight,
                preferredColorScheme: .light,
                windowBackgroundColor: NSColor(hex: 0xFFFFFF),
                surfaceBackgroundColor: NSColor(hex: 0xF6F8FA),
                mutedSurfaceBackgroundColor: NSColor(hex: 0xEFF2F5),
                inputBackgroundColor: NSColor(hex: 0xFFFFFF),
                primaryTextColor: NSColor(hex: 0x1F2328),
                secondaryTextColor: NSColor(hex: 0x656D76),
                borderColor: NSColor(hex: 0xD0D7DE),
                assistantBubbleColor: NSColor(hex: 0xF6F8FA),
                codeBlockBackgroundColor: NSColor(hex: 0xEFF2F5),
                toolCardBackgroundColor: NSColor(hex: 0xF0F3F6),
                diffAdditionColor: NSColor(hex: 0x1A7F37),
                diffAdditionBackgroundColor: NSColor(hex: 0xDFF3E4),
                diffDeletionColor: NSColor(hex: 0xCF222E),
                diffDeletionBackgroundColor: NSColor(hex: 0xFFEBE9)
            )
        case .githubDark:
            return OpenCodeTheme(
                id: .githubDark,
                preferredColorScheme: .dark,
                windowBackgroundColor: NSColor(hex: 0x0D1117),
                surfaceBackgroundColor: NSColor(hex: 0x161B22),
                mutedSurfaceBackgroundColor: NSColor(hex: 0x1F2630),
                inputBackgroundColor: NSColor(hex: 0x0D1117),
                primaryTextColor: NSColor(hex: 0xE6EDF3),
                secondaryTextColor: NSColor(hex: 0x8B949E),
                borderColor: NSColor(hex: 0x30363D),
                assistantBubbleColor: NSColor(hex: 0x161B22),
                codeBlockBackgroundColor: NSColor(hex: 0x11161D),
                toolCardBackgroundColor: NSColor(hex: 0x11161D),
                diffAdditionColor: NSColor(hex: 0x3FB950),
                diffAdditionBackgroundColor: NSColor(hex: 0x0F381A),
                diffDeletionColor: NSColor(hex: 0xF85149),
                diffDeletionBackgroundColor: NSColor(hex: 0x3F1518)
            )
        case .nord:
            return OpenCodeTheme(
                id: .nord,
                preferredColorScheme: .dark,
                windowBackgroundColor: NSColor(hex: 0x2E3440),
                surfaceBackgroundColor: NSColor(hex: 0x3B4252),
                mutedSurfaceBackgroundColor: NSColor(hex: 0x434C5E),
                inputBackgroundColor: NSColor(hex: 0x2A303B),
                primaryTextColor: NSColor(hex: 0xECEFF4),
                secondaryTextColor: NSColor(hex: 0xD8DEE9),
                borderColor: NSColor(hex: 0x4C566A),
                assistantBubbleColor: NSColor(hex: 0x434C5E),
                codeBlockBackgroundColor: NSColor(hex: 0x2A303B),
                toolCardBackgroundColor: NSColor(hex: 0x2A303B),
                diffAdditionColor: NSColor(hex: 0xA3BE8C),
                diffAdditionBackgroundColor: NSColor(hex: 0x3E4C41),
                diffDeletionColor: NSColor(hex: 0xBF616A),
                diffDeletionBackgroundColor: NSColor(hex: 0x4D3841)
            )
        case .oneDarkPro:
            return OpenCodeTheme(
                id: .oneDarkPro,
                preferredColorScheme: .dark,
                windowBackgroundColor: NSColor(hex: 0x282C34),
                surfaceBackgroundColor: NSColor(hex: 0x31353F),
                mutedSurfaceBackgroundColor: NSColor(hex: 0x3A3F4B),
                inputBackgroundColor: NSColor(hex: 0x21252B),
                primaryTextColor: NSColor(hex: 0xABB2BF),
                secondaryTextColor: NSColor(hex: 0x7F848E),
                borderColor: NSColor(hex: 0x4B5263),
                assistantBubbleColor: NSColor(hex: 0x31353F),
                codeBlockBackgroundColor: NSColor(hex: 0x21252B),
                toolCardBackgroundColor: NSColor(hex: 0x21252B),
                diffAdditionColor: NSColor(hex: 0x98C379),
                diffAdditionBackgroundColor: NSColor(hex: 0x253126),
                diffDeletionColor: NSColor(hex: 0xE06C75),
                diffDeletionBackgroundColor: NSColor(hex: 0x3B2228)
            )
        }
    }

    var displayName: String { id.displayName }
    var windowBackground: Color { Color(nsColor: windowBackgroundColor) }
    var surfaceBackground: Color { Color(nsColor: surfaceBackgroundColor) }
    var mutedSurfaceBackground: Color { Color(nsColor: mutedSurfaceBackgroundColor) }
    var inputBackground: Color { Color(nsColor: inputBackgroundColor) }
    var primaryText: Color { Color(nsColor: primaryTextColor) }
    var secondaryText: Color { Color(nsColor: secondaryTextColor) }
    var border: Color { Color(nsColor: borderColor) }
    var assistantBubble: Color { Color(nsColor: assistantBubbleColor) }
    var codeBlockBackground: Color { Color(nsColor: codeBlockBackgroundColor) }
    var toolCardBackground: Color { Color(nsColor: toolCardBackgroundColor) }
    var diffAddition: Color { Color(nsColor: diffAdditionColor) }
    var diffAdditionBackground: Color { Color(nsColor: diffAdditionBackgroundColor) }
    var diffDeletion: Color { Color(nsColor: diffDeletionColor) }
    var diffDeletionBackground: Color { Color(nsColor: diffDeletionBackgroundColor) }
}

@MainActor
final class ThemeController: ObservableObject {
    enum Constants {
        static let selectedThemeKey = "selectedTheme"
    }

    @Published private(set) var selectedThemeID: OpenCodeThemeID

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawValue = defaults.string(forKey: Constants.selectedThemeKey),
           let storedTheme = OpenCodeThemeID(rawValue: rawValue) {
            selectedThemeID = storedTheme
        } else {
            selectedThemeID = .native
        }
    }

    var selectedTheme: OpenCodeTheme {
        OpenCodeTheme.resolve(selectedThemeID)
    }

    func selectTheme(_ themeID: OpenCodeThemeID) {
        guard selectedThemeID != themeID else { return }
        selectedThemeID = themeID
        defaults.set(themeID.rawValue, forKey: Constants.selectedThemeKey)
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

private extension NSColor {
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
    var color: Color {
        switch tint {
        case .idle:
            return Color(nsColor: .systemGreen)
        case .busy:
            return Color(nsColor: .systemOrange)
        case .retry:
            return Color(nsColor: .systemYellow)
        case .permission:
            return Color(nsColor: .systemRed)
        }
    }
}
