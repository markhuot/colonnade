import AppKit
import Foundation
import SwiftUI
import Textual

private final class ThemeBundleMarker: NSObject {}

private struct ThemeTokenPropertyGroup: TextProperty {
    let properties: [AnyTextProperty]

    func apply(in attributes: inout AttributeContainer, environment: TextEnvironmentValues) {
        for property in properties {
            property.apply(in: &attributes, environment: environment)
        }
    }
}

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
        self.orderedThemeIDs
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
            highlighterTheme: makeHighlighterTheme(document: document, palette: palette),
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

    private static func makeHighlighterTheme(document: TextMateThemeDocument, palette: TextMateThemePalette) -> StructuredText.HighlighterTheme {
        var tokenProperties: [StructuredText.HighlighterTheme.TokenType: AnyTextProperty] = [:]

        for rule in document.tokenColors {
            let tokenTypes = Set(rule.scopes.flatMap(tokenTypes(for:)))
            guard !tokenTypes.isEmpty else { continue }

            let property = tokenProperty(from: rule.settings)
            for tokenType in tokenTypes {
                tokenProperties[tokenType] = property
            }
        }

        return StructuredText.HighlighterTheme(
            foregroundColor: DynamicColor(Color(nsColor: palette.codeForeground)),
            backgroundColor: DynamicColor(Color(nsColor: palette.codeBlockBackground)),
            tokenProperties: tokenProperties
        )
    }

    private static func tokenProperty(from settings: TextMateTokenSettings) -> AnyTextProperty {
        var properties: [AnyTextProperty] = []

        if let foreground = settings.foreground.flatMap(NSColor.init(cssHex:)) {
            properties.append(AnyTextProperty(.foregroundColor(DynamicColor(Color(nsColor: foreground)))))
        }

        if let background = settings.background.flatMap(NSColor.init(cssHex:)) {
            properties.append(AnyTextProperty(.backgroundColor(DynamicColor(Color(nsColor: background)))))
        }

        let fontStyles = Set(
            (settings.fontStyle ?? "")
                .split(whereSeparator: \.isWhitespace)
                .map { $0.lowercased() }
        )

        if fontStyles.contains("italic") {
            properties.append(AnyTextProperty(.italic))
        }

        if fontStyles.contains("bold") {
            properties.append(AnyTextProperty(.bold))
        }

        if fontStyles.contains("underline") {
            properties.append(AnyTextProperty(.underlineStyle(.single)))
        }

        if fontStyles.contains("strikethrough") {
            properties.append(AnyTextProperty(.strikethroughStyle(.single)))
        }

        return AnyTextProperty(ThemeTokenPropertyGroup(properties: properties))
    }

    private static func tokenTypes(for scope: String) -> [StructuredText.HighlighterTheme.TokenType] {
        let scope = scope.lowercased()
        var tokens: Set<StructuredText.HighlighterTheme.TokenType> = []

        if scope.contains("comment") {
            tokens.insert(.comment)
        }
        if scope.contains("doc") && scope.contains("comment") {
            tokens.insert(.docComment)
        }
        if scope.contains("block") && scope.contains("comment") {
            tokens.insert(.blockComment)
        }
        if scope.contains("keyword") || scope.contains("storage") || scope.contains("control") {
            tokens.insert(.keyword)
        }
        if scope.contains("builtin") || scope.contains("support.") {
            tokens.insert(.builtin)
        }
        if scope.contains("entity.name.class") || scope.contains("entity.name.type") || scope.contains("support.class") || scope.contains("support.type") {
            tokens.insert(.className)
        }
        if scope.contains("entity.name.function") || scope.contains("meta.function") || scope.contains("support.function") || scope.contains("variable.function") || scope.contains("method") {
            tokens.insert(.function)
        }
        if scope.contains("function-definition") || (scope.contains("function") && scope.contains("definition")) {
            tokens.insert(.functionDefinition)
        }
        if scope.contains("boolean") {
            tokens.insert(.boolean)
        }
        if scope.contains("numeric") || scope.contains("number") {
            tokens.insert(.number)
        }
        if scope.contains("regexp") || scope.contains("regex") {
            tokens.insert(.regex)
        }
        if scope.contains("url") || scope.contains("link") {
            tokens.insert(.url)
        }
        if scope.contains("string") {
            tokens.insert(.string)
        }
        if scope.contains("character") || scope.contains("char") {
            tokens.insert(.char)
        }
        if scope.contains("symbol") {
            tokens.insert(.symbol)
        }
        if scope.contains("operator") {
            tokens.insert(.operator)
        }
        if scope.contains("variable.other.constant") || scope.contains("variable.constant") || scope.contains("enum") || scope.contains("constant") {
            tokens.insert(.constant)
        }
        if scope.contains("parameter") || scope.contains("variable") {
            tokens.insert(.variable)
        }
        if scope.contains("property-name") || scope.contains("property") || scope.contains("field") || scope.contains("meta.object-literal.key") {
            tokens.insert(.property)
        }
        if scope.contains("punctuation") {
            tokens.insert(.punctuation)
        }
        if scope.contains("important") {
            tokens.insert(.important)
        }
        if scope.contains("entity.name.tag") || scope.contains("meta.tag") {
            tokens.insert(.tag)
        }
        if scope.contains("attribute-name") || scope.contains("attr-name") {
            tokens.insert(.attributeName)
        }
        if scope.contains("attribute-value") || scope.contains("attr-value") {
            tokens.insert(.attributeValue)
        }
        if scope.contains("namespace") {
            tokens.insert(.namespace)
        }
        if scope.contains("prolog") {
            tokens.insert(.prolog)
        }
        if scope.contains("doctype") {
            tokens.insert(.doctype)
        }
        if scope.contains("cdata") {
            tokens.insert(.cdata)
        }
        if scope.contains("entity") {
            tokens.insert(.entity)
        }
        if scope.contains("atrule") {
            tokens.insert(.atrule)
        }
        if scope.contains("selector") {
            tokens.insert(.selector)
        }
        if scope.contains("markup.inserted") || scope.contains("diff.plus") || scope.contains("inserted") || scope.contains("added") {
            tokens.insert(.inserted)
        }
        if scope.contains("markup.deleted") || scope.contains("diff.minus") || scope.contains("deleted") || scope.contains("removed") {
            tokens.insert(.deleted)
        }
        if scope.contains("preprocessor") {
            tokens.insert(.preprocessor)
        }
        if scope.contains("directive") {
            tokens.insert(.directive)
        }
        if scope.contains("annotation") || scope.contains("attribute") {
            tokens.insert(.attribute)
        }
        if scope.contains("label") {
            tokens.insert(.label)
        }
        if scope.contains(" nil") || scope.hasSuffix(".nil") || scope.contains(".nil.") {
            tokens.insert(.nil)
        }
        if scope.contains("interpolation-punctuation") {
            tokens.insert(.interpolationPunctuation)
        }
        if scope.contains("interpolation") {
            tokens.insert(.interpolation)
        }
        if tokens.isEmpty {
            tokens.insert(.plain)
        }

        return Array(tokens)
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
    let windowBackground: NSColor
    let surfaceBackground: NSColor
    let mutedSurfaceBackground: NSColor
    let inputBackground: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let border: NSColor
    let accent: NSColor
    let accentSubtleBackground: NSColor
    let assistantBubble: NSColor
    let userBubble: NSColor
    let codeForeground: NSColor
    let codeBlockBackground: NSColor
    let toolCardBackground: NSColor
    let diffAddition: NSColor
    let diffAdditionBackground: NSColor
    let diffDeletion: NSColor
    let diffDeletionBackground: NSColor
    let warning: NSColor
    let error: NSColor
    let errorBackground: NSColor
    let positive: NSColor

    init(document: TextMateThemeDocument) {
        let themeType = document.type?.lowercased()
        let isDark = themeType == "dark"
        let colors = document.colors

        colorScheme = switch themeType {
        case "light": .light
        case "dark": .dark
        default: nil
        }

        let defaultWindow = isDark ? NSColor(hex: 0x111111) : NSColor(hex: 0xFFFFFF)
        let defaultForeground = isDark ? NSColor(hex: 0xE6E6E6) : NSColor(hex: 0x1F2328)
        let defaultAccent = isDark ? NSColor(hex: 0x61AFEF) : NSColor(hex: 0x0B6BDE)
        let defaultPositive = isDark ? NSColor(hex: 0x3FB950) : NSColor(hex: 0x1A7F37)
        let defaultWarning = isDark ? NSColor(hex: 0xE3B341) : NSColor(hex: 0x9A6700)
        let defaultError = isDark ? NSColor(hex: 0xF85149) : NSColor(hex: 0xCF222E)

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

    private static func color(in colors: [String: String], keys: [String]) -> NSColor? {
        for key in keys {
            if let value = colors[key], let color = NSColor(cssHex: value) {
                return color
            }
        }

        return nil
    }

    private static func color(in colors: [String: String], keys: [String], meetingMinimumContrast minimumContrast: CGFloat, against background: NSColor) -> NSColor? {
        for key in keys {
            guard let value = colors[key], let color = NSColor(cssHex: value) else { continue }
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

private extension NSColor {
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

    func shiftedSurface(isDark: Bool, amount: CGFloat) -> NSColor {
        let target = isDark ? NSColor.white : NSColor.black
        return blended(withFraction: amount, of: target) ?? self
    }

    var resolvedAlphaComponent: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 1 }
        return color.alphaComponent
    }

    func contrastRatio(against background: NSColor) -> CGFloat {
        let foreground = composited(over: background)
        let foregroundLuminance = foreground.relativeLuminance
        let backgroundLuminance = background.relativeLuminance
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func composited(over background: NSColor) -> NSColor {
        guard
            let foreground = usingColorSpace(.sRGB),
            let background = background.usingColorSpace(.sRGB)
        else {
            return self
        }

        let alpha = foreground.alphaComponent
        if alpha >= 1 { return foreground }

        return NSColor(
            srgbRed: foreground.redComponent * alpha + background.redComponent * (1 - alpha),
            green: foreground.greenComponent * alpha + background.greenComponent * (1 - alpha),
            blue: foreground.blueComponent * alpha + background.blueComponent * (1 - alpha),
            alpha: 1
        )
    }

    private var relativeLuminance: CGFloat {
        guard let color = usingColorSpace(.sRGB) else { return 0 }

        func channel(_ value: CGFloat) -> CGFloat {
            if value <= 0.03928 {
                return value / 12.92
            }

            return pow((value + 0.055) / 1.055, 2.4)
        }

        let red = channel(color.redComponent)
        let green = channel(color.greenComponent)
        let blue = channel(color.blueComponent)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
