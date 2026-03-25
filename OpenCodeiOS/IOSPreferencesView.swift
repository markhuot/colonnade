import SwiftUI

struct IOSPreferencesView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @EnvironmentObject private var themeController: ThemeController
    @EnvironmentObject private var modelPreferencesController: ModelPreferencesController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openCodeTheme) private var theme
    @AppStorage(ThinkingVisibilityPreferences.showsThinkingKey) private var showsThinking = true

    private var defaultModelSelectionKey: String {
        let options = appState.availableModelOptions()
        guard let reference = modelPreferencesController.preferredDefaultModelReference else { return "" }
        return options.contains(where: { $0.reference == reference }) ? reference.key : "" }

    var body: some View {
        let modelOptions = appState.availableModelOptions()

        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { themeController.selectedThemeID },
                        set: { themeController.selectTheme($0) }
                    )) {
                        ForEach(OpenCodeThemeID.allCases) { themeID in
                            Text(themeID.displayName)
                                .tag(themeID)
                        }
                    }

                    Text("Native follows the built-in iOS colors for the app interface. TextMate themes match the macOS theme list.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }

                Section("Sessions") {
                    Picker("Default Model", selection: Binding(
                        get: { defaultModelSelectionKey },
                        set: { newValue in
                            let reference = newValue.isEmpty ? nil : ModelReference(key: newValue)
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

                    if modelOptions.isEmpty {
                        Text("No models are available yet. Open a workspace or wait for the provider catalog to load.")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                    } else {
                        Text("New sessions use this model when there is no recent model saved for that session.")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Toggle("Hide Thinking", isOn: Binding(
                        get: { !showsThinking },
                        set: { showsThinking = !$0 }
                    ))

                    Text("Hides assistant thinking blocks in session transcripts, matching the macOS View menu option.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.windowBackground)
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
