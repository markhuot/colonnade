import AppKit
import SwiftUI
import Textual

struct OpenCodeThemeID: RawRepresentable, Hashable, Codable, Identifiable, CaseIterable, Sendable {
    static let native = Self(rawValue: "native")
    static let githubLight = Self(rawValue: "github-light")
    static let githubDark = Self(rawValue: "github-dark")
    static let nord = Self(rawValue: "nord")
    static let oneDarkPro = Self(rawValue: "one-dark-pro")

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }

    static var allCases: [OpenCodeThemeID] {
        [.native] + ShikiThemeCatalog.shared.themeIDs
    }

    var displayName: String {
        if self == .native {
            return "Native"
        }

        return ShikiThemeCatalog.shared.displayName(for: self) ?? rawValue.humanizedThemeName
    }

    var isSupported: Bool {
        self == .native || ShikiThemeCatalog.shared.contains(self)
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

        return ShikiThemeCatalog.shared.theme(for: id) ?? nativeTheme
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

@MainActor
final class ThemeController: ObservableObject {
    enum Constants {
        static let selectedThemeKey = "selectedTheme"
    }

    @Published private(set) var selectedThemeID: OpenCodeThemeID

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawValue = defaults.string(forKey: Constants.selectedThemeKey) {
            let storedTheme = OpenCodeThemeID(rawValue: rawValue)
            selectedThemeID = storedTheme.isSupported ? storedTheme : .native
        } else {
            selectedThemeID = .native
        }
    }

    var selectedTheme: OpenCodeTheme {
        OpenCodeTheme.resolve(selectedThemeID)
    }

    func selectTheme(_ themeID: OpenCodeThemeID) {
        guard themeID.isSupported, selectedThemeID != themeID else { return }
        selectedThemeID = themeID
        defaults.set(themeID.rawValue, forKey: Constants.selectedThemeKey)
    }
}

@MainActor
final class ModelPreferencesController: ObservableObject {
    enum Constants {
        static let preferredDefaultModelKey = "preferredDefaultModel"
    }

    @Published private(set) var preferredDefaultModelReference: ModelReference?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredDefaultModelReference = Self.loadPreferredDefaultModelReference(from: defaults)
    }

    func setPreferredDefaultModelReference(_ reference: ModelReference?) {
        guard preferredDefaultModelReference != reference else { return }
        preferredDefaultModelReference = reference

        if let reference {
            defaults.set(reference.key, forKey: Constants.preferredDefaultModelKey)
        } else {
            defaults.removeObject(forKey: Constants.preferredDefaultModelKey)
        }
    }

    private static func loadPreferredDefaultModelReference(from defaults: UserDefaults) -> ModelReference? {
        guard let key = defaults.string(forKey: Constants.preferredDefaultModelKey) else { return nil }
        return ModelReference(key: key)
    }
}

@MainActor
final class LocalServerPreferencesController: ObservableObject {
    enum Constants {
        static let opencodeExecutablePathKey = "opencodeExecutablePath"
        static let defaultOpencodeExecutablePath = "~/.bun/bin/opencode"
    }

    @Published private(set) var opencodeExecutablePath: String

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        opencodeExecutablePath = Self.loadOpencodeExecutablePath(from: defaults)
    }

    func setOpencodeExecutablePath(_ path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = trimmedPath.isEmpty ? Constants.defaultOpencodeExecutablePath : trimmedPath
        guard opencodeExecutablePath != normalizedPath else { return }

        opencodeExecutablePath = normalizedPath

        if normalizedPath == Constants.defaultOpencodeExecutablePath {
            defaults.removeObject(forKey: Constants.opencodeExecutablePathKey)
        } else {
            defaults.set(normalizedPath, forKey: Constants.opencodeExecutablePathKey)
        }
    }

    nonisolated static func loadOpencodeExecutablePath(from defaults: UserDefaults = .standard) -> String {
        let storedPath = defaults.string(forKey: Constants.opencodeExecutablePathKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return storedPath?.isEmpty == false ? storedPath! : Constants.defaultOpencodeExecutablePath
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
