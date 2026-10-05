import AppKit
import SwiftUI

/// A borderless, translucent panel that drops down from the status item, Control Center style.
/// Closes on a click elsewhere, on Escape, or when it loses focus.
@MainActor
final class StatusPanel: NSPanel, NSWindowDelegate {
    private static let cornerRadius: CGFloat = 16
    private static let gap: CGFloat = 6

    private var clickMonitor: Any?
    /// Top-left corner the panel stays pinned to while its content grows or shrinks.
    private var anchor: NSPoint = .zero
    var onClose: () -> Void = {}

    init<Content: View>(rootView: Content) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        delegate = self

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.blendingMode = .behindWindow
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        // The window sizes itself to the SwiftUI content through these constraints.
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    /// Shows the panel below `button`, left-aligned with it and kept inside the screen.
    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main

        layoutIfNeeded()
        let size = frame.size
        var x = buttonFrame.minX
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + Self.gap), visible.maxX - size.width - Self.gap)
        }
        anchor = NSPoint(x: x, y: buttonFrame.minY - Self.gap)
        setFrameTopLeftPoint(anchor)

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    override func close() {
        guard isVisible else { return }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        super.close()
        onClose()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowDidResize(_ notification: Notification) {
        if isVisible {
            setFrameTopLeftPoint(anchor)
        }
    }

    /// A stretchable rounded-rectangle mask for the visual effect view.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
