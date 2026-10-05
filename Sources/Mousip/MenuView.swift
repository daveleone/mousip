import ServiceManagement
import SwiftUI

/// State shown in the status panel. Toggles write straight through to `Settings`.
@MainActor
final class MenuModel: ObservableObject {
    enum Problem {
        case accessibility, restart, shortcutsDisabled
    }

    enum Action {
        case openAccessibilitySettings, openKeyboardSettings
        case testLeft, testRight, testMissionControl
        case quit
    }

    private let settings: Settings
    /// Called after a setting changes and on every action button.
    var onSettingsChange: () -> Void = {}
    var onAction: (Action) -> Void = { _ in }
    var onError: (Error) -> Void = { _ in }

    @Published var problem: Problem?
    /// Developer extras, shown when ⌥ is held while opening the panel.
    @Published var showsExtras = false

    @Published var isEnabled: Bool { didSet { settings.isEnabled = isEnabled; onSettingsChange() } }
    @Published var invertDirection: Bool { didSet { settings.invertDirection = invertDirection } }
    @Published var repeatWhileHeld: Bool { didSet { settings.repeatWhileHeld = repeatWhileHeld } }
    @Published var middleClickMissionControl: Bool {
        didSet { settings.middleClickMissionControl = middleClickMissionControl }
    }
    @Published var debugLogging: Bool { didSet { settings.debugLogging = debugLogging } }

    @Published var launchAtLogin: Bool {
        didSet {
            let service = SMAppService.mainApp
            guard launchAtLogin != (service.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                launchAtLogin = service.status == .enabled
                onError(error)
            }
        }
    }

    init(settings: Settings) {
        self.settings = settings
        isEnabled = settings.isEnabled
        invertDirection = settings.invertDirection
        repeatWhileHeld = settings.repeatWhileHeld
        middleClickMissionControl = settings.middleClickMissionControl
        debugLogging = settings.debugLogging
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Picks up changes made outside the panel (e.g. Launch at Login in System Settings).
    func reload() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func perform(_ action: Action) {
        onAction(action)
    }
}

struct MenuView: View {
    @ObservedObject var model: MenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let problem = model.problem {
                ProblemBanner(problem: problem, perform: model.perform)
            }

            Card(title: "Tilt Wheel", footer: "Hold ⌥ while tilting to scroll sideways as usual.") {
                SettingRow(icon: "arrow.left.arrow.right", tint: .blue, title: "Invert Direction",
                           isOn: $model.invertDirection)
                CardDivider()
                SettingRow(icon: "repeat", tint: .indigo, title: "Repeat While Held",
                           subtitle: "Keep switching while the wheel stays tilted",
                           isOn: $model.repeatWhileHeld)
            }

            Card(title: "Middle Click") {
                SettingRow(icon: "rectangle.3.group", tint: .purple, title: "Mission Control",
                           subtitle: "Only on empty spots: links, tabs and text work as usual",
                           isOn: $model.middleClickMissionControl)
            }

            Card(title: "General") {
                SettingRow(icon: "power", tint: .green, title: "Launch at Login", isOn: $model.launchAtLogin)
            }

            if model.showsExtras {
                Card(title: "Developer") {
                    HStack(spacing: 6) {
                        TestButton(icon: "arrow.left", title: "Left") { model.perform(.testLeft) }
                        TestButton(icon: "arrow.right", title: "Right") { model.perform(.testRight) }
                        TestButton(icon: "rectangle.3.group", title: "Mission Ctrl") {
                            model.perform(.testMissionControl)
                        }
                    }
                    .padding(8)
                    CardDivider()
                    SettingRow(icon: "ladybug", tint: .gray, title: "Debug Logging", isOn: $model.debugLogging)
                }
            }

            footer
        }
        .padding(14)
        .frame(width: 310)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mousip").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(status.color).frame(width: 7, height: 7)
                    Text(status.text).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("Enabled", isOn: $model.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(model.isEnabled ? "Pause Mousip" : "Resume Mousip")
        }
    }

    private var status: (text: String, color: Color) {
        switch model.problem {
        case .accessibility: return ("Needs Accessibility access", .orange)
        case .restart: return ("Restart needed", .orange)
        case .shortcutsDisabled where model.isEnabled: return ("Space shortcuts disabled", .orange)
        default: return model.isEnabled ? ("Active", .green) : ("Paused", .secondary)
        }
    }

    private var footer: some View {
        HStack {
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Version \(version)").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                model.perform(.quit)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Components

/// A rounded group of rows with an optional title above and note below.
private struct Card<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) { content }
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )

            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
    }
}

private struct CardDivider: View {
    var body: some View {
        Divider().padding(.leading, 44)
    }
}

/// An icon, a title and a switch. Clicking anywhere on the row flips the switch.
private struct SettingRow: View {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

private struct ProblemBanner: View {
    var problem: MenuModel.Problem
    var perform: (MenuModel.Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.title) { perform(action.action) }
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25))
        )
    }

    private var message: String {
        switch problem {
        case .accessibility: "Mousip needs the Accessibility permission to read the wheel and switch Spaces."
        case .restart: "Permission granted. Restart Mousip to activate it."
        case .shortcutsDisabled: "The “Move left/right a space” keyboard shortcuts are turned off."
        }
    }

    private var action: (title: String, action: MenuModel.Action)? {
        switch problem {
        case .accessibility: ("Grant Access…", .openAccessibilitySettings)
        case .restart: nil
        case .shortcutsDisabled: ("Enable Shortcuts…", .openKeyboardSettings)
        }
    }
}

private struct TestButton: View {
    var icon: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .controlSize(.small)
    }
}
