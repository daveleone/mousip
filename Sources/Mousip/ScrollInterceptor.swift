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
    var isRunning: Bool { tap.isRunning }

    private let settings: Settings
    private lazy var tap = EventTap(name: "Scroll", events: [.scrollWheel]) { [unowned self] _, event in
        handle(ScrollSample(event))
    }

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

    @discardableResult
    func start() -> Bool { tap.start() }

    /// Returns `true` if the event should be consumed.
    private func handle(_ sample: ScrollSample) -> Bool {
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
