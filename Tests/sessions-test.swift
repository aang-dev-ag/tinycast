import Foundation

@main
@MainActor
struct SessionTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expectThrows(
        _ expected: SessionValidationError, _ message: String, _ body: () throws -> Void
    ) {
        do {
            try body()
            expect(false, message)
        } catch let error as SessionValidationError {
            expect(error == expected, message)
        } catch {
            expect(false, message)
        }
    }

    static func entry(
        _ bundleID: String = "com.example.app", _ name: String? = nil,
        geometry: WindowLayoutEntry? = nil
    ) -> SessionEntry {
        SessionEntry(bundleID: bundleID, displayName: name ?? bundleID, geometry: geometry)
    }

    static func geometry(_ bundleID: String = "com.example.app") -> WindowLayoutEntry {
        WindowLayoutEntry(
            bundleID: bundleID, display: WindowLayoutDisplay(uuid: "UUID-1", name: "Display 1"))
    }

    static func session(_ name: String = "Work", entries: [SessionEntry]) -> Session {
        Session(name: name, entries: entries)
    }

    static func withStore(_ body: (SessionStore) -> Void) {
        let name = "tinycast-sessions-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            expect(false, "a scratch defaults suite opens")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        body(SessionStore(defaults: defaults, now: { Date(timeIntervalSince1970: 1_700_000_000) }))
    }

    static func main() {
        recordIdentity()
        sanitizeEntries()
        capturing()
        storeValidation()
        storeCRUD()
        storeSanitization()
        storePersistence()
        uniqueNaming()
        codableRoundTrip()
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func recordIdentity() {
        let value = session(entries: [entry()])
        expect(value.entryID.hasPrefix("session:"), "an entry id is namespaced")
        expect(Session.id(fromEntryID: value.entryID) == value.id, "the entry id round-trips")
        expect(
            Session.id(fromEntryID: "window-layout:\(value.id)") == nil,
            "another feature's entry id is not claimed")
        expect(
            Session.id(fromEntryID: "session:not-a-uuid") == nil, "a malformed id is not claimed")
        expect(Session.sfSymbol == "square.stack", "sessions draw a stack glyph")
        expect(session(entries: [entry()]).summary == "1 app", "one entry reads singular")
        expect(session(entries: [entry(), entry("com.example.other")]).summary == "2 apps", "two read plural")
        let a = session("alpha", entries: [entry()])
        let b = session("Beta", entries: [entry()])
        expect(Session.precedes(a, b), "ordering is case-insensitive by name")
        expect(!Session.precedes(b, a), "ordering is antisymmetric")
    }

    static func sanitizeEntries() {
        let cleaned = SessionEntry.sanitized([
            entry("  com.example.app  ", "  Safari  "),
            entry("COM.EXAMPLE.APP", "Dupe"),
            entry("   ", "Blank"),
            entry("com.example.other", "   "),
        ])
        expect(cleaned.count == 2, "blanks drop and bundle ids dedupe case-insensitively")
        expect(cleaned.first?.displayName == "Safari", "the first of a dupe wins with its name")
        expect(cleaned.last?.displayName == "com.example.other", "an empty name falls back to the id")
    }

    static func capturing() {
        let geo = geometry()
        let captured = SessionEntry.capturing(
            candidates: [
                ("com.example.app", "Safari"), ("com.example.ignored", "Ignored"),
                ("COM.EXAMPLE.APP", "Dupe"), ("  ", "Blank"),
            ],
            ignored: ["COM.EXAMPLE.IGNORED"],
            geometry: ["com.example.app": geo])
        expect(captured.count == 1, "ignored apps never capture and dupes collapse")
        expect(captured.first?.geometry == geo, "geometry attaches by case-insensitive id")
        let bare = SessionEntry.capturing(
            candidates: [("com.example.app", "")], ignored: [], geometry: [:])
        expect(bare.first?.displayName == "com.example.app", "an empty name falls back to the id")
    }

    static func storeValidation() {
        withStore { store in
            for (name, label) in [("", "an empty"), ("   ", "a whitespace-only")] {
                expectThrows(.emptyName, "\(label) name is rejected") {
                    _ = try store.add(session(name, entries: [entry()]))
                }
            }
            expectThrows(.invalidCharacter, "a null character is rejected") {
                _ = try store.add(session("Bad\0Name", entries: [entry()]))
            }
            expectThrows(.noEntries, "a session with no entries is rejected") {
                _ = try store.add(session("Empty", entries: []))
            }
            _ = try? store.add(session("Work", entries: [entry()]))
            expectThrows(.duplicateName, "a duplicate name is rejected") {
                _ = try store.add(session("WORK", entries: [entry()]))
            }
        }
    }

    static func storeCRUD() {
        withStore { store in
            let entries = [entry(), entry("com.example.other")]
            guard let work = try? store.add(Session(name: "Work", entries: entries)) else {
                return expect(false, "adding a session succeeds")
            }
            expect(store.sessions.map(\.name) == ["Work"], "an added session is listed")
            expect(store.session(id: work.id)?.name == "Work", "a session is found by id")
            expect(store.session(entryID: work.entryID)?.id == work.id, "the entry id resolves")
            expect(store.lastSession?.id == work.id, "saving marks the session as last used")
            var renamed = work
            renamed.name = "Play"
            try? store.update(renamed)
            expect(store.sessions.map(\.name) == ["Play"], "an update lands")
            try? store.rename(id: work.id, to: "Evening")
            expect(store.session(id: work.id)?.name == "Evening", "a rename lands")
            expect(store.remove(id: work.id)?.id == work.id, "removing returns the record")
            expect(store.sessions.isEmpty, "removing takes it out of the library")
            expect(store.lastSession == nil, "removing the last session clears the marker")
            expect(store.remove(id: UUID()) == nil, "removing an unknown id is a no-op")
            var changes = 0
            store.onChange = { _ in changes += 1 }
            _ = try? store.add(Session(name: "Kept", entries: entries))
            changes = 0
            try? store.update(store.sessions[0])
            expect(changes == 0, "committing an unchanged record notifies nobody")
        }
    }

    static func storeSanitization() {
        let shared = UUID()
        let hostile = [
            Session(id: shared, name: "Work", entries: [entry()]),
            Session(id: shared, name: "Second", entries: [entry()]),
            Session(name: "work", entries: [entry()]),
            Session(name: "  ", entries: [entry()]),
            Session(name: "Empty", entries: []),
            Session(name: "Bad\0Name", entries: [entry()]),
            Session(name: "  Evening  ", entries: [entry("  "), entry("com.example.other")]),
        ]
        withStore { store in
            let kept = store.replace(with: hostile)
            expect(kept == 2, "only the sound records survive")
            expect(store.sessions.map(\.name) == ["Evening", "Work"], "survivors arrive in display order")
            guard let evening = store.sessions.first(where: { $0.name == "Evening" }) else {
                return expect(false, "the trimmed session kept its usable entry")
            }
            expect(evening.entries.map(\.bundleID) == ["com.example.other"], "blank entries drop")
        }
    }

    static func storePersistence() {
        let name = "tinycast-sessions-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            return expect(false, "a scratch defaults suite opens")
        }
        defer { defaults.removePersistentDomain(forName: name) }
        var stored: Session?
        do {
            let store = SessionStore(defaults: defaults)
            stored = try? store.add(
                Session(name: "Work", entries: [entry(geometry: geometry())]))
        }
        let reopened = SessionStore(defaults: defaults)
        expect(reopened.sessions.count == 1, "a reopened store finds its library")
        expect(reopened.sessions.first == stored, "every field survives the round trip")
        expect(reopened.lastSession?.id == stored?.id, "the last-used marker survives the round trip")
    }

    static func uniqueNaming() {
        let existing = [session("Session", entries: [entry()])]
        expect(
            SessionStore.uniqueName(from: "Session", among: existing) == "Session 2",
            "a taken name takes the next index")
        expect(
            SessionStore.uniqueName(from: "  ", among: []) == "Session",
            "a blank suggestion becomes Session")
        expect(
            SessionStore.uniqueName(from: "Work", among: existing) == "Work",
            "a free name passes through")
    }

    static func codableRoundTrip() {
        let value = Session(
            name: "Work", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            entries: [entry("com.example.app", "Safari", geometry: geometry())])
        guard let data = try? JSONEncoder().encode(value),
            let decoded = try? JSONDecoder().decode(Session.self, from: data)
        else {
            expect(false, "a session encodes and decodes")
            return
        }
        expect(decoded == value, "a session round-trips through JSON unchanged")
        let minimal = """
            [{"name": "Bare", "entries": [{"bundleID": "com.example.app"}]}]
            """
        guard
            let bare = try? JSONDecoder().decode(
                [Session].self, from: Data(minimal.utf8)), let first = bare.first,
            let only = first.entries.first
        else {
            expect(false, "a minimal hand-written payload decodes")
            return
        }
        expect(only.displayName == "com.example.app", "an absent display name falls back to the id")
        expect(only.geometry == nil, "an absent geometry defaults to none")
    }
}
