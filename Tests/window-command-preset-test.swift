// Standalone contract tests for the migration preset tables.
import Foundation

@main
@MainActor
struct WindowCommandPresetTests {
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

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), expected \(expected)")
        }
    }

    static func main() {
        testTableSizes()
        testSpotValues()
        testChordUniqueness()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func testTableSizes() {
        expectEqual(
            WindowCommandPreset.rectangle.entries.count, 22, "the Rectangle table covers 22 actions")
        expectEqual(
            WindowCommandPreset.spectacle.entries.count, 16, "the Spectacle table covers 16 actions")
        expectEqual(
            WindowCommandPreset.magnet.entries.count, 16, "the Magnet table covers 16 actions")
        for preset in WindowCommandPreset.allCases {
            let ids = Set(preset.entries.map(\.command))
            expectEqual(
                ids.count, preset.entries.count, "the \(preset.title) table names no action twice")
            for entry in preset.entries {
                expect(
                    WindowCommand.ID.allCases.contains(entry.command),
                    "the \(preset.title) table only names catalog actions")
            }
        }
    }

    static func chord(_ keyCode: Int, _ modifiers: Int) -> String { "\(keyCode):\(modifiers)" }

    static func testSpotValues() {
        let ctrl = 1 << 12
        let opt = 1 << 11
        let cmd = 1 << 8
        func entry(_ preset: WindowCommandPreset, _ id: WindowCommand.ID) -> WindowCommandPreset.Entry? {
            preset.entries.first { $0.command == id }
        }
        let left = entry(.rectangle, .leftHalf)
        expectEqual(
            chord(left?.keyCode ?? 0, left?.carbonModifiers ?? 0), chord(123, ctrl | opt),
            "Rectangle left half is ⌃⌥←")
        let spectacleLeft = entry(.spectacle, .leftHalf)
        expectEqual(
            chord(spectacleLeft?.keyCode ?? 0, spectacleLeft?.carbonModifiers ?? 0),
            chord(123, cmd | opt), "Spectacle left half is ⌘⌥←")
        let center = entry(.rectangle, .centerTwoThirds)
        expectEqual(
            chord(center?.keyCode ?? 0, center?.carbonModifiers ?? 0), chord(15, ctrl | opt),
            "Rectangle center two-thirds is ⌃⌥R")
        let magnetCenter = entry(.magnet, .center)
        expectEqual(
            chord(magnetCenter?.keyCode ?? 0, magnetCenter?.carbonModifiers ?? 0),
            chord(8, ctrl | opt), "Magnet center is ⌃⌥C")
        expect(
            entry(.magnet, .nextDisplay) == nil, "Magnet binds no display moves by default")
        expect(
            entry(.spectacle, .firstThird) == nil, "Spectacle defines no thirds")
    }

    static func testChordUniqueness() {
        for preset in WindowCommandPreset.allCases {
            let chords = Set(preset.entries.map { chord($0.keyCode, $0.carbonModifiers) })
            expectEqual(
                chords.count, preset.entries.count,
                "the \(preset.title) table assigns every action its own chord")
        }
    }
}
