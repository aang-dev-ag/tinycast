import CoreGraphics
import Foundation

/// Switches Space with a synthetic Dock swipe, so macOS skips its sliding transition.
@MainActor
final class SpaceSwitcher {
    /// The running OS decides whether the payload is required, so this cannot be `#available`.
    private nonisolated static let augmentsEvents = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))

    private var gesture: Task<Void, Never>?
    private var isPostingInstant = false
    private var prediction = SpaceSwitchState.Prediction()
    /// A second gesture overlapping the first makes the Dock move two Spaces, so it is dropped.
    func perform(_ direction: SpaceDirection) {
        guard gesture == nil, Permissions.ensureAccessibility() else { return }
        gesture = Task {
            await Self.post(direction)
            gesture = nil
        }
    }

    /// The instant path posts synchronously, so a swipe's synthetics land before the terminal event.
    func performInstant(_ direction: SpaceDirection, travel: Double) {
        guard !isPostingInstant, Permissions.isAccessibilityTrusted() else { return }
        guard Self.augmentsEvents else {
            perform(direction)
            return
        }
        let natural = Self.naturalScrolling
        let now = ProcessInfo.processInfo.systemUptime
        if let info = SkyLightSpaces.spaceInfo(cursorPoint: Self.cursorPoint()) {
            let base = prediction.base(displayKey: info.displayKey, activeIndex: info.activeIndex, now: now)
            guard
                let landing = SpaceSwitchState.target(
                    direction: direction, spaceCount: info.spaces.count, activeIndex: base)
            else { return }
            guard postInstant(direction: direction, travel: travel, naturalScrolling: natural) else { return }
            prediction.record(displayKey: info.displayKey, landingIndex: landing, now: now)
        } else {
            _ = postInstant(direction: direction, travel: travel, naturalScrolling: natural)
        }
    }
    /// The key is absent until the user first changes it, and macOS defaults it to on.
    private nonisolated static var naturalScrolling: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }

    private nonisolated static func cursorPoint() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
    private nonisolated static func post(_ direction: SpaceDirection) async {
        // macOS 27 applies Natural Scrolling to a synthetic swipe, so the sign is undone here.
        let direction = augmentsEvents && naturalScrolling ? direction.reversed : direction
        for phase in SpaceGesture.Phase.allCases {
            guard let event = event(phase: phase, direction: direction) else { return }
            event.post(tap: .cgSessionEventTap)
            guard augmentsEvents, phase != .ended else { continue }
            try? await Task.sleep(for: SpaceGesture.phaseDelay)
        }
    }

    private nonisolated static func event(
        phase: SpaceGesture.Phase, direction: SpaceDirection
    ) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        // A freshly created event carries no timestamp, which the payload cannot be built without.
        let timestamp = mach_absolute_time()
        let fields = SpaceGesture.fields(
            phase: phase, direction: direction, augmented: augmentsEvents, timestamp: timestamp)
        for field in fields {
            guard let key = CGEventField(rawValue: field.raw) else { continue }
            switch field.value {
            case .integer(let value): event.setIntegerValueField(key, value: value)
            case .double(let value): event.setDoubleValueField(key, value: value)
            }
        }
        guard augmentsEvents else { return event }
        let payload = SpaceGesture.payload(
            phase: phase, direction: direction, timestamp: timestamp)
        return augmented(event, payload: payload)
    }

    /// All three Dock events build up front; a partial began with no ended strands the Dock.
    private func postInstant(direction: SpaceDirection, travel: Double, naturalScrolling: Bool) -> Bool {
        var docks: [CGEvent] = []
        var companions: [CGEvent] = []
        for phase in SpaceGesture.Phase.allCases {
            guard
                let dock = Self.instantEvent(
                    phase: phase, direction: direction, travel: travel,
                    naturalScrolling: naturalScrolling),
                let companion = Self.companion()
            else { return false }
            docks.append(dock)
            companions.append(companion)
        }
        isPostingInstant = true
        defer { isPostingInstant = false }
        for index in docks.indices {
            docks[index].post(tap: .cgSessionEventTap)
            companions[index].post(tap: .cgSessionEventTap)
        }
        return true
    }

    private nonisolated static func instantEvent(
        phase: SpaceGesture.Phase, direction: SpaceDirection, travel: Double, naturalScrolling: Bool
    ) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        let timestamp = mach_absolute_time()
        let fields = SpaceGesture.instantFields(
            phase: phase, direction: direction, travel: travel, naturalScrolling: naturalScrolling)
        for field in fields {
            guard let key = CGEventField(rawValue: field.raw) else { continue }
            switch field.value {
            case .integer(let value): event.setIntegerValueField(key, value: value)
            case .double(let value): event.setDoubleValueField(key, value: value)
            }
        }
        let payload = SpaceGesture.instantPayload(
            phase: phase, direction: direction, travel: travel, naturalScrolling: naturalScrolling,
            timestamp: timestamp)
        guard let spliced = augmented(event, payload: payload) else { return nil }
        spliced.setIntegerValueField(.eventSourceUserData, value: SpaceGesture.syntheticTag)
        return spliced
    }

    private nonisolated static func companion() -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        guard let gesture = CGEventType(rawValue: 29) else { return nil }
        event.type = gesture
        event.setIntegerValueField(.eventSourceUserData, value: SpaceGesture.syntheticTag)
        return event
    }
    /// No setter reaches field 4205, so the payload is spliced into the serialized event instead.
    private nonisolated static func augmented(_ event: CGEvent, payload: Data) -> CGEvent? {
        guard var bytes = event.__data(allocator: nil) as Data?,
            bytes.starts(with: SpaceGesture.dataVersion)
        else { return nil }
        bytes.append(contentsOf: SpaceGesture.payloadRecordHeader(payloadCount: payload.count))
        bytes.append(payload)
        return CGEvent(withDataAllocator: nil, data: bytes as CFData)
    }
}
