import AppKit

/// C entry point: reduce to Sendable scalars, then cross in. The actor returns the verdict.
private func spaceSwipeEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<SpaceSwipeMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { monitor.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    let phaseField = CGEventField(rawValue: 132)!
    let motionField = CGEventField(rawValue: 123)!
    let hidField = CGEventField(rawValue: 110)!
    let progressField = CGEventField(rawValue: 124)!
    let velocityField = CGEventField(rawValue: 129)!
    let scalars = SpaceSwipeMonitor.Input(
        typeRaw: Int(type.rawValue),
        phaseRaw: event.getIntegerValueField(phaseField),
        motionRaw: event.getIntegerValueField(motionField),
        hidRaw: event.getIntegerValueField(hidField),
        progress: event.getDoubleValueField(progressField),
        velocityX: event.getDoubleValueField(velocityField),
        isTagged: event.getIntegerValueField(.eventSourceUserData) == SpaceGesture.syntheticTag)
    let verdict = MainActor.assumeIsolated { monitor.decide(scalars) }
    switch verdict {
    case .pass(let zero):
        if zero {
            event.setDoubleValueField(velocityField, value: 0)
            event.setDoubleValueField(CGEventField(rawValue: 130)!, value: 0)
            event.setDoubleValueField(progressField, value: 0)
        }
        return Unmanaged.passUnretained(event)
    case .swallow:
        return nil
    }
}

/// The 3-finger swipe tap feeding the coordinator. See docs/plans/instant-spaces.md §5.
@MainActor
@Observable
final class SpaceSwipeMonitor: HealthCheckable {
    struct Input: Sendable {
        let typeRaw: Int
        let phaseRaw: Int64
        let motionRaw: Int64
        let hidRaw: Int64
        let progress: Double
        let velocityX: Double
        let isTagged: Bool
    }

    enum Verdict: Sendable {
        case pass(zero: Bool)
        case swallow
    }

    /// True while wanted but the tap can't be created; Settings surfaces it instead of prompting.
    private(set) var needsAccessibility = false

    /// Fired with the read-side direction; the coordinator posts the synthetic synchronously.
    @ObservationIgnored var onSwipe: (@MainActor (SpaceDirection) -> Void)?
    @ObservationIgnored private var tapPort: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var sessionTokens: [NotificationToken] = []
    private var sessionActive = true
    private var wantsTap = false
    private var tracking = false
    private var fired = false
    private var loggedTapFailure = false

    @ObservationIgnored weak var healthTicker: HealthTicker?

    isolated deinit {
        tearDownTap()
    }

    func update(enabled: Bool) {
        guard enabled != wantsTap else { return }
        wantsTap = enabled
        installObserversIfNeeded()
        syncTapPresence()
    }

    // MARK: - Decision

    fileprivate func decide(_ input: Input) -> Verdict {
        if input.isTagged { return .pass(zero: false) }
        let isDock = input.typeRaw == 30 && input.hidRaw == 23 && input.motionRaw == 1
        if isDock {
            switch input.phaseRaw {
            case 1:
                tracking = true
                fired = false
                return .swallow
            case 2:
                guard tracking else { return .pass(zero: false) }
                if !fired, input.progress != 0 {
                    fired = true
                    fire(progress: input.progress, velocityX: nil)
                }
                return .swallow
            case 4:
                guard tracking else { return .pass(zero: false) }
                if !fired, input.velocityX != 0 {
                    fired = true
                    fire(progress: nil, velocityX: input.velocityX)
                }
                tracking = false
                fired = false
                return .pass(zero: true)
            case 8:
                tracking = false
                fired = false
                return .swallow
            default:
                return tracking ? .swallow : .pass(zero: false)
            }
        }
        if input.typeRaw == 29 {
            return tracking ? .swallow : .pass(zero: false)
        }
        return .pass(zero: false)
    }

    private func fire(progress: Double?, velocityX: Double?) {
        let isRight: Bool
        if let progress {
            isRight = SpaceSwitchState.isRightSwipe(progress: progress)
        } else if let velocityX {
            isRight = SpaceSwitchState.isRightSwipe(velocityX: velocityX)
        } else {
            return
        }
        onSwipe?(SpaceSwitchState.direction(isRightSwipe: isRight))
    }

    // MARK: - Tap lifecycle

    private func installObserversIfNeeded() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidChange(active: false) }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidChange(active: true) }
                }, center: center)
        ]
    }

    private func sessionDidChange(active: Bool) {
        sessionActive = active
        tracking = false
        fired = false
        syncTapPresence()
    }

    private func syncTapPresence() {
        guard wantsTap, sessionActive else {
            tearDownTap()
            healthTicker?.unsubscribe(self)
            needsAccessibility = false
            return
        }
        healthTicker?.subscribe(self)
        installTapIfNeeded()
    }

    private func installTapIfNeeded() {
        guard tapPort == nil else { return }
        guard Permissions.isAccessibilityTrusted() else {
            needsAccessibility = true
            return
        }
        let mask: CGEventMask = (1 << 29) | (1 << 30)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: spaceSwipeEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            if !loggedTapFailure {
                NSLog("Tinycast: Failed to create space-swipe event tap")
                loggedTapFailure = true
            }
            needsAccessibility = true
            return
        }
        loggedTapFailure = false
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        needsAccessibility = false
    }

    private func tearDownTap() {
        tracking = false
        fired = false
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }

    fileprivate func tapWasDisabled() {
        tracking = false
        fired = false
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    func healthCheck() {
        guard wantsTap, sessionActive else { return }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
            needsAccessibility = true
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
    }
}
