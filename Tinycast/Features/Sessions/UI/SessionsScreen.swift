import SwiftUI

/// The session browser: a filtered list beside a preview of the selected session.
struct SessionsScreen: PaletteScreen {
    let store: SessionStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    var rows: [Session] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.sessions }
        return store.sessions.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var primaryActionTitle: String { "Restore Session" }

    private func session(at selection: Int) -> Session? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let session = session(at: selection) else { return nil }
        return SessionActionsMenu.content(session: session, core: core)
    }

    func activate(at selection: Int) {
        guard let session = session(at: selection) else { return }
        core.sessionCoordinator.restoreSession(id: session.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            guard let session = session(at: selection) else { return false }
            core.sessionCoordinator.deleteSession(id: session.id)
            return true
        default:
            return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: store.sessions.isEmpty ? "No sessions yet" : "No matching sessions")
        } else {
            let selected = session(at: selection)
            HStack(spacing: 0) {
                SessionList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { session in
                        vm.selection = rows.firstIndex(of: session) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { session in
                        if let index = rows.firstIndex(of: session) { vm.selection = index }
                        openActions()
                    })
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: 1)
                SessionPreview(session: selected, core: core)
            }
        }
    }
}

/// The ⌘K menu for a session row.
@MainActor
enum SessionActionsMenu {
    static func content(session: Session, core: AppCore) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(title: "Restore Session", systemImage: Session.sfSymbol, shortcut: "↵") {
                core.sessionCoordinator.restoreSession(id: session.id)
            }
        ]
        items.append(
            PopoverMenuItem(title: "Rename Session", systemImage: "pencil") {
                core.sessionCoordinator.renameSession(id: session.id)
            })
        items.append(
            PopoverMenuItem(title: "Hide Other Apps", systemImage: "eye.slash") {
                core.sessionCoordinator.clearWorkspace(quit: false)
            })
        items.append(
            PopoverMenuItem(
                title: "Delete Session", systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) {
                core.sessionCoordinator.deleteSession(id: session.id)
            })
        return PopoverMenuContent(header: session.name, items: items)
    }
}

private struct SessionList: View {
    @Environment(\.metrics) private var metrics
    let results: [Session]
    let selectedID: Session.ID?
    let scroll: ScrollIntent
    let onSelect: (Session) -> Void
    let onActivate: () -> Void
    let onActions: (Session) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { session in
                        SessionRow(session: session, selected: session.id == selectedID)
                            .selectionFrame(session.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(session) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(session)
                                    onActivate()
                                })
                            .onRightClick { onActions(session) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID?.uuidString,
                atOrigin: selectedID == results.first?.id, proxy: proxy)
        }
    }
}

private struct SessionRow: View {
    @Environment(\.metrics) private var metrics
    let session: Session
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.md) {
            SymbolImage(name: Session.sfSymbol, size: metrics.size.menuIcon)
                .foregroundStyle(Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).lineLimit(1)
                    .font(metrics.typography.rowTitle)
                Text(session.summary).lineLimit(1)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(fill, in: RoundedRectangle(cornerRadius: metrics.radius.row))
        .onHover { hovered = $0 }
    }
}

private struct SessionPreview: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppIndex.self) private var appIndex
    let session: Session?
    let core: AppCore

    private static let savedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        if let session {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(metrics.typography.rowTitle)
                    Text(
                        "\(session.summary) · Saved \(Self.savedFormatter.string(from: session.createdAt))"
                    )
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.entries, id: \.bundleID) { entry in
                            let resolved = AppPresentation.resolve(
                                bundleID: entry.bundleID, in: appIndex)
                            HStack(spacing: metrics.spacing.md) {
                                Image(nsImage: resolved.icon)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                Text(entry.displayName).lineLimit(1)
                                    .font(metrics.typography.rowTitle)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                        }
                    }
                }
                .hideNativeScrollers()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }
}
