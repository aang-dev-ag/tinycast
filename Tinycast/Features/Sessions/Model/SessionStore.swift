import Foundation

/// The named session library, kept local to this Mac like a history is.
@MainActor
@Observable
final class SessionStore {
    private static let defaultsKey = "workspaceSessions"
    private static let lastKey = "workspaceSessionsLastID"

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private(set) var sessions: [Session]
    private(set) var lastID: UUID?
    @ObservationIgnored var onChange: (([Session]) -> Void)?

    init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([Session].self, from: $0) } ?? []
        sessions = Self.sanitized(decoded)
        if sessions != decoded { Self.persist(sessions, to: defaults) }
        lastID =
            defaults.string(forKey: Self.lastKey).flatMap(UUID.init(uuidString:))
            .flatMap { id in sessions.contains(where: { $0.id == id }) ? id : nil }
    }

    func session(id: UUID) -> Session? {
        sessions.first { $0.id == id }
    }

    func session(entryID: String) -> Session? {
        Session.id(fromEntryID: entryID).flatMap(session(id:))
    }

    var lastSession: Session? {
        lastID.flatMap(session(id:)) ?? sessions.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    func noteUsed(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        lastID = id
        defaults.set(id.uuidString, forKey: Self.lastKey)
    }

    @discardableResult
    func add(_ draft: Session) throws(SessionValidationError) -> Session {
        let value = try validated(draft)
        commit(sessions + [value])
        noteUsed(id: value.id)
        return value
    }

    func create(name: String, entries: [SessionEntry]) throws(SessionValidationError) -> Session {
        try add(Session(name: name, createdAt: now(), entries: entries))
    }

    func update(_ draft: Session) throws(SessionValidationError) {
        guard let index = sessions.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = sessions
        updated[index] = value
        commit(updated)
    }

    func rename(id: UUID, to name: String) throws(SessionValidationError) {
        guard var draft = session(id: id) else { return }
        draft.name = name
        try update(draft)
    }

    @discardableResult
    func remove(id: UUID) -> Session? {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = sessions
        let removed = updated.remove(at: index)
        commit(updated)
        if lastID == id {
            lastID = nil
            defaults.removeObject(forKey: Self.lastKey)
        }
        return removed
    }

    @discardableResult
    func replace(with incoming: [Session]) -> Int {
        let updated = Self.sanitized(incoming)
        commit(updated)
        if let lastID, !updated.contains(where: { $0.id == lastID }) {
            self.lastID = nil
            defaults.removeObject(forKey: Self.lastKey)
        }
        return updated.count
    }

    static func uniqueName(from name: String, among existing: [Session]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Session" : trimmed
        let taken = Set(existing.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }

    private func validated(_ draft: Session) throws(SessionValidationError) -> Session {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.sanitizeEntries()
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard !value.entries.isEmpty else { throw .noEntries }
        guard
            !sessions.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw .duplicateName }
        return value
    }

    private func commit(_ updated: [Session]) {
        let ordered = updated.sorted(by: Session.precedes)
        guard ordered != sessions else { return }
        sessions = ordered
        Self.persist(ordered, to: defaults)
        onChange?(ordered)
    }

    private static func persist(_ sessions: [Session], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func sanitized(_ values: [Session]) -> [Session] {
        var ids = Set<UUID>()
        var names = Set<String>()
        var result: [Session] = []
        for value in values {
            var cleaned = value
            cleaned.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.sanitizeEntries()
            let folded = cleaned.name.folding(options: [.caseInsensitive], locale: .current)
            guard !cleaned.name.isEmpty, !cleaned.name.contains("\0"), !cleaned.entries.isEmpty,
                ids.insert(cleaned.id).inserted, names.insert(folded).inserted
            else { continue }
            result.append(cleaned)
        }
        return result.sorted(by: Session.precedes)
    }
}
