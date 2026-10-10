# Plan: Workspace Sessions (Later-inspired) for Tinycast

## Context

Bring https://github.com/alyssaxuu/later ("Save all your Mac apps for later with one click") to Tinycast as a native feature. Later's core loop: capture the current set of Mac apps as a named session → hide or quit them all (clear workspace / save battery / tidy before screen-share) → restore the session later with one click → optionally schedule apps to reopen after a delay → manage via menu-bar, keyboard shortcuts, ignore-list and terminate-vs-hide setting.

Tinycast already owns most primitives (RunningAppsMonitor, AppLauncher quit/launch/toggle, WindowLayoutStore save/restore pattern, WindowLayoutRunner capture/run, coordinators, launcher commands, global hotkeys, Settings panes). No new permission needed for hide/terminate/relaunch via NSWorkspace; geometry capture/reapply reuses Window Management's Accessibility grant (no second permission). Target: macOS 26+, Swift 6, zero dependencies, latest-only posture.

## Decisions (locked with user)

1. **Library**: named multi-session library (Later parity), not a single stash slot. Save-current-as-named, rename, delete, restore-by-name, restore-last.
2. **Clear-workspace default = hide; quit requires confirm.** Hide-all is the safe default; quit-all goes through `DialogController` confirm first (graceful terminate, unsaved-work sheets respected).
3. **Restore = relaunch + hide.** Relaunch session apps that aren't running; hide running regular-policy apps not in the session; then reapply geometry. No focus-stealing beyond the layout's frontmost rule.
4. **Scheduling deferred.** No reopen timers in v1.
5. **Launcher is the main surface**, with a full clipboard-history-style interface: session list beside detail preview (app rows, icons, saved-at metadata, entry count).
6. **Capture + reapply WindowLayout geometry**, with per-app opt-out through Settings (bundleID exclusion list for geometry only — the app still relaunches, its windows just aren't moved).
7. **Backup split: sessions excluded, exclusion lists carried.** The sessions library never rides a backup (no `sessions` field on `SettingsBackup`, never gathered/applied). The ignore-list and geometry-opt-out lists ARE carried, as ordinary `AppSettings` keys in the configuration backup — same shape as `menuSearchDisabledApps` / `clipboardDisabledApps`: narrowing lists that grant no permission class.

## Approach (recommended)

New `Tinycast/Features/Sessions/` feature following the mature Model/Service/UI + Settings split:

- **Model (pure, Foundation-only, harness-compiled):** `Session` (id, name, createdAt, entries), `SessionEntry` (bundleID + display name + optional `WindowLayoutEntry` geometry snapshot), `SessionStore` (named library, JSON in UserDefaults, clock-injected `now`, sanitize-on-load like `WindowLayoutStore`). The ignore-list and geometry-opt-out are NOT store state — they are `AppSettings` keys (`sessionsIgnoredApps`, `sessionsGeometryOptOut`), so they automatically ride the configuration backup via `SettingsData` + `SettingsBackupCoverage`, exactly like `menuSearchDisabledApps`.
- **Service (effects):** `SessionSnapshotter` (capture `NSWorkspace.runningApplications` regular-policy apps minus Finder/Tinycast/self, filtered by ignore-list; geometry via the same capture path `WindowLayoutRunner.captureCurrentWindows()` uses, minus opt-out apps) + `SessionRunner` (hide-all via `NSRunningApplication.hide()`, quit-all via `AppLauncher.quitAllTargets()`-style terminate with confirm, restore via `AppLauncher.launch` for missing + hide for extras, then geometry reapply through `WindowLayoutPlan`/`WindowPlacementEngine` — never touching `WindowActionMemory`, per the layouts invariant).
- **UI — clipboard-history pattern:** new `PaletteScreen`-conforming `SessionsScreen` (session list + detail preview, `activate`/`secondary`/`delete` chords mirroring `ClipboardScreen`) + `SessionCoordinator` funnel (save/rename/delete/restore/clear-workspace, Dialog confirm for quit, HUD report for save/restore). Launcher commands: Save session, Sessions (browse), Restore last session.
- **Wire once in `AppCore.start()`; no competing singleton.** New `SettingsTab.sessions` pane owning its commands via `ownedCommands`; new `AppEntry.Kind` case (e.g. `.session`) with `VisibilityStore` master switch; global hotkeys via HotKeyManager (generic commands ride the existing `commands` hotkey-backup map — no per-session hotkey backup, unlike `windowLayouts`).
- **Backup split:** `SettingsBackup` gains the two exclusion-list `SettingsData` fields (with `SettingsBackupCoverage` mirror entries — the harness fails otherwise) and NO sessions field; `BackupComposer`/`BackupBundle` untouched.

Deliberately **out of scope for v1**: scheduled reopen timers, document-level/Finder-window restore.

## Files to modify

- NEW: `Tinycast/Features/Sessions/Model/Session{,Entry,Store}.swift` (+ harness `Tests/sessions-test.swift`)
- NEW: `Tinycast/Features/Sessions/Service/SessionSnapshotter.swift`, `SessionRunner.swift` (or one `SessionService`)
- NEW: `Tinycast/Features/Sessions/UI/SessionCoordinator.swift` + `SessionsScreen.swift` (+ actions menu, detail preview views)
- NEW: `Tinycast/Features/Sessions/Settings/SessionsSettingsView.swift` (session list, ignore-list editor, geometry opt-out editor, hide-vs-quit default)
- MOD: `Tinycast/App/AppCore.swift` (own store + coordinator, wire in `start()`)
- MOD: `Tinycast/Features/Settings/SettingsTab.swift` (new `.sessions` case + `ownedCommands`), `Launcher/Model/CommandID.swift` (save/browse/restore-last), `Launcher/Service/AppIndex.swift` (`AppEntry.Kind` case), `Launcher/Service/VisibilityStore.swift`, `project.yml` (+ `xcodegen generate`)
- MOD (backup, lists only): `Tinycast/Features/Settings/AppSettings.swift` + `AppSettingsKey.swift` (new `sessionsIgnoredApps`, `sessionsGeometryOptOut` keys), `Backup/Model/SettingsBackup.swift` (two `SettingsData` fields, NO sessions field), `Backup/Model/SettingsBackupCoverage.swift` (two mirror entries)
- EXPLICITLY NOT MODIFIED: `Backup/Model/BackupCategory.swift` (no new category — lists ride `.configuration`, sessions ride nothing), `Backup/Service/BackupComposer.swift`, `DesignSystem/Scrolling/EdgeDissolve.swift`, `ThinScrollbar.swift`, `EmojiData.generated.swift` and other generated files
- DOCS: `docs/features/sessions.md` (new, with Invariants), `README.md` feature bullet if shipped

## Reuse (found in codebase)

- `Tinycast/Features/Launcher/Service/RunningAppsMonitor.swift` — live running set + change notifications
- `Tinycast/Features/Launcher/Service/AppLauncher.swift` — `launch/toggle/quit/quitAllTargets` (Finder exclusion, graceful terminate, relaunch guard, quit-awaiting-exit)
- `Tinycast/Features/WindowManagement/Model/WindowLayoutStore.swift` — reference for JSON-backed named-library store pattern (sanitize-on-load, UserDefaults)
- `Tinycast/Features/WindowManagement/Model/WindowLayout{,Entry,Plan}.swift` + `Service/WindowLayoutRunner.swift` (`captureCurrentWindows`, `run`, 10s launch deadline, `WindowActionMemory` exclusion, frontmost-by-construction) — geometry capture/reapply; `WindowPlacementEngine`/`AXScreens` for resolve
- `Tinycast/Features/WindowManagement/Service/WindowInventory.swift` + `AXWindowAccess.swift` — what-is-on-screen snapshot + AX writes
- `Tinycast/Features/SystemActions/UI/SystemActionCoordinator.swift` + `Service/SystemActionRunner.swift` — Quit All confirm-then-terminate funnel, `hideOtherApps/unhideAllApps` actions
- `Tinycast/Features/Clipboard/UI/ClipboardScreen.swift` + `ClipboardCoordinator.swift` (`PaletteScreen` rows/actions/activate/secondary/delete chords, `applyEnabled` pattern) — direct template for `SessionsScreen`
- `Tinycast/Palette/PaletteScreen.swift` + `RootPaletteView.swift` — screen protocol the sessions browser plugs into
- `Tinycast/Features/Launcher/Model/CommandCatalog.swift` + `CommandID.swift` + `Launcher/UI/LauncherCoordinator.swift` — how commands reach the palette
- `Tinycast/Features/Backup/Model/SettingsBackup.swift` (`SettingsData` + per-library fields like `windowLayouts`) + `SettingsBackupCoverage.swift` (mirror rule the harness enforces) — backup shape; `menuSearchDisabledApps`/`clipboardDisabledApps` as the carried exclusion-list precedent
- `Tinycast/App/AppCore.swift` — sole composition root / wiring point

## Steps (checklist)

- [ ] Model: `Session`/`SessionEntry` value types + `SessionStore` CRUD/sanitize (Sendable, clock-injected, Foundation-only)
- [ ] Harness: `Tests/sessions-test.swift` compiling shipped Model sources verbatim (sanitize, dedupe by bundleID, opt-out filtering, unique naming)
- [ ] Service: snapshotter (regular-policy capture, Finder/self exclusion, ignore-list filter, geometry capture minus opt-outs) + runner (hide-all / confirmed quit-all / restore relaunch+hide / geometry reapply via layout plan)
- [ ] Coordinator: save (name prompt via Dialog) / rename / delete / restore / clear-workspace funnels with Dialog confirm (quit) + HUD report; last-restored tracking for "Restore last session"
- [ ] Launcher surface: `CommandID` cases (save-session, sessions-browse, restore-last-session) + `AppEntry.Kind.session` + `SettingsTab.ownedCommands` + `VisibilityStore` wiring; `SessionsScreen` list+detail browser with icons via `AppIndex`/`IconCache`
- [ ] Hotkeys: per-command global shortcuts via HotKeyManager; guard sits in the dispatch funnel like other feature switches
- [ ] Settings pane: `SessionsSettingsView` — session list (rename/delete), ignore-list editor, geometry opt-out editor, hide-vs-quit default; new `SettingsTab.sessions`; new `AppSettings`/`AppSettingsKey` entries for the two lists
- [ ] Backup split: `SettingsData` + `SettingsBackupCoverage` entries for the two lists (carried under `.configuration`); assert NO sessions field and no gather/apply of the sessions library; extend backup harness expectations
- [ ] Docs: `docs/features/sessions.md` + invariants (restore = relaunch+hide; runner never touches WindowActionMemory; geometry opt-out moves nothing; sessions local-only, exclusion lists ride backup); update README/docs index
- [ ] Verify: `grep` Model purity, `./Scripts/run-tests.sh`, Debug build no new warnings, `./Scripts/lint.sh`

## Verification

- `grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/Sessions/Model/` returns nothing
- `./Scripts/run-tests.sh` passes (incl. new sessions harness + backup coverage harness)
- Debug build compiles with no new warnings; `./Scripts/lint.sh` clean
- Manual: save named session with N apps → hide-all clears → restore relaunches missing + hides extras + reapplies geometry; quit-all asks confirm first; ignore-listed app never captured; geometry-opted-out app relaunches but isn't moved; sessions absent from backup export/import while ignore-list + geometry-opt-out survive a backup round-trip; hotkeys fire with palette closed
