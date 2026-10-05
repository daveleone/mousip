import AppKit
import Security

/// Checks GitHub Releases for a newer version, and installs it in place of the running app.
@MainActor
final class Updater {
    struct Release: Equatable {
        var version: String
        var archiveURL: URL
        var notesURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case checkFailed(String)
        case available(Release)
        case installing(Release)
        case installFailed(Release, String)

        var release: Release? {
            switch self {
            case .available(let release), .installing(let release), .installFailed(let release, _): release
            default: nil
            }
        }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/daveleone/mousip/releases/latest")!
    private static let archiveName = "Mousip.zip"
    private static let checkInterval: Duration = .seconds(24 * 60 * 60)

    private let settings: Settings
    private(set) var state: State = .idle {
        didSet { onStateChange(state) }
    }
    var onStateChange: (State) -> Void = { _ in }

    init(settings: Settings) {
        self.settings = settings
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Checks shortly after launch and then once a day, while automatic checks are on.
    func startAutomaticChecks() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            while let self {
                if settings.checkForUpdates {
                    await check(quietly: true)
                }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// Looks for a newer release. A quiet check doesn't report "up to date" or network errors.
    func check(quietly: Bool = false) async {
        switch state {
        case .checking, .installing: return
        default: break
        }
        let previous = state
        state = .checking
        do {
            let release = try await Self.fetchLatestRelease()
            if Self.isVersion(release.version, newerThan: Self.currentVersion) {
                state = .available(release)
            } else {
                state = quietly ? .idle : .upToDate
            }
        } catch {
            log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = quietly ? (previous.release.map(State.available) ?? .idle) : .checkFailed(error.localizedDescription)
        }
    }

    /// Downloads and verifies the release, swaps it in for the running app and relaunches.
    func install() async {
        guard let release = state.release else { return }
        state = .installing(release)
        do {
            let appURL = Bundle.main.bundleURL
            let newAppURL = try await Self.download(release)
            let isAdHoc = Self.teamIdentifier(of: newAppURL) == nil
            // macOS allows replacing the bundle of a running app: the old files stay mapped.
            _ = try FileManager.default.replaceItemAt(appURL, withItemAt: newAppURL)
            try Self.relaunch(appURL, resetAccessibility: isAdHoc)
            NSApp.terminate(nil)
        } catch {
            log.error("Update failed: \(error.localizedDescription, privacy: .public)")
            state = .installFailed(release, error.localizedDescription)
        }
    }

    // MARK: - Steps

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            var name: String
            var browserDownloadUrl: URL
        }

        var tagName: String
        var htmlUrl: URL
        var draft: Bool
        var prerelease: Bool
        var assets: [Asset]
    }

    private static func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Mousip/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("GitHub didn't return the latest release.")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let latest = try decoder.decode(GitHubRelease.self, from: data)
        guard !latest.draft, !latest.prerelease,
              let archive = latest.assets.first(where: { $0.name == archiveName })
        else { throw UpdateError("The latest release has no \(archiveName).") }

        return Release(version: String(latest.tagName.trimmingPrefix("v")),
                       archiveURL: archive.browserDownloadUrl, notesURL: latest.htmlUrl)
    }

    /// Downloads and unpacks the archive, and checks it really is a newer, intact Mousip.
    private static func download(_ release: Release) async throws -> URL {
        let (archive, response) = try await URLSession.shared.download(from: release.archiveURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("The download failed.")
        }

        // A folder on the app's volume, so the final swap is a rename.
        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: Bundle.main.bundleURL, create: true)
        try await run("/usr/bin/ditto", "-x", "-k", archive.path, folder.path)
        try? FileManager.default.removeItem(at: archive)

        let newAppURL = folder.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
        guard let bundle = Bundle(url: newAppURL),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              isVersion(version, newerThan: currentVersion)
        else { throw UpdateError("The downloaded app isn't a newer Mousip.") }

        guard hasValidSignature(newAppURL) else {
            throw UpdateError("The downloaded app's signature is invalid.")
        }
        // Once releases are signed with a Developer ID, only accept the same developer.
        if let team = teamIdentifier(of: Bundle.main.bundleURL), teamIdentifier(of: newAppURL) != team {
            throw UpdateError("The downloaded app is signed by a different developer.")
        }
        return newAppURL
    }

    /// Reopens the app once this process has quit. An ad-hoc signed build has a new identity,
    /// so its old Accessibility entry is cleared and the new build asks again.
    private static func relaunch(_ appURL: URL, resetAccessibility: Bool) throws {
        var script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; "
        if resetAccessibility, let bundleID = Bundle.main.bundleIdentifier {
            script += "/usr/bin/tccutil reset Accessibility '\(bundleID)' >/dev/null 2>&1; "
        }
        script += "/usr/bin/open \"$0\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, appURL.path]
        try process.run()
    }

    // MARK: - Helpers

    nonisolated static func isVersion(_ version: String, newerThan current: String) -> Bool {
        let parse = { (string: String) in string.split(separator: ".").map { Int($0) ?? 0 } }
        let (a, b) = (parse(version), parse(current))
        for index in 0..<max(a.count, b.count) {
            let (x, y) = (index < a.count ? a[index] : 0, index < b.count ? b[index] : 0)
            if x != y { return x > y }
        }
        return false
    }

    private static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        return SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess ? code : nil
    }

    private static func hasValidSignature(_ url: URL) -> Bool {
        guard let code = staticCode(url) else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }

    /// Ad-hoc builds lose the Accessibility permission on every update.
    static var isAdHocSigned: Bool {
        teamIdentifier(of: Bundle.main.bundleURL) == nil
    }

    /// The Developer ID team, or nil for an ad-hoc signature.
    private static func teamIdentifier(of url: URL) -> String? {
        guard let code = staticCode(url) else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func run(_ path: String, _ arguments: String...) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError("Couldn't unpack the update."))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct UpdateError: LocalizedError {
    var errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
