import AppKit
import CoreGraphics

enum SpaceDirection: Sendable {
    case left, right

    var opposite: SpaceDirection { self == .left ? .right : .left }
}

/// Switches Spaces by posting the system shortcut "Move left/right a space"
/// (System Settings › Keyboard › Keyboard Shortcuts › Mission Control), ⌃← / ⌃→ by default.
/// Works for both virtual desktops and full-screen apps.
@MainActor
final class SpaceSwitcher {
    struct Shortcut {
        var keyCode: CGKeyCode
        var flags: CGEventFlags
        var isEnabled: Bool
    }

    /// Reads the shortcut the user has configured, so customized shortcuts keep working.
    func shortcut(for direction: SpaceDirection) -> Shortcut {
        // System "symbolic hot key" IDs: 79 = Move left a space, 81 = Move right a space.
        systemShortcut(id: direction == .left ? "79" : "81", defaultKeyCode: direction == .left ? 123 : 124)
    }

    private func systemShortcut(id hotKeyID: String, defaultKeyCode: CGKeyCode) -> Shortcut {
        var shortcut = Shortcut(keyCode: defaultKeyCode, flags: .maskControl, isEnabled: true)

        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        guard let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any],
              let entry = hotKeys[hotKeyID] as? [String: Any]
        else { return shortcut }

        if let enabled = entry["enabled"] as? Bool {
            shortcut.isEnabled = enabled
        }
        // parameters = (ASCII character, key code, modifiers)
        if let value = entry["value"] as? [String: Any],
           let parameters = value["parameters"] as? [Int], parameters.count == 3 {
            shortcut.keyCode = CGKeyCode(parameters[1])
            shortcut.flags = CGEventFlags(rawValue: UInt64(parameters[2]))
        }
        return shortcut
    }

    var hasDisabledShortcut: Bool {
        !shortcut(for: .left).isEnabled || !shortcut(for: .right).isEnabled
    }

    func switchSpace(_ direction: SpaceDirection) {
        let shortcut = shortcut(for: direction)
        guard shortcut.isEnabled else {
            log.error("Shortcut for moving \(direction == .left ? "left" : "right", privacy: .public) a space is disabled")
            return
        }
        post(shortcut)
    }

    /// Opens (or closes) Mission Control by launching its app, which works whatever shortcut
    /// (if any) the user assigned to it: a synthetic F-key press isn't always recognized.
    func toggleMissionControl() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                log.error("Could not open Mission Control: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func post(_ shortcut: Shortcut) {
        var flags = shortcut.flags
        // Physical arrow keys always carry the Fn and numeric pad flags as well: mimic them.
        if (123...126).contains(shortcut.keyCode) {
            flags.formUnion([.maskSecondaryFn, .maskNumericPad])
        }

        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}
