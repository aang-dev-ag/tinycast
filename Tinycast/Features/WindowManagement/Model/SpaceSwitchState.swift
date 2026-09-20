import Foundation

/// Pure Space-switch decisions: edge clamp, rapid-press prediction, swipe reading.
enum SpaceSwitchState {
    /// A real swipe reads positive as right on every OS; Natural Scrolling mirrors the gesture.
    static func isRightSwipe(progress: Double) -> Bool {
        progress > 0
    }

    /// Discrete swipes skip changed, so ended falls back to velocity on the same rule.
    static func isRightSwipe(velocityX: Double) -> Bool {
        velocityX > 0
    }

    /// Right means next: the writer already inverts the posted sign, so this stays direct.
    static func direction(isRightSwipe: Bool) -> SpaceDirection {
        isRightSwipe ? .next : .previous
    }
    /// The index a switch lands on, or nil at the first/last Space instead of rubber-banding.
    static func target(
        direction: SpaceDirection, spaceCount: Int, activeIndex: Int
    ) -> Int? {
        guard spaceCount > 0, activeIndex >= 0, activeIndex < spaceCount else { return nil }
        let stepped = direction == .next ? activeIndex + 1 : activeIndex - 1
        guard stepped >= 0, stepped < spaceCount else { return nil }
        return stepped
    }

    /// The SkyLight list settles slower than gestures commit, so the last landing wins briefly.
    struct Prediction: Equatable, Sendable {
        static let window: TimeInterval = 0.4

        private var displayKey: String?
        private var landingIndex: Int?
        private var recordedAt: TimeInterval?

        init() {}

        mutating func record(displayKey: String, landingIndex: Int, now: TimeInterval) {
            self.displayKey = displayKey
            self.landingIndex = landingIndex
            self.recordedAt = now
        }

        mutating func reset() {
            displayKey = nil
            landingIndex = nil
            recordedAt = nil
        }

        /// The base a clamp steps from: our own landing while fresh, else what SkyLight reports.
        func base(displayKey: String, activeIndex: Int, now: TimeInterval) -> Int {
            guard
                let recorded = landingIndex, let at = recordedAt,
                self.displayKey == displayKey, now >= at, now - at < Self.window
            else { return activeIndex }
            return recorded
        }
    }
}
