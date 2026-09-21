import SwiftUI

/// Migration presets, below the custom sizes: one choice loads another app's defaults.
struct WindowCommandPresetSection: View {
    @Environment(WindowCommandCoordinator.self) private var coordinator

    var body: some View {
        Section {
            SettingsRow(
                title: "Shortcut presets",
                subtitle: "Load another app's window shortcuts.",
                anchor: .windowManagementPresets
            ) {
                Menu("Load preset") {
                    ForEach(WindowCommandPreset.allCases, id: \.self) { preset in
                        Button(preset.title + "…") {
                            Task { await coordinator.applyPreset(preset) }
                        }
                    }
                }
            }
            SettingsRow(
                title: "Clear all shortcuts",
                subtitle: "Removes every window-management shortcut.",
                anchor: .windowManagementPresets
            ) {
                Button("Clear…") {
                    Task { await coordinator.clearWindowCommandShortcuts() }
                }
            }
        } header: {
            SettingsSectionHeader(.windowManagementPresets)
        }
    }
}
