import AppKit

/// Owns sessions: the library, the save/restore funnels and the clear-workspace gate.
@MainActor
final class SessionCoordinator {
    private let store: SessionStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private unowned let core: AppCore
    private var run: Task<Void, Never>?

    init(
        store: SessionStore, settings: AppSettings, appIndex: AppIndex,
        favorites: FavoritesStore, visibility: VisibilityStore, ranking: LauncherRankingStore,
        aliases: AliasStore, paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator, core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
    }

    func applySessionsPresence() {
        appIndex.setSessions(store.sessions)
        let commands: Set<CommandID> = [.saveSession, .sessionsBrowse, .restoreLastSession]
        appIndex.setCommandsVisible(commands, true)
    }

    func saveCurrentSession() {
        let entries = SessionSnapshotter.captureCurrent(
            ignored: Set(settings.sessionsIgnoredApps),
            geometryOptOut: Set(settings.sessionsGeometryOptOut))
        guard !entries.isEmpty else {
            core.showMessage("No apps to save", tone: .neutral)
            return
        }
        let suggested = SessionStore.uniqueName(from: "Session", among: store.sessions)
        Task {
            guard
                let name = await core.promptForText(
                    title: "Save Session", message: "\(entries.count) apps will be saved.",
                    symbol: Session.sfSymbol, initial: suggested, confirmTitle: "Save")
            else { return }
            do {
                let saved = try store.create(name: name, entries: entries)
                applySessionsPresence()
                core.showMessage("Saved \(saved.name)")
            } catch {
                await core.showNotice(
                    title: "Couldn't Save the Session",
                    message: (error as? SessionValidationError)?.errorDescription
                        ?? "The session could not be saved.",
                    symbol: Session.sfSymbol, tone: .danger)
            }
        }
    }

    func restoreSession(id: UUID) {
        guard let session = store.session(id: id) else { return }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        run?.cancel()
        run = Task { [weak self] in
            guard let self else { return }
            let outcome = await SessionRunner.restore(
                session, gap: CGFloat(settings.windowGap),
                geometryOptOut: Set(settings.sessionsGeometryOptOut),
                ignoring: Set(settings.sessionsIgnoredApps))
            store.noteUsed(id: session.id)
            report(outcome, for: session)
        }
    }

    func restoreLastSession() {
        guard let session = store.lastSession else {
            core.showMessage("No saved sessions", tone: .neutral)
            return
        }
        restoreSession(id: session.id)
    }

    func deleteSession(id: UUID) {
        guard let removed = store.remove(id: id) else { return }
        removeSessionReferences(entryIDs: [removed.entryID])
        applySessionsPresence()
    }

    func renameSession(id: UUID) {
        guard let session = store.session(id: id) else { return }
        Task {
            guard
                let name = await core.promptForText(
                    title: "Rename Session", message: nil, symbol: Session.sfSymbol,
                    initial: session.name, confirmTitle: "Rename")
            else { return }
            do {
                try store.rename(id: id, to: name)
                applySessionsPresence()
            } catch {
                await core.showNotice(
                    title: "Couldn't Rename the Session",
                    message: (error as? SessionValidationError)?.errorDescription
                        ?? "The session could not be renamed.",
                    symbol: Session.sfSymbol, tone: .danger)
            }
        }
    }

    func showSessions() {
        paletteCoordinator.togglePalette(mode: .sessions)
    }

    func editSessions() {
        settingsCoordinator.showSettings(tab: .sessions)
    }

    func clearWorkspace(quit: Bool? = nil) {
        let quits = quit ?? settings.sessionsQuitOnClear
        if quits {
            quitAll()
        } else {
            let hidden = SessionRunner.hideExtras(
                notIn: [], ignoring: Set(settings.sessionsIgnoredApps))
            core.showMessage(hidden == 0 ? "Nothing to hide" : "Hid \(hidden) applications")
        }
    }

    func prepareForTermination() {
        run?.cancel()
        run = nil
    }

    private func quitAll() {
        let targets = SessionRunner.quitTargets(ignoring: Set(settings.sessionsIgnoredApps))
        guard !targets.isEmpty else {
            core.showMessage("Nothing to quit", tone: .neutral)
            return
        }
        Task {
            guard
                await core.confirm(
                    title: targets.count == 1
                        ? "Quit 1 application?" : "Quit \(targets.count) applications?",
                    message: "Applications with unsaved changes will ask you to save.",
                    symbol: Session.sfSymbol, confirmTitle: "Quit All")
            else { return }
            for app in targets { app.terminate() }
            core.showMessage(
                targets.count == 1 ? "Quit 1 application" : "Quit \(targets.count) applications")
        }
    }

    private func report(_ outcome: SessionRunner.RestoreOutcome, for session: Session) {
        if outcome.relaunched == 0, outcome.hidden == 0, outcome.placed == 0 {
            core.showMessage("“\(session.name)” is already in place", tone: .neutral)
            return
        }
        var parts: [String] = []
        if outcome.relaunched > 0 {
            parts.append(
                outcome.relaunched == 1 ? "1 app reopened" : "\(outcome.relaunched) apps reopened")
        }
        if outcome.hidden > 0 {
            parts.append(outcome.hidden == 1 ? "1 app hidden" : "\(outcome.hidden) apps hidden")
        }
        if let skipped = outcome.skippedDetails { parts.append(skipped) }
        let detail = parts.isEmpty ? "Restored" : parts.joined(separator: " · ")
        core.showMessage("\(session.name) — \(detail)", tone: .neutral)
    }

    private func removeSessionReferences(entryIDs: Set<String>) {
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs { ranking.reset(itemKey: entryID) }
    }
}
