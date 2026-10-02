import AppKit
import ApplicationServices

/// Turns a middle click on an "empty" spot (not a link, button, tab or text field) into Mission Control.
/// Clicks on interactive elements pass through untouched, so "open link in new tab",
/// "close tab", "paste" and so on keep working. A middle drag (canvas panning) is replayed to the app.
@MainActor
final class MiddleClickInterceptor {
    var onClick: (() -> Void)?
    var isRunning: Bool { tap.isRunning }

    private let settings: Settings
    private lazy var tap = EventTap(
        name: "Middle click",
        events: [.otherMouseDown, .otherMouseDragged, .otherMouseUp]
    ) { [unowned self] type, event in
        handle(type, event)
    }

    /// Marks the clicks we post ourselves, so the tap lets them through.
    private static let syntheticMarker: Int64 = 0x6D6F_7573 // "mous"
    /// Moving farther than this while the button is down turns the click into a drag (canvas panning, etc.).
    private static let dragThreshold: Double = 6
    private static let middleButton: Int64 = 2

    /// Roles on which a middle click means something: open a link in a new tab, close a tab, paste…
    private static let interactiveRoles: Set<String> = [
        "AXLink", "AXButton", "AXRadioButton", "AXTab", "AXCheckBox", "AXPopUpButton", "AXMenuButton",
        "AXComboBox", "AXTextField", "AXTextArea", "AXSearchField", "AXDisclosureTriangle", "AXSlider",
        "AXIncrementor", "AXMenuItem", "AXMenuBarItem", "AXDockItem",
    ]
    /// Containers where the search for an interactive ancestor stops.
    private static let boundaryRoles: Set<String> = ["AXWebArea", "AXWindow", "AXSheet", "AXApplication"]
    private static let maxAncestors = 12

    private let systemWide = AXUIElementCreateSystemWide()
    /// The location of a swallowed button press, waiting for its release.
    private var pendingClick: CGPoint?
    /// Apps already asked to expose their accessibility tree.
    private var preparedApps: Set<pid_t> = []

    init(settings: Settings) {
        self.settings = settings
        // Never stall the input pipeline for long on an unresponsive app.
        AXUIElementSetMessagingTimeout(systemWide, 0.15)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                if let pid { self?.prepareApp(pid) }
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        prepareFrontmostApp()
        return tap.start()
    }

    func prepareFrontmostApp() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            prepareApp(pid)
        }
    }

    /// Chromium and Electron apps build their web accessibility tree only when asked:
    /// without it a link looks like an empty area.
    private func prepareApp(_ pid: pid_t) {
        guard settings.isEnabled, settings.middleClickMissionControl,
              preparedApps.insert(pid).inserted
        else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: - Events

    /// Returns `true` if the event should be consumed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        if type == .otherMouseDown, settings.debugLogging {
            log.notice("mouse button \(button, privacy: .public) down")
        }
        guard button == Self.middleButton,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker
        else { return false }

        switch type {
        case .otherMouseDown:
            pendingClick = nil
            guard settings.isEnabled, settings.middleClickMissionControl,
                  event.flags.isDisjoint(with: [.maskCommand, .maskShift, .maskAlternate, .maskControl]),
                  !isOverInteractiveElement(event.location)
            else { return false }
            pendingClick = event.location
            return true

        case .otherMouseDragged:
            guard let origin = pendingClick else { return false }
            let location = event.location
            if hypot(location.x - origin.x, location.y - origin.y) > Self.dragThreshold {
                // It's a drag after all: replay the press so the app sees the whole gesture.
                pendingClick = nil
                postSynthetic(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                      mouseCursorPosition: origin, mouseButton: .center))
                postSynthetic(event.copy())
            }
            return true

        case .otherMouseUp:
            guard pendingClick != nil else { return false }
            pendingClick = nil
            if settings.debugLogging { log.notice("→ Mission Control") }
            onClick?()
            return true

        default:
            return false
        }
    }

    private func postSynthetic(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility

    /// `true` if the element under the cursor (or one of its ancestors) reacts to a middle click.
    /// When in doubt (no accessibility info, app not responding) the click is left alone.
    private func isOverInteractiveElement(_ point: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit
        else {
            if settings.debugLogging { log.notice("middle click: no accessibility info, passing through") }
            return true
        }

        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) == .success { prepareApp(pid) }

        var path: [String] = []
        defer {
            if settings.debugLogging {
                log.notice("middle click on \(path.joined(separator: " ← "), privacy: .public)")
            }
        }
        for _ in 0..<Self.maxAncestors {
            guard let role = stringAttribute(element, kAXRoleAttribute) else { return path.isEmpty }
            path.append(role)
            if Self.interactiveRoles.contains(role) { return true }
            if Self.boundaryRoles.contains(role) { return false }
            guard let parent = elementAttribute(element, kAXParentAttribute) else { return false }
            element = parent
        }
        return false
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
}
