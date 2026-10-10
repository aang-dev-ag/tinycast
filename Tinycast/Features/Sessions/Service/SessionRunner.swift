import AppKit

/// Clears the workspace and brings a session back, relaunching what is missing.
@MainActor
enum SessionRunner {
    struct RestoreOutcome: Sendable {
        var relaunched = 0
        var hidden = 0
        var placed = 0
        var skippedDetails: String?
    }

    static func hideExtras(notIn bundleIDs: Set<String>, ignoring ignored: Set<String>) -> Int {
        let wanted = Set(bundleIDs.map { $0.lowercased() })
        let blocked = Set(ignored.map { $0.lowercased() })
        let ownPID = NSRunningApplication.current.processIdentifier
        let ownID = Bundle.main.bundleIdentifier
        var hidden = 0
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, app.processIdentifier != ownPID,
                app.bundleIdentifier != ownID,
                app.bundleIdentifier != SessionSnapshotter.finderID,
                let bundleID = app.bundleIdentifier, !wanted.contains(bundleID.lowercased()),
                !blocked.contains(bundleID.lowercased())
            else { continue }
            app.hide()
            hidden += 1
        }
        return hidden
    }

    static func quitTargets(ignoring ignored: Set<String>) -> [NSRunningApplication] {
        let blocked = Set(ignored.map { $0.lowercased() })
        return AppLauncher.quitAllTargets().filter {
            guard let bundleID = $0.bundleIdentifier else { return true }
            return !blocked.contains(bundleID.lowercased())
        }
    }

    static func restore(
        _ session: Session, gap: CGFloat, geometryOptOut: Set<String>, ignoring ignored: Set<String>
    ) async -> RestoreOutcome {
        let blocked = Set(ignored.map { $0.lowercased() })
        let running = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        var relaunched = 0
        for entry in session.entries {
            guard !blocked.contains(entry.bundleID.lowercased()),
                !running.contains(entry.bundleID.lowercased()),
                let url = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: entry.bundleID)
            else { continue }
            AppLauncher.launch(url)
            relaunched += 1
        }
        let wanted = Set(session.entries.map(\.bundleID))
        let hidden = hideExtras(notIn: wanted, ignoring: ignored)
        let optOut = Set(geometryOptOut.map { $0.lowercased() })
        let geometries = session.entries.compactMap { entry -> WindowLayoutEntry? in
            guard !optOut.contains(entry.bundleID.lowercased()) else { return nil }
            return entry.geometry
        }
        guard !geometries.isEmpty else {
            return RestoreOutcome(relaunched: relaunched, hidden: hidden)
        }
        let layout = WindowLayout(
            name: session.name, usesPreferredGap: false, entries: geometries)
        let outcome = await WindowLayoutRunner.run(layout, gap: gap)
        let skipped =
            WindowLayoutPlan(placements: [], skipped: outcome.skipped).skippedSummary
        return RestoreOutcome(
            relaunched: relaunched, hidden: hidden, placed: outcome.placed,
            skippedDetails: skipped)
    }
}
