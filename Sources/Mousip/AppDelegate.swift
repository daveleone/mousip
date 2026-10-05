import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let switcher = SpaceSwitcher()
    private lazy var interceptor = ScrollInterceptor(settings: settings)
    private lazy var middleClick = MiddleClickInterceptor(settings: settings)
    private lazy var model = MenuModel(settings: settings)
    private lazy var panel = StatusPanel(rootView: MenuView(model: model))
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mousip")
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        model.onSettingsChange = { [weak self] in self?.updateIcon() }
        model.onAction = { [weak self] in self?.perform($0) }
        model.onError = { [weak self] in self?.show($0) }
        panel.onClose = { [weak self] in self?.statusItem.button?.highlight(false) }

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
            self?.model.problem = self?.currentProblem()
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

    // MARK: - Panel

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.close()
            return
        }
        model.problem = currentProblem()
        model.showsExtras = NSEvent.modifierFlags.contains(.option)
        model.reload()
        guard let button = statusItem.button else { return }
        button.highlight(true)
        panel.show(below: button)
    }

    private func currentProblem() -> MenuModel.Problem? {
        if !AXIsProcessTrusted() { return .accessibility }
        if !interceptor.isRunning { return .restart }
        if switcher.hasDisabledShortcut { return .shortcutsDisabled }
        return nil
    }

    private func perform(_ action: MenuModel.Action) {
        switch action {
        case .openAccessibilitySettings:
            panel.close()
            openAccessibilitySettings()
        case .openKeyboardSettings:
            panel.close()
            openKeyboardSettings()
        case .testLeft:
            afterPanelCloses { [switcher] in switcher.switchSpace(.left) }
        case .testRight:
            afterPanelCloses { [switcher] in switcher.switchSpace(.right) }
        case .testMissionControl:
            afterPanelCloses { [switcher] in switcher.toggleMissionControl() }
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// Closes the panel and waits for it to fade before posting a shortcut.
    private func afterPanelCloses(_ action: @escaping @MainActor () -> Void) {
        panel.close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            action()
        }
    }

    private func show(_ error: Error) {
        panel.close()
        NSApp.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
    }

    private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private func open(_ url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }
}
