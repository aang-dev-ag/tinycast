// Standalone contract tests for Space-switch clamp, prediction and swipe reading.
import Foundation

@main
@MainActor
struct SpaceSwitchTests {
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
        testDirectionReading()
        testPostingAgainstReading()
        testEdgeClamp()
        testPrediction()
        testSyntheticTag()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func testDirectionReading() {
        expect(SpaceSwitchState.isRightSwipe(progress: 0.5), "positive progress reads as right")
        expect(!SpaceSwitchState.isRightSwipe(progress: -0.5), "negative progress reads as left")
        expect(!SpaceSwitchState.isRightSwipe(progress: 0), "zero progress reads as left")
        expect(SpaceSwitchState.isRightSwipe(velocityX: 9999), "positive velocity reads as right")
        expect(!SpaceSwitchState.isRightSwipe(velocityX: -9999), "negative velocity reads as left")
        expect(!SpaceSwitchState.isRightSwipe(velocityX: 0), "zero velocity reads as left")
        expectEqual(SpaceSwitchState.direction(isRightSwipe: true), .next, "a right swipe steps next")
        expectEqual(SpaceSwitchState.direction(isRightSwipe: false), .previous, "a left swipe steps previous")
    }

    static func testPostingAgainstReading() {
        let travel: Double = 0.1
        for natural in [true, false] {
            let nextSign = SpaceGesture.postingSign(direction: .next, naturalScrolling: natural)
            let previousSign = SpaceGesture.postingSign(
                direction: .previous, naturalScrolling: natural)
            expect(nextSign == -previousSign, "the two directions post opposite signs")
            let fields = SpaceGesture.instantFields(
                phase: .changed, direction: .next, travel: travel, naturalScrolling: natural)
            guard case .double(let progress) = fields.first(where: { $0.raw == 124 })?.value
            else {
                expect(false, "instant changed carries progress")
                continue
            }
            let readRight = SpaceSwitchState.isRightSwipe(progress: progress)
            expect(readRight == (nextSign > 0), "the reader follows the posted sign")
            expect(progress != 0, "posted progress never quantizes to a no-op")
        }
    }

    static func testEdgeClamp() {
        expectEqual(
            SpaceSwitchState.target(direction: .next, spaceCount: 3, activeIndex: 1), 2,
            "a middle Space steps next")
        expectEqual(
            SpaceSwitchState.target(direction: .previous, spaceCount: 3, activeIndex: 1), 0,
            "a middle Space steps previous")
        expect(
            SpaceSwitchState.target(direction: .previous, spaceCount: 3, activeIndex: 0) == nil,
            "the first Space stays put instead of rubber-banding")
        expect(
            SpaceSwitchState.target(direction: .next, spaceCount: 3, activeIndex: 2) == nil,
            "the last Space stays put instead of rubber-banding")
        expect(
            SpaceSwitchState.target(direction: .next, spaceCount: 1, activeIndex: 0) == nil,
            "a lone Space never moves")
        expect(
            SpaceSwitchState.target(direction: .next, spaceCount: 0, activeIndex: 0) == nil,
            "an unreadable list fails closed on the clamp")
        expect(
            SpaceSwitchState.target(direction: .next, spaceCount: 3, activeIndex: 9) == nil,
            "an out-of-range active index fails closed")
    }

    static func testPrediction() {
        expectEqual(SpaceSwitchState.Prediction.window, 0.4, "the prediction outlives the settle lag")
        var prediction = SpaceSwitchState.Prediction()
        expectEqual(
            prediction.base(displayKey: "a", activeIndex: 0, now: 100), 0,
            "with no record the SkyLight index stands")
        prediction.record(displayKey: "a", landingIndex: 1, now: 100)
        expectEqual(
            prediction.base(displayKey: "a", activeIndex: 0, now: 100.2), 1,
            "a fresh landing overrides the stale list")
        let stepped = SpaceSwitchState.target(
            direction: .next, spaceCount: 4,
            activeIndex: prediction.base(displayKey: "a", activeIndex: 0, now: 100.2))
        expectEqual(stepped, 2, "a rapid repeat keeps stepping instead of sticking")
        expectEqual(
            prediction.base(displayKey: "a", activeIndex: 0, now: 100.5), 0,
            "an expired landing falls back to the list")
        expectEqual(
            prediction.base(displayKey: "b", activeIndex: 0, now: 100.2), 0,
            "a landing never leaks onto another display")
        expectEqual(
            prediction.base(displayKey: "a", activeIndex: 0, now: 99.9), 0,
            "a clock step back falls back instead of trusting the future")
        prediction.reset()
        expectEqual(
            prediction.base(displayKey: "a", activeIndex: 2, now: 100.2), 2,
            "a reset prediction stops overriding")
    }

    static func testSyntheticTag() {
        expectEqual(SpaceGesture.syntheticTag, 0x4E53_5753, "our own output carries the tag")
    }
}
