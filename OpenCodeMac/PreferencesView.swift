import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var themeController: ThemeController
    @EnvironmentObject private var modelPreferencesController: ModelPreferencesController
    @EnvironmentObject private var localServerPreferencesController: LocalServerPreferencesController
    @StateObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    init() {
        _appState = StateObject(wrappedValue: OpenCodeAppModelFactory.makePreferencesAppModel())
    }

    private var defaultModelSelectionKey: String {
        let options = appState.availableModelOptions()
        guard let reference = modelPreferencesController.preferredDefaultModelReference else { return "" }
        return options.contains(where: { $0.reference == reference }) ? reference.key : ""
    }

    var body: some View {
        let modelOptions = appState.availableModelOptions()

        Form {
            Picker("Theme", selection: Binding(
                get: { themeController.selectedThemeID },
                set: { themeController.selectTheme($0) }
            )) {
                ForEach(OpenCodeThemeID.allCases) { themeID in
                    Text(themeID.displayName)
                        .tag(themeID)
                }
            }
            .pickerStyle(.menu)

            Text("Native keeps the current macOS window and text colors. TextMate themes currently update the window background and text colors.")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Default Model", selection: Binding(
                get: { defaultModelSelectionKey },
                set: { newValue in
                    let reference = ModelReference(key: newValue)
                    modelPreferencesController.setPreferredDefaultModelReference(reference)
                    appState.setPreferredDefaultModel(reference)
                }
            )) {
                Text("Use Server Default")
                    .tag("")

                ForEach(modelOptions) { option in
                    Text(option.preferenceLabel)
                        .tag(option.reference.key)
                }
            }
            .pickerStyle(.menu)

            if modelOptions.isEmpty {
                Text("No models are available yet. Open a workspace or wait for the provider catalog to load.")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("New sessions prefer your local default model when there is no recent model for that session. Hold Option while choosing a model in a session to update this preference at the same time.")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Opencode Path", text: Binding(
                get: { localServerPreferencesController.opencodeExecutablePath },
                set: { localServerPreferencesController.setOpencodeExecutablePath($0) }
            ))
            .textFieldStyle(.roundedBorder)

            Text("Used to start the local headless server when you open a local directory. Defaults to ~/.bun/bin/opencode.")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 460)
        .background(theme.windowBackground)
        .themedWindow(theme)
        .task {
            appState.configurePreferredDefaultModelPersistence(
                provider: { modelPreferencesController.preferredDefaultModelReference },
                setter: { modelPreferencesController.setPreferredDefaultModelReference($0) }
            )
            await appState.bootstrapIfNeeded()
        }
        .onReceive(WorkspaceCommandCenter.shared.$currentConnection.compactMap { $0 }) { connection in
            Task {
                await appState.updatePreferencesConnection(connection)
            }
        }
    }
}
