import Foundation

/// A named set of apps captured together, restored together.
struct Session: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "session:"
    static let sfSymbol = "square.stack"

    let id: UUID
    var name: String
    var createdAt: Date
    var entries: [SessionEntry]

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), entries: [SessionEntry] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        entries = try container.decodeIfPresent([SessionEntry].self, forKey: .entries) ?? []
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    var summary: String {
        entries.count == 1 ? "1 app" : "\(entries.count) apps"
    }

    mutating func sanitizeEntries() {
        entries = SessionEntry.sanitized(entries)
    }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum SessionValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case noEntries
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the session."
        case .duplicateName: return "A session with this name already exists."
        case .noEntries: return "No apps to save in this session."
        case .invalidCharacter: return "Names cannot contain null characters."
        }
    }
}
