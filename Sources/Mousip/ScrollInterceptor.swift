import AppKit
import CoreGraphics
import os

let log = Logger(subsystem: "com.mousip.app", category: "scroll")

/// The fields of a scroll event we need, extracted in the tap callback.
struct ScrollSample: Sendable {
    var lineVertical: Int64
    var lineHorizontal: Int64
    var pointVertical: Double
    var pointHorizontal: Double
    /// `true` for trackpads and the Magic Mouse, `false` for notched scroll wheels.
    var isContinuous: Bool
    var flags: UInt64
    /// `true` if macOS has already inverted the deltas for "natural scrolling".
    var isDirectionInverted: Bool

    init(_ event: CGEvent) {
        lineVertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        lineHorizontal = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        pointVertical = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        pointHorizontal = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        flags = event.flags.rawValue
        let isHorizontal = lineHorizontal != 0 || pointHorizontal != 0
        isDirectionInverted = isHorizontal && (NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false)
    }

    var vertical: Double { lineVertical != 0 ? Double(lineVertical) : pointVertical }
    var horizontal: Double { lineHorizontal != 0 ? Double(lineHorizontal) : pointHorizontal }
}

/// Intercepts horizontal scrolling from a tilt wheel and turns it into Space switches.
/// Handled horizontal events are consumed, so apps don't scroll sideways.
@MainActor
final class ScrollInterceptor {
    var onSwitch: ((SpaceDirection) -> Void)?
    private(set) var isRunning = false

    private let settings: Settings
    private var tap: CFMachPort?

    // A single wheel tilt often produces a burst of events: we group them into one "gesture".
    /// Pause without horizontal events after which a new gesture starts.
    private static let gestureGap: TimeInterval = 0.3
    /// With "repeat while held", the interval between one Space switch and the next.
    private static let repeatInterval: TimeInterval = 0.45

    private var lastEventTime: TimeInterval = 0
    private var lastTriggerTime: TimeInterval = 0
    private var lastDirection: SpaceDirection?

    init(settings: Settings) {
        self.settings = settings
    }

    /// Creates the event tap. Fails if the app lacks the Accessibility permission.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("Could not create the event tap (missing Accessibility permission?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        isRunning = true
        log.notice("Event tap active")
        return true
    }

    /// macOS disables the tap if the callback is too slow: turn it back on.
    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        log.notice("Event tap re-enabled")
    }

    /// Returns `true` if the event should be consumed.
    fileprivate func handle(_ sample: ScrollSample) -> Bool {
        if settings.debugLogging {
            log.notice("""
                scroll v=\(sample.vertical, privacy: .public) h=\(sample.horizontal, privacy: .public) \
                continuous=\(sample.isContinuous, privacy: .public) inverted=\(sample.isDirectionInverted, privacy: .public) \
                flags=0x\(String(sample.flags, radix: 16), privacy: .public)
                """)
        }

        guard settings.isEnabled,
              !sample.isContinuous,
              sample.horizontal != 0,
              sample.vertical == 0
        else { return false }

        // ⇧ + wheel is macOS's "emulated" horizontal scroll; ⌥ lets you scroll sideways as usual.
        let flags = CGEventFlags(rawValue: sample.flags)
        if flags.contains(.maskShift) || flags.contains(.maskAlternate) { return false }

        // macOS convention (without natural scrolling): positive horizontal delta = wheel tilted left.
        let physical = sample.isDirectionInverted ? -sample.horizontal : sample.horizontal
        var direction: SpaceDirection = physical > 0 ? .left : .right
        if settings.invertDirection { direction = direction.opposite }

        registerTilt(direction)
        return true
    }

    private func registerTilt(_ direction: SpaceDirection) {
        let now = ProcessInfo.processInfo.systemUptime
        let isNewGesture = now - lastEventTime > Self.gestureGap || direction != lastDirection
        let shouldRepeat = settings.repeatWhileHeld && now - lastTriggerTime >= Self.repeatInterval
        lastEventTime = now
        guard isNewGesture || shouldRepeat else { return }

        lastDirection = direction
        lastTriggerTime = now
        if settings.debugLogging {
            log.notice("→ Space \(direction == .left ? "left" : "right", privacy: .public)")
        }
        onSwitch?(direction)
    }
}

/// C callback for the event tap: runs on the main run loop.
private func scrollTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<ScrollInterceptor>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { interceptor.reenable() }
        return Unmanaged.passUnretained(event)
    case .scrollWheel:
        let sample = ScrollSample(event)
        let consume = MainActor.assumeIsolated { interceptor.handle(sample) }
        return consume ? nil : Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
