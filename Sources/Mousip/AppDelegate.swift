import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let switcher = SpaceSwitcher()
    private lazy var interceptor = ScrollInterceptor(settings: settings)
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Mousip")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        interceptor.onSwitch = { [switcher] direction in
            switcher.switchSpace(direction)
        }
        startWhenTrusted()
        updateIcon()
    }

    // MARK: - Permissions

    /// Requests the Accessibility permission (needed to intercept scrolling and post the shortcut)
    /// and starts the interceptor as soon as it is granted.
    private func startWhenTrusted() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            interceptor.start()
            return
        }
        Task { @MainActor [weak self] in
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(1.5))
            }
            self?.interceptor.start()
            self?.updateIcon()
        }
    }

    private var isWorking: Bool {
        interceptor.isRunning && settings.isEnabled
    }

    private func updateIcon() {
        statusItem.button?.appearsDisabled = !isWorking
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let trusted = AXIsProcessTrusted()
        let status: String
        if !trusted {
            status = "Accessibility permission missing"
        } else if !interceptor.isRunning {
            status = "Restart Mousip to activate it"
        } else if !settings.isEnabled {
            status = "Paused"
        } else {
            status = "Active: tilt the wheel to switch Spaces"
        }
        menu.addItem(infoItem(status))
        if trusted && interceptor.isRunning {
            menu.addItem(infoItem("Hold ⌥ for normal horizontal scrolling"))
        }

        if !trusted {
            menu.addItem(actionItem("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
        }
        if switcher.hasDisabledShortcut {
            menu.addItem(.separator())
            menu.addItem(infoItem("⚠︎ Mission Control \"Move a space\" shortcuts are disabled"))
            menu.addItem(actionItem("Open Keyboard Shortcuts…", #selector(openKeyboardSettings)))
        }

        menu.addItem(.separator())
        menu.addItem(toggleItem("Enabled", settings.isEnabled, #selector(toggleEnabled)))
        menu.addItem(toggleItem("Invert Direction", settings.invertDirection, #selector(toggleInvertDirection)))
        menu.addItem(toggleItem("Repeat While Wheel Is Held", settings.repeatWhileHeld, #selector(toggleRepeat)))

        menu.addItem(.separator())
        let testMenu = NSMenu()
        testMenu.addItem(actionItem("Space Left", #selector(testLeft)))
        testMenu.addItem(actionItem("Space Right", #selector(testRight)))
        let testItem = NSMenuItem(title: "Test Space Switch", action: nil, keyEquivalent: "")
        testItem.submenu = testMenu
        menu.addItem(testItem)
        menu.addItem(toggleItem("Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLaunchAtLogin)))
        menu.addItem(toggleItem("Debug Logging", settings.debugLogging, #selector(toggleDebugLogging)))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mousip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggleItem(_ title: String, _ isOn: Bool, _ action: Selector) -> NSMenuItem {
        let item = actionItem(title, action)
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        updateIcon()
    }

    @objc private func toggleInvertDirection() {
        settings.invertDirection.toggle()
    }

    @objc private func toggleRepeat() {
        settings.repeatWhileHeld.toggle()
    }

    @objc private func toggleDebugLogging() {
        settings.debugLogging.toggle()
    }

    @objc private func testLeft() { testSwitch(.left) }
    @objc private func testRight() { testSwitch(.right) }

    /// Waits for the menu to close before posting the shortcut.
    private func testSwitch(_ direction: SpaceDirection) {
        Task { @MainActor [switcher] in
            try? await Task.sleep(for: .milliseconds(300))
            switcher.switchSpace(direction)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private func open(_ url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }
}
