# Sessions

A **Session** is a named set of Mac apps captured together, cleared away together and restored
together. Save what is open now, hide or quit everything to clear the desk, then bring the set back
with one click — missing apps relaunch, anything else hides, and each window lands where it was.

It reuses the launcher, the palette, the global-shortcut map and Window Management's Accessibility
grant, and adds no permission: hiding and terminating go through `NSWorkspace`, and geometry capture
reads the same AX attributes the layout runner writes.

## Invariants

- **Restore is relaunch plus hide.** Apps in the session that are not running are opened; running
  regular-policy apps that are not in the session are hidden; then geometry is reapplied. Nothing is
  ever focused beyond what the geometry pass itself brings forward.
- **The runner never touches `WindowActionMemory`.** A restore is not a window command, so it must not
  overwrite the single-level restore point the commands keep.
- **A geometry opt-out moves nothing.** The app still relaunches, but its entry's snapshot is dropped
  before the layout is built, so no frame is ever written for it.
- **Sessions are local-only; the exclusion lists ride the backup.** The library has no
  `SettingsBackup` field and is never gathered or applied. `sessionsIgnoredApps`,
  `sessionsGeometryOptOut` and `sessionsQuitOnClear` travel as ordinary configuration keys, the same
  shape as `menuSearchDisabledApps`.
- **Quit always confirms.** Hiding is the default because it is reversible; quitting goes through
  `DialogController` first, and graceful termination means unsaved work still gets its sheet.
- **`Model/` stays Foundation-only.** The store takes the clock as an injected `now`, so the harness
  compiles the shipped sources verbatim.

## Layout

| File | Role |
| --- | --- |
| `Model/Session.swift` | **Pure.** The record, its identity and its validation |
| `Model/SessionEntry.swift` | **Pure.** One app plus its optional geometry, and the capture filter |
| `Model/SessionStore.swift` | The named library as JSON in `UserDefaults`, with the last-used marker |
| `Service/SessionSnapshotter.swift` | Regular-policy capture minus Finder/self, filtered by the ignore list |
| `Service/SessionRunner.swift` | Hide-all, quit targets and the relaunch-plus-hide restore |
| `UI/SessionCoordinator.swift` | The one funnel: save, rename, delete, restore, clear |
| `UI/SessionsScreen.swift` | The palette browser: session list beside entry preview |
| `Settings/SessionsSettingsView.swift` | The pane: library, clear default and both exclusion lists |

## Capture

The candidates are `NSWorkspace.runningApplications` with a regular activation policy, minus this
process by pid and minus Finder, which `terminate()` would only relaunch. The ignore list filters by
lowercased bundle ID before anything else, so an ignored app is never captured, hidden or quit.

Geometry comes from `WindowLayoutRunner.captureCurrentWindows()`, first window per bundle ID, minus
the opt-out list. An app with no positionable window still captures — it restores by relaunch, just
without a frame to place.

## Running

`SessionCoordinator.restoreSession(id:)` is the one funnel for a palette row, a launcher row, a
global shortcut and the pane's button alike. It hides the palette with `restoreFocus: false`, launches
what is missing through `AppLauncher`, hides what is extra, then builds a gapless `WindowLayout` from
the surviving snapshots and runs it through `WindowLayoutRunner`. A run with nothing to do reports
itself as already in place rather than succeeding silently.

## Wiring

- **`AppEntry.Kind.session`** — entries are `session:<uuid>`, published by
  `AppIndex.setSessions(_)` immediately after the window-layout slice.
- **Three commands** — `Save Session`, `Sessions` and `Restore Last Session`, owned by
  `SettingsTab.sessions`. They ride the existing `commands` hotkey-backup map; no per-session binding
  is persisted, unlike window layouts.
- **Settings** — `sessionsIgnoredApps`, `sessionsGeometryOptOut` (both narrowing lists) and
  `sessionsQuitOnClear` (hide by default). All three ride the configuration backup.
- **Last used** — the store remembers the last saved or restored session for `Restore Last Session`,
  falling back to the most recently created one.

## Testing

`Tests/sessions-test.swift` covers the record and its entry id, entry sanitising and capture
filtering, validation, store CRUD with the last-used marker, sanitisation, persistence and unique
naming, plus a Codable round trip including a minimal hand-written payload.
