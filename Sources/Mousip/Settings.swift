import Foundation

/// User preferences, stored in UserDefaults.
@MainActor
final class Settings {
    private enum Key {
        static let enabled = "enabled"
        static let invertDirection = "invertDirection"
        static let repeatWhileHeld = "repeatWhileHeld"
        static let middleClickMissionControl = "middleClickMissionControl"
        static let debugLogging = "debugLogging"
    }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.invertDirection: false,
            Key.repeatWhileHeld: false,
            Key.middleClickMissionControl: false,
            Key.debugLogging: false,
        ])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// Flips the tilt → Space direction mapping.
    var invertDirection: Bool {
        get { defaults.bool(forKey: Key.invertDirection) }
        set { defaults.set(newValue, forKey: Key.invertDirection) }
    }

    /// Keeps switching Spaces at a fixed interval while the wheel is held tilted.
    var repeatWhileHeld: Bool {
        get { defaults.bool(forKey: Key.repeatWhileHeld) }
        set { defaults.set(newValue, forKey: Key.repeatWhileHeld) }
    }

    /// Opens Mission Control on a middle click that doesn't land on a link, button, tab or text.
    var middleClickMissionControl: Bool {
        get { defaults.bool(forKey: Key.middleClickMissionControl) }
        set { defaults.set(newValue, forKey: Key.middleClickMissionControl) }
    }

    /// Writes every scroll event to the system log (subsystem "com.mousip.app").
    var debugLogging: Bool {
        get { defaults.bool(forKey: Key.debugLogging) }
        set { defaults.set(newValue, forKey: Key.debugLogging) }
    }
}
