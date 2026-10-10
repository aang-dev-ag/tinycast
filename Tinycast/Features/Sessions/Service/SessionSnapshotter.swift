import AppKit

/// Reads the running workspace into session entries, minus what the user excluded.
enum SessionSnapshotter {
    static let finderID = "com.apple.finder"

    static func entries(from candidates: [SessionEntry.Candidate], ignored: Set<String>, geometry: SessionEntry.GeometryMap)
        -> [SessionEntry] {
        SessionEntry.capturing(candidates: candidates, ignored: ignored, geometry: geometry)
    }

    @MainActor
    static func captureCurrent(ignored: Set<String>, geometryOptOut: Set<String>) -> [SessionEntry] {
        let ownPID = NSRunningApplication.current.processIdentifier
        let ownID = Bundle.main.bundleIdentifier
        let candidates: [SessionEntry.Candidate] =
            NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.activationPolicy == .regular, app.processIdentifier != ownPID,
                    app.bundleIdentifier != ownID, app.bundleIdentifier != finderID,
                    let bundleID = app.bundleIdentifier
                else { return nil }
                return (bundleID, app.localizedName ?? bundleID)
            }
        let blocked = Set(geometryOptOut.map { $0.lowercased() })
        var geometry: [String: WindowLayoutEntry] = [:]
        let captured = WindowLayoutRunner.captureCurrentWindows().entries
        for entry in captured where geometry[entry.bundleID.lowercased()] == nil {
            guard !blocked.contains(entry.bundleID.lowercased()) else { continue }
            geometry[entry.bundleID.lowercased()] = entry
        }
        return entries(from: candidates, ignored: ignored, geometry: geometry)
    }
}
