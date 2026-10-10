import Foundation

/// One app inside a session, with the window frame it had when captured.
struct SessionEntry: Codable, Hashable, Sendable {
    var bundleID: String
    var displayName: String
    var geometry: WindowLayoutEntry?

    init(bundleID: String, displayName: String, geometry: WindowLayoutEntry? = nil) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.geometry = geometry
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, displayName, geometry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? bundleID
        geometry = try container.decodeIfPresent(WindowLayoutEntry.self, forKey: .geometry)
    }

    typealias Candidate = (bundleID: String, displayName: String)
    typealias GeometryMap = [String: WindowLayoutEntry]

    static func capturing(candidates: [Candidate], ignored: Set<String>, geometry: GeometryMap) -> [SessionEntry] {
        let blocked = Set(ignored.map { $0.lowercased() })
        var seen = Set<String>()
        var result: [SessionEntry] = []
        for candidate in candidates {
            let bundleID = candidate.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, !blocked.contains(bundleID.lowercased()),
                seen.insert(bundleID.lowercased()).inserted
            else { continue }
            let name = candidate.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let geo = geometry[bundleID.lowercased()]
            let label = name.isEmpty ? bundleID : name
            result.append(SessionEntry(bundleID: bundleID, displayName: label, geometry: geo))
        }
        return result
    }

    static func sanitized(_ entries: [SessionEntry]) -> [SessionEntry] {
        var seen = Set<String>()
        var result: [SessionEntry] = []
        for entry in entries {
            let bundleID = entry.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, seen.insert(bundleID.lowercased()).inserted else { continue }
            let name = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                SessionEntry(
                    bundleID: bundleID, displayName: name.isEmpty ? bundleID : name,
                    geometry: entry.geometry))
        }
        return result
    }
}
