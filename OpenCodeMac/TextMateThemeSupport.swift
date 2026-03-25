import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private final class ThemeBundleMarker: NSObject {}

private struct TextMateThemeDocument: Decodable {
    let name: String
    let displayName: String?
    let type: String?
    let colors: [String: String]
    let tokenColors: [TextMateTokenColorRule]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        colors = try container.decodeIfPresent([String: String].self, forKey: .colors) ?? [:]
        tokenColors = try container.decodeIfPresent([TextMateTokenColorRule].self, forKey: .tokenColors) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case type
        case colors
        case tokenColors
    }
}

private struct TextMateTokenColorRule: Decodable {
    let scopes: [String]
    let settings: TextMateTokenSettings

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawScope = try container.decodeIfPresent(TextMateScopeValue.self, forKey: .scope)
        settings = try container.decodeIfPresent(TextMateTokenSettings.self, forKey: .settings) ?? .empty
        scopes = rawScope?.scopes ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case settings
    }
}

private enum TextMateScopeValue: Decodable {
    case string(String)
    case array([String])

    var scopes: [String] {
        switch self {
        case let .string(value):
            return value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case let .array(values):
            return values.flatMap { value in
                value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        self = .array(try container.decode([String].self))
    }
}

private struct TextMateTokenSettings: Decodable {
    let foreground: String?
    let background: String?
    let fontStyle: String?

    static let empty = Self(foreground: nil, background: nil, fontStyle: nil)
}

final class TextMateThemeCatalog: @unchecked Sendable {
    static let shared = TextMateThemeCatalog()

    private let displayNameByID: [OpenCodeThemeID: String]
    private let themeByID: [OpenCodeThemeID: OpenCodeTheme]
    private let orderedThemeIDs: [OpenCodeThemeID]

    private init(fileManager: FileManager = .default) {
        let decoder = JSONDecoder()
        var orderedThemeIDs: [OpenCodeThemeID] = []
        var displayNameByID: [OpenCodeThemeID: String] = [:]
        var themeByID: [OpenCodeThemeID: OpenCodeTheme] = [:]

        for themeURL in Self.themeFileURLs(fileManager: fileManager) {
            guard let data = try? Data(contentsOf: themeURL),
                  let document = try? decoder.decode(TextMateThemeDocument.self, from: data) else {
                continue
            }

            let id = OpenCodeThemeID(rawValue: document.name)
            let theme = Self.buildTheme(id: id, document: document)
            orderedThemeIDs.append(id)
            displayNameByID[id] = document.displayName ?? document.name.humanizedThemeName
            themeByID[id] = theme
        }

        orderedThemeIDs.sort {
            let lhs = displayNameByID[$0] ?? $0.rawValue
            let rhs = displayNameByID[$1] ?? $1.rawValue
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        self.orderedThemeIDs = orderedThemeIDs
        self.displayNameByID = displayNameByID
        self.themeByID = themeByID
    }

    var themeIDs: [OpenCodeThemeID] {
        orderedThemeIDs
    }

    func contains(_ id: OpenCodeThemeID) -> Bool {
        themeByID[id] != nil
    }

    func displayName(for id: OpenCodeThemeID) -> String? {
        displayNameByID[id]
    }

    func theme(for id: OpenCodeThemeID) -> OpenCodeTheme? {
        themeByID[id]
    }

    private static func buildTheme(id: OpenCodeThemeID, document: TextMateThemeDocument) -> OpenCodeTheme {
        let palette = TextMateThemePalette(document: document)

        return OpenCodeTheme(
            id: id,
            preferredColorScheme: palette.colorScheme,
            windowBackgroundColor: palette.windowBackground,
            surfaceBackgroundColor: palette.surfaceBackground,
            mutedSurfaceBackgroundColor: palette.mutedSurfaceBackground,
            inputBackgroundColor: palette.inputBackground,
            primaryTextColor: palette.primaryText,
            secondaryTextColor: palette.secondaryText,
            borderColor: palette.border,
            accentColor: palette.accent,
            accentSubtleBackgroundColor: palette.accentSubtleBackground,
            assistantBubbleColor: palette.assistantBubble,
            userBubbleColor: palette.userBubble,
            codeBlockBackgroundColor: palette.codeBlockBackground,
            toolCardBackgroundColor: palette.toolCardBackground,
            diffAdditionColor: palette.diffAddition,
            diffAdditionBackgroundColor: palette.diffAdditionBackground,
            diffDeletionColor: palette.diffDeletion,
            diffDeletionBackgroundColor: palette.diffDeletionBackground,
            warningColor: palette.warning,
            errorColor: palette.error,
            errorBackgroundColor: palette.errorBackground,
            positiveColor: palette.positive
        )
    }

    private static func themeFileURLs(fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        var seenPaths = Set<String>()

        for directoryURL in resourceDirectories(fileManager: fileManager) {
            guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil) else {
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "json" {
                guard seenPaths.insert(fileURL.path).inserted else { continue }
                urls.append(fileURL)
            }
        }

        return urls.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    private static func resourceDirectories(fileManager: FileManager) -> [URL] {
        let candidateBundles = [Bundle.main, Bundle(for: ThemeBundleMarker.self)] + Bundle.allBundles + Bundle.allFrameworks
        var directories: [URL] = []
        var seenPaths = Set<String>()

        for bundle in candidateBundles {
            guard let resourceURL = bundle.resourceURL else { continue }

            let folderURL = resourceURL.appendingPathComponent("TextMateThemes", isDirectory: true)
            if fileManager.fileExists(atPath: folderURL.path), seenPaths.insert(folderURL.path).inserted {
                directories.append(folderURL)
            }

            if bundle.url(forResource: "github-dark", withExtension: "json") != nil,
               seenPaths.insert(resourceURL.path).inserted {
                directories.append(resourceURL)
            }
        }

        return directories
    }
}

private struct TextMateThemePalette {
    let colorScheme: ColorScheme?
    let windowBackground: PlatformColor
    let surfaceBackground: PlatformColor
    let mutedSurfaceBackground: PlatformColor
    let inputBackground: PlatformColor
    let primaryText: PlatformColor
    let secondaryText: PlatformColor
    let border: PlatformColor
    let accent: PlatformColor
    let accentSubtleBackground: PlatformColor
    let assistantBubble: PlatformColor
    let userBubble: PlatformColor
    let codeForeground: PlatformColor
    let codeBlockBackground: PlatformColor
    let toolCardBackground: PlatformColor
    let diffAddition: PlatformColor
    let diffAdditionBackground: PlatformColor
    let diffDeletion: PlatformColor
    let diffDeletionBackground: PlatformColor
    let warning: PlatformColor
    let error: PlatformColor
    let errorBackground: PlatformColor
    let positive: PlatformColor

    init(document: TextMateThemeDocument) {
        let themeType = document.type?.lowercased()
        let isDark = themeType == "dark"
        let colors = document.colors

        colorScheme = switch themeType {
        case "light": .light
        case "dark": .dark
        default: nil
        }

        let defaultWindow = PlatformColor(hex: isDark ? 0x111111 : 0xFFFFFF)
        let defaultForeground = PlatformColor(hex: isDark ? 0xE6E6E6 : 0x1F2328)
        let defaultAccent = PlatformColor(hex: isDark ? 0x61AFEF : 0x0B6BDE)
        let defaultPositive = PlatformColor(hex: isDark ? 0x3FB950 : 0x1A7F37)
        let defaultWarning = PlatformColor(hex: isDark ? 0xE3B341 : 0x9A6700)
        let defaultError = PlatformColor(hex: isDark ? 0xF85149 : 0xCF222E)

        windowBackground = Self.color(in: colors, keys: ["editor.background", "sideBar.background", "activityBar.background"]) ?? defaultWindow
        surfaceBackground = Self.color(in: colors, keys: ["sideBar.background", "panel.background", "editorWidget.background"]) ?? windowBackground.shiftedSurface(isDark: isDark, amount: 0.06)
        mutedSurfaceBackground = Self.color(in: colors, keys: ["editor.lineHighlightBackground", "list.hoverBackground", "editorWidget.background"]) ?? surfaceBackground.shiftedSurface(isDark: isDark, amount: 0.05)
        inputBackground = Self.color(in: colors, keys: ["input.background", "dropdown.background", "editorWidget.background"]) ?? mutedSurfaceBackground
        primaryText = Self.color(in: colors, keys: ["editor.foreground", "foreground", "sideBar.foreground"]) ?? defaultForeground
        secondaryText = Self.color(in: colors, keys: ["descriptionForeground", "sideBar.foreground", "titleBar.inactiveForeground"]) ?? primaryText.withAlphaComponent(isDark ? 0.72 : 0.62)
        border = Self.color(in: colors, keys: ["panel.border", "editorGroup.border", "input.border", "dropdown.border", "sideBar.border"]) ?? primaryText.withAlphaComponent(isDark ? 0.18 : 0.12)
        let accentMinimumContrast: CGFloat = 1.75
        let focusAccent = Self.color(
            in: colors,
            keys: ["focusBorder"],
            meetingMinimumContrast: accentMinimumContrast,
            against: windowBackground
        )
        let fallbackAccent = Self.color(
            in: colors,
            keys: ["textLink.foreground", "progressBar.background", "editorCursor.foreground", "activityBarBadge.background"],
            meetingMinimumContrast: accentMinimumContrast,
            against: windowBackground
        ) ?? Self.color(in: colors, keys: ["textLink.foreground", "progressBar.background", "editorCursor.foreground", "activityBarBadge.background"])
        accent = focusAccent ?? fallbackAccent ?? defaultAccent
        accentSubtleBackground = Self.color(in: colors, keys: ["editor.selectionBackground", "list.focusBackground", "badge.background"]) ?? accent.withAlphaComponent(0.14)
        assistantBubble = Self.color(in: colors, keys: ["textBlockQuote.background", "panel.background", "editorWidget.background"]) ?? surfaceBackground
        userBubble = accentSubtleBackground
        codeForeground = Self.color(in: colors, keys: ["editor.foreground", "textPreformat.foreground", "foreground"]) ?? primaryText
        codeBlockBackground = Self.color(in: colors, keys: ["textCodeBlock.background", "editorWidget.background", "editor.background"]) ?? mutedSurfaceBackground
        toolCardBackground = Self.color(in: colors, keys: ["panel.background", "peekViewResult.background", "editorWidget.background"]) ?? mutedSurfaceBackground
        positive = Self.color(in: colors, keys: ["gitDecoration.addedResourceForeground", "terminal.ansiGreen", "editorGutter.addedBackground"]) ?? defaultPositive
        diffAddition = positive
        diffAdditionBackground = Self.color(in: colors, keys: ["diffEditor.insertedTextBackground"]) ?? positive.withAlphaComponent(0.18)
        error = Self.color(in: colors, keys: ["errorForeground", "editorError.foreground", "gitDecoration.deletedResourceForeground", "terminal.ansiRed", "editorGutter.deletedBackground"]) ?? defaultError
        diffDeletion = error
        diffDeletionBackground = Self.color(in: colors, keys: ["diffEditor.removedTextBackground"]) ?? error.withAlphaComponent(0.18)
        warning = Self.color(in: colors, keys: ["editorWarning.foreground", "terminal.ansiYellow", "notificationsWarningIcon.foreground"]) ?? defaultWarning
        let diffDeletionAlpha = diffDeletionBackground.resolvedAlphaComponent
        errorBackground = diffDeletionBackground.withAlphaComponent(max(diffDeletionAlpha, 0.14))
    }

    private static func color(in colors: [String: String], keys: [String]) -> PlatformColor? {
        for key in keys {
            if let value = colors[key], let color = PlatformColor(cssHex: value) {
                return color
            }
        }

        return nil
    }

    private static func color(in colors: [String: String], keys: [String], meetingMinimumContrast minimumContrast: CGFloat, against background: PlatformColor) -> PlatformColor? {
        for key in keys {
            guard let value = colors[key], let color = PlatformColor(cssHex: value) else { continue }
            if color.contrastRatio(against: background) >= minimumContrast {
                return color
            }
        }

        return nil
    }
}

extension String {
    var humanizedThemeName: String {
        split(separator: "-")
            .map { component in
                component.isEmpty ? "" : component.prefix(1).uppercased() + component.dropFirst()
            }
            .joined(separator: " ")
    }
}

#if os(macOS)
private extension PlatformColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init?(cssHex: String) {
        let trimmed = cssHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }

        let hex = String(trimmed.dropFirst())
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        switch hex.count {
        case 6:
            self.init(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        case 8:
            self.init(
                srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
                green: CGFloat((value >> 16) & 0xFF) / 255,
                blue: CGFloat((value >> 8) & 0xFF) / 255,
                alpha: CGFloat(value & 0xFF) / 255
            )
        default:
            return nil
        }
    }

    static func fromRGBA(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        PlatformColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }
}
#else
private extension PlatformColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init?(cssHex: String) {
        let trimmed = cssHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }

        let hex = String(trimmed.dropFirst())
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        switch hex.count {
        case 6:
            self.init(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        case 8:
            self.init(
                red: CGFloat((value >> 24) & 0xFF) / 255,
                green: CGFloat((value >> 16) & 0xFF) / 255,
                blue: CGFloat((value >> 8) & 0xFF) / 255,
                alpha: CGFloat(value & 0xFF) / 255
            )
        default:
            return nil
        }
    }

    static func fromRGBA(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        PlatformColor(red: red, green: green, blue: blue, alpha: alpha)
    }

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
}
#endif

private extension PlatformColor {
    func shiftedSurface(isDark: Bool, amount: CGFloat) -> PlatformColor {
        guard let components = rgbaComponents else { return self }
        let target: CGFloat = isDark ? 1 : 0

        return PlatformColor.fromRGBA(
            red: components.red + (target - components.red) * amount,
            green: components.green + (target - components.green) * amount,
            blue: components.blue + (target - components.blue) * amount,
            alpha: components.alpha
        )
    }

    var resolvedAlphaComponent: CGFloat {
        rgbaComponents?.alpha ?? 1
    }

    func contrastRatio(against background: PlatformColor) -> CGFloat {
        let foreground = composited(over: background)
        let foregroundLuminance = foreground.relativeLuminance
        let backgroundLuminance = background.relativeLuminance
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func composited(over background: PlatformColor) -> PlatformColor {
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

    private var relativeLuminance: CGFloat {
        guard let color = rgbaComponents else { return 0 }

        func channel(_ value: CGFloat) -> CGFloat {
            if value <= 0.03928 {
                return value / 12.92
            }

            return pow((value + 0.055) / 1.055, 2.4)
        }

        let red = channel(color.red)
        let green = channel(color.green)
        let blue = channel(color.blue)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
