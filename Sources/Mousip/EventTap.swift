import CoreGraphics

/// A session-wide event tap whose handler runs on the main run loop.
/// The handler returns `true` to consume the event.
@MainActor
final class EventTap {
    typealias Handler = @MainActor (CGEventType, CGEvent) -> Bool

    private(set) var isRunning = false
    private let name: String
    private let mask: CGEventMask
    private let handler: Handler
    private var port: CFMachPort?

    init(name: String, events: [CGEventType], handler: @escaping Handler) {
        self.name = name
        mask = events.reduce(0) { $0 | CGEventMask(1 << $1.rawValue) }
        self.handler = handler
    }

    /// Creates the tap. Fails if the app lacks the Accessibility permission.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("Could not create the \(self.name, privacy: .public) event tap (missing Accessibility permission?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        isRunning = true
        log.notice("\(self.name, privacy: .public) event tap active")
        return true
    }

    /// macOS disables the tap if the callback is too slow: turn it back on.
    fileprivate func reenable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        log.notice("\(self.name, privacy: .public) event tap re-enabled")
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        handler(type, event)
    }
}

/// C callback for the event tap: runs on the main run loop.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    default:
        nonisolated(unsafe) let event = event
        let consume = MainActor.assumeIsolated { tap.handle(type, event) }
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
