import SwiftUI

/// Settings ▸ Sessions: the library plus what capture and restore leave alone.
struct SessionsSettingsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var query = ""
    @State private var pendingDeletion: Session?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureCommandsSection(owner: .sessions, anchor: .sessionsCommands)
            library
            Section {
                Toggle(isOn: $settings.sessionsQuitOnClear) {
                    SettingsRowTitle(.sessionsBehaviour, "Quit when clearing")
                    Text("Off hides every app instead, so nothing needs reopening.")
                }
                SettingsRow(
                    title: "Ignored Applications",
                    subtitle: "Never captured, hidden or quit.",
                    anchor: .sessionsBehaviour
                ) {
                    EmptyView()
                }
                DisabledApplicationsList(bundleIDs: $settings.sessionsIgnoredApps)
                SettingsRow(
                    title: "Window Geometry",
                    subtitle: "These apps reopen but keep their windows where they are.",
                    anchor: .sessionsBehaviour
                ) {
                    EmptyView()
                }
                DisabledApplicationsList(bundleIDs: $settings.sessionsGeometryOptOut)
            } header: {
                SettingsSectionHeader(.sessionsBehaviour)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.sessions)
        .alert(item: $pendingDeletion) { session in
            Alert(
                title: Text("Delete “\(session.name)”?"),
                message: Text("Its launcher references go with it."),
                primaryButton: .destructive(Text("Delete")) {
                    core.sessionCoordinator.deleteSession(id: session.id)
                },
                secondaryButton: .cancel())
        }
    }

    private var library: some View {
        Section {
            if !store.sessions.isEmpty, store.sessions.count > 6 {
                SettingsFilterField(prompt: "Search sessions…", query: $query)
            }
            if results.isEmpty {
                Text(store.sessions.isEmpty ? "Save the apps you have open, restore them later." : "No session matches.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { session in
                    SessionSettingsRow(
                        session: session,
                        onRename: { core.sessionCoordinator.renameSession(id: session.id) },
                        onRestore: { core.sessionCoordinator.restoreSession(id: session.id) },
                        onDelete: { pendingDeletion = session })
                }
            }
            Button {
                core.sessionCoordinator.saveCurrentSession()
            } label: {
                SettingsRowTitle(.sessionsSessions, "Save Current Session")
            }
        } header: {
            SettingsSectionHeader(.sessionsSessions)
        }
    }

    private var results: [Session] {
        guard !query.isEmpty else { return store.sessions }
        return store.sessions.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

private struct SessionSettingsRow: View {
    let session: Session
    let onRename: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        SettingsRow(title: session.name, subtitle: session.summary) {
            SymbolImage(name: Session.sfSymbol, size: 13)
        } trailing: {
            Button(action: onRestore) {
                Image(systemName: "play")
            }
            .buttonStyle(.plain)
            .help("Restore this session")
            .accessibilityLabel("Restore \(session.name)")
            Button(action: onRename) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Rename")
            .accessibilityLabel("Rename \(session.name)")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help("Delete")
            .accessibilityLabel("Delete \(session.name)")
            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel("Show \(session.name) in launcher")
        }
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(AppEntry(session)) },
            set: { visibility.setItemVisible($0, for: AppEntry(session)) })
    }
}
