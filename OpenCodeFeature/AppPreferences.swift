import Combine
import Foundation

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

enum ThinkingVisibilityPreferences {
    static let showsThinkingKey = "showsThinking"

    static func showsThinking(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: showsThinkingKey) != nil else { return true }
        return defaults.bool(forKey: showsThinkingKey)
    }

    static func setShowsThinking(_ showsThinking: Bool, defaults: UserDefaults = .standard) {
        defaults.set(showsThinking, forKey: showsThinkingKey)
    }
}

enum RecentRemoteConnectionsPreferences {
    static let recentRemoteConnectionsKey = "recentRemoteConnections"
    private static let maximumConnectionCount = 5

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        let storedValues = defaults.stringArray(forKey: recentRemoteConnectionsKey) ?? []
        return normalize(storedValues)
    }

    @discardableResult
    static func remember(_ urlText: String, defaults: UserDefaults = .standard) -> [String] {
        let trimmedURLText = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURLText.isEmpty else {
            return load(from: defaults)
        }

        let updatedConnections = normalize([trimmedURLText] + load(from: defaults))
        defaults.set(updatedConnections, forKey: recentRemoteConnectionsKey)
        return updatedConnections
    }

    private static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var normalizedValues: [String] = []

        for value in values {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty, seen.insert(trimmedValue).inserted else { continue }
            normalizedValues.append(trimmedValue)

            if normalizedValues.count == maximumConnectionCount {
                break
            }
        }

        return normalizedValues
    }
}
