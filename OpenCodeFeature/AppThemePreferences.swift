import Foundation

struct OpenCodeThemeID: RawRepresentable, Hashable, Codable, Identifiable, Sendable {
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
}

@MainActor
final class ThemeController: ObservableObject {
    enum Constants {
        static let selectedThemeKey = "selectedTheme"
    }

    @Published private(set) var selectedThemeID: OpenCodeThemeID

    private let defaults: UserDefaults
    private let supportsTheme: (OpenCodeThemeID) -> Bool

    init(
        defaults: UserDefaults = .standard,
        supportsTheme: @escaping (OpenCodeThemeID) -> Bool = { _ in true }
    ) {
        self.defaults = defaults
        self.supportsTheme = supportsTheme

        if let rawValue = defaults.string(forKey: Constants.selectedThemeKey) {
            let storedTheme = OpenCodeThemeID(rawValue: rawValue)
            selectedThemeID = supportsTheme(storedTheme) ? storedTheme : .native
        } else {
            selectedThemeID = .native
        }
    }

    func selectTheme(_ themeID: OpenCodeThemeID) {
        guard supportsTheme(themeID), selectedThemeID != themeID else { return }
        selectedThemeID = themeID
        defaults.set(themeID.rawValue, forKey: Constants.selectedThemeKey)
    }
}
