import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let switcher = SpaceSwitcher()
    private lazy var interceptor = ScrollInterceptor(settings: settings)
    private lazy var middleClick = MiddleClickInterceptor(settings: settings)
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
        middleClick.onClick = { [switcher] in
            switcher.toggleMissionControl()
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
            startInterceptors()
            return
        }
        Task { @MainActor [weak self] in
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(1.5))
            }
            self?.startInterceptors()
            self?.updateIcon()
        }
    }

    private func startInterceptors() {
        interceptor.start()
        middleClick.start()
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

        // Only the essentials, plus problems when there are any. Hold ⌥ while opening for the extras.
        if !AXIsProcessTrusted() {
            menu.addItem(actionItem("⚠︎ Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        } else if !interceptor.isRunning {
            menu.addItem(infoItem("⚠︎ Restart Mousip to activate it"))
            menu.addItem(.separator())
        } else if switcher.hasDisabledShortcut {
            menu.addItem(actionItem("⚠︎ Enable “Move a space” Shortcuts…", #selector(openKeyboardSettings)))
            menu.addItem(.separator())
        }

        let enabled = toggleItem("Enabled", settings.isEnabled, #selector(toggleEnabled))
        enabled.toolTip = "Hold ⌥ while tilting the wheel to scroll sideways as usual."
        menu.addItem(enabled)
        menu.addItem(toggleItem("Invert Direction", settings.invertDirection, #selector(toggleInvertDirection)))
        menu.addItem(toggleItem("Repeat While Held", settings.repeatWhileHeld, #selector(toggleRepeat)))
        let missionControl = toggleItem("Middle Click for Mission Control", settings.middleClickMissionControl,
                                        #selector(toggleMiddleClick))
        missionControl.toolTip = "Only on empty spots: middle clicks on links, tabs, buttons and text work as usual."
        menu.addItem(missionControl)

        menu.addItem(.separator())
        menu.addItem(toggleItem("Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLaunchAtLogin)))

        if NSEvent.modifierFlags.contains(.option) {
            let testMenu = NSMenu()
            testMenu.addItem(actionItem("Space Left", #selector(testLeft)))
            testMenu.addItem(actionItem("Space Right", #selector(testRight)))
            testMenu.addItem(actionItem("Mission Control", #selector(testMissionControl)))
            let testItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
            testItem.submenu = testMenu
            menu.addItem(testItem)
            menu.addItem(toggleItem("Debug Logging", settings.debugLogging, #selector(toggleDebugLogging)))
        }

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

    @objc private func toggleMiddleClick() {
        settings.middleClickMissionControl.toggle()
    }

    @objc private func toggleDebugLogging() {
        settings.debugLogging.toggle()
    }

    @objc private func testLeft() { testSwitch(.left) }
    @objc private func testRight() { testSwitch(.right) }

    @objc private func testMissionControl() {
        afterMenuCloses { [switcher] in switcher.toggleMissionControl() }
    }

    private func testSwitch(_ direction: SpaceDirection) {
        afterMenuCloses { [switcher] in switcher.switchSpace(direction) }
    }

    /// Waits for the menu to close before posting a shortcut.
    private func afterMenuCloses(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            action()
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
