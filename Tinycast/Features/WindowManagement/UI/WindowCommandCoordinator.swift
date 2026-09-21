import AppKit

/// The one funnel from a palette row or a global hotkey to the mover.
/// Observable only for `@Environment`.
@MainActor
@Observable
final class WindowCommandCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private let windowMover: WindowMover
    private let spaceSwitcher: SpaceSwitcher
    private let customSizes: CustomWindowSizeStore
    private let hotKeys: HotKeyManager
    private unowned let core: AppCore
    init(
        settings: AppSettings, paletteCoordinator: PaletteCoordinator, windowMover: WindowMover,
        spaceSwitcher: SpaceSwitcher, customSizes: CustomWindowSizeStore, hotKeys: HotKeyManager,
        core: AppCore
    ) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.windowMover = windowMover
        self.spaceSwitcher = spaceSwitcher
        self.customSizes = customSizes
        self.hotKeys = hotKeys
        self.core = core
    }

    /// The one funnel for palette and hotkey alike. See docs/features/window-management.md#wiring.
    func runWindowCommand(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        if let direction = SpaceDirection(id) {
            runSpaceSwitch(direction)
            return
        }
        windowMover.perform(
            id, target: handOffTarget(), gap: CGFloat(settings.windowGap),
            cycle: settings.windowCycle)
    }

    /// The one funnel for palette, hotkey and swipe; the gate branches here, nowhere else.
    func runSpaceSwitch(_ direction: SpaceDirection) {
        guard settings.windowManagementEnabled else { return }
        // Restoring focus reactivates an app elsewhere, pulling its Space forward.
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        if settings.instantSpacesEnabled {
            spaceSwitcher.performInstant(direction, travel: settings.spaceSwitchTravel)
        } else {
            spaceSwitcher.perform(direction)
        }
    }
    /// The same funnel for a custom size, so the feature switch gates it identically.
    func runCustomWindowSize(id: UUID) {
        guard settings.windowManagementEnabled, let size = customSizes.size(id: id) else { return }
        windowMover.perform(size, target: handOffTarget(), gap: CGFloat(settings.windowGap))
    }
    /// Loads a migration preset's shortcuts, asking first: this replaces managed bindings.
    func applyPreset(_ preset: WindowCommandPreset) async {
        guard settings.windowManagementEnabled else { return }
        let confirmed = await core.confirm(
            title: "Load \(preset.title) shortcuts?",
            message: "This replaces your window-management shortcuts. "
                + "Shortcuts the preset doesn't cover stay as they are.",
            symbol: "keyboard", confirmTitle: "Load", confirmRole: .destructive)
        guard confirmed else { return }
        let actions = preset.entries.map { HotKeyAction.windowCommand(id: $0.command) }
        for action in actions { hotKeys.setBinding(nil, for: action) }
        var skipped = 0
        for entry in preset.entries {
            let action = HotKeyAction.windowCommand(id: entry.command)
            let binding = HotKeyBinding.combo(
                KeyShortcut(
                    carbonKeyCode: entry.keyCode, carbonModifiers: entry.carbonModifiers))
            guard hotKeys.conflictOwner(of: binding, excluding: action) == nil else {
                skipped += 1
                continue
            }
            hotKeys.setBinding(binding, for: action)
        }
        if skipped == 0 {
            core.showMessage("Loaded \(preset.title) shortcuts.")
        } else {
            core.showMessage("Loaded \(preset.title) shortcuts, skipped \(skipped) already in use.")
        }
    }

    /// Removes every window-command shortcut, asking first.
    func clearWindowCommandShortcuts() async {
        guard settings.windowManagementEnabled else { return }
        let bound = WindowCommand.ID.allCases.filter {
            hotKeys.binding(for: .windowCommand(id: $0)) != nil
        }
        guard !bound.isEmpty else {
            core.showMessage("No window shortcuts to clear.")
            return
        }
        let confirmed = await core.confirm(
            title: "Clear all window shortcuts?",
            message: "This removes every window-management shortcut. "
                + "Custom sizes and layouts keep theirs.",
            symbol: "keyboard", confirmTitle: "Clear", confirmRole: .destructive)
        guard confirmed else { return }
        for id in bound { hotKeys.setBinding(nil, for: .windowCommand(id: id)) }
        core.showMessage(
            bound.count == 1 ? "Cleared 1 window shortcut." : "Cleared \(bound.count) window shortcuts.")
    }

    /// The window to place, read before the palette hides and hands focus back to it.
    private func handOffTarget() -> WindowTarget? {
        guard paletteCoordinator.isVisible else { return WindowTarget.current() }
        let target = WindowTarget.behindPalette(
            ownWindow: paletteCoordinator.previousOwnWindow, app: paletteCoordinator.targetApp)
        paletteCoordinator.hidePalette(restoreFocus: true)
        return target
    }
}
