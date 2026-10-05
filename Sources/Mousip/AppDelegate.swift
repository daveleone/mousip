import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let switcher = SpaceSwitcher()
    private lazy var interceptor = ScrollInterceptor(settings: settings)
    private lazy var middleClick = MiddleClickInterceptor(settings: settings)
    private lazy var model = MenuModel(settings: settings)
    private lazy var updater = Updater(settings: settings)
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mousip")
        statusItem.menu = makeMenu()

        model.onSettingsChange = { [weak self] in self?.updateIcon() }
        model.onAction = { [weak self] in self?.perform($0) }
        model.onError = { [weak self] in self?.show($0) }
        updater.onStateChange = { [weak self] in self?.model.update = $0 }

        interceptor.onSwitch = { [switcher] direction in
            switcher.switchSpace(direction)
        }
        middleClick.onClick = { [switcher] in
            switcher.toggleMissionControl()
        }
        startWhenTrusted()
        updateIcon()
        updater.startAutomaticChecks()
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

    // MARK: - Menu

    /// A real NSMenu hosting the SwiftUI panel: unlike a custom window, an open menu keeps the
    /// menu bar visible in full-screen Spaces, and the system handles highlighting and dismissal.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem())  // holds the SwiftUI view, set on every open

        // Key equivalents only reach menu items while the menu is open.
        let quit = NSMenuItem(title: "Quit Mousip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.isHidden = true
        quit.allowsKeyEquivalentWhenHidden = true
        menu.addItem(quit)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.problem = currentProblem()
        model.showsExtras = NSEvent.modifierFlags.contains(.option)
        model.reload()

        // A fresh hosting view measures the current state right away; an existing one would
        // report its old size until the next run loop pass, cutting off newly shown sections.
        let view = MenuHostingView(rootView: MenuView(model: model))
        view.frame.size = view.fittingSize
        menu.items.first?.view = view
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
            closeMenu()
            openAccessibilitySettings()
        case .openKeyboardSettings:
            closeMenu()
            openKeyboardSettings()
        case .checkForUpdates:
            Task { await updater.check() }
        case .installUpdate:
            Task { await updater.install() }
        case .openReleaseNotes:
            closeMenu()
            if let url = updater.state.release?.notesURL {
                NSWorkspace.shared.open(url)
            }
        case .testLeft:
            afterMenuCloses { [switcher] in switcher.switchSpace(.left) }
        case .testRight:
            afterMenuCloses { [switcher] in switcher.switchSpace(.right) }
        case .testMissionControl:
            afterMenuCloses { [switcher] in switcher.toggleMissionControl() }
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func closeMenu() {
        statusItem.menu?.cancelTracking()
    }

    /// Closes the menu and waits for it to fade before posting a shortcut.
    private func afterMenuCloses(_ action: @escaping @MainActor () -> Void) {
        closeMenu()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            action()
        }
    }

    private func show(_ error: Error) {
        closeMenu()
        // Leave the menu's tracking loop before running a modal alert.
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
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
