import AppKit
import DockPrefsKit

/// Everything we write lives in one directory so a user can delete it and get a clean slate.
@MainActor
final class Persistence {
    static let shared = Persistence()

    let directory: URL

    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    private var layoutURL: URL { directory.appendingPathComponent("layout.json") }
    var dockBackupURL: URL { directory.appendingPathComponent("dock-backup.json") }
    private var recentsURL: URL { directory.appendingPathComponent("recents.json") }
    var badgesURL: URL { directory.appendingPathComponent("badges.json") }
    var progressURL: URL { directory.appendingPathComponent("progress.json") }
    var iconsURL: URL { directory.appendingPathComponent("Icons", isDirectory: true) }

    init(directory: URL? = nil) {
        self.directory = directory ?? SupportDirectory.url
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    // MARK: - Settings

    func loadSettings() -> Settings {
        load(Settings.self, from: settingsURL) ?? Settings()
    }

    func save(_ settings: Settings) {
        write(settings, to: settingsURL)
    }

    // MARK: - Layout

    func loadLayout() -> [PersistedItem] {
        (load(Layout.self, from: layoutURL) ?? Layout()).items
    }

    func saveLayout(_ items: [PersistedItem]) {
        write(Layout(version: 1, items: items), to: layoutURL)
    }

    /// A first-run layout so the bar is not an empty sliver. Anything not installed is skipped.
    func defaultLayout() -> [PersistedItem] {
        let candidates = [
            "com.apple.finder", "com.apple.Safari", "com.apple.mail",
            "com.apple.iCal", "com.apple.Notes", "com.apple.systempreferences",
            "com.apple.Terminal",
        ]
        return candidates.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return nil
            }
            return PersistedItem.make(for: url)
        }
    }

    // MARK: - Badges

    func loadBadgeConfiguration() -> BadgeConfiguration {
        load(BadgeConfiguration.self, from: badgesURL) ?? BadgeConfiguration()
    }

    /// Writes an empty, self-documenting badge file on first run.
    ///
    /// JSON has no comments, so the worked examples live in a key the decoder ignores — which is
    /// still the shortest path from "I want a number on Mail" to a number on Mail.
    func seedBadgeConfigurationIfMissing() {
        guard !FileManager.default.fileExists(atPath: badgesURL.path) else { return }
        let template = """
            {
              "sources": [],

              "_readme": [
                "The real Dock badges are read for you: nothing here is needed for Mail, Messages",
                "or anything else macOS already badges. This file is for the rest.",
                "",
                "Each source puts a number on one cell of the bar.",
                "bundleID: the app's bundle identifier, or \\"trash\\" for the Trash.",
                "command: run through /bin/sh; the first number in its output becomes the badge.",
                "interval: seconds between runs (5-3600, default 30).",
                "No badge is shown when the command prints nothing, fails, or yields 0 — in which",
                "case the app's real Dock badge is drawn instead. A command that does answer wins",
                "its cell, so it can override a badge as well as supply one.",
                "",
                "Both examples below are overrides: they count something slightly different from",
                "what the app itself badges. Delete them unless you want that difference."
              ],

              "_examples": [
                {
                  "bundleID": "com.apple.mail",
                  "command": "osascript -e 'tell application \\"Mail\\" to get unread count of inbox'",
                  "interval": 30
                },
                {
                  "bundleID": "com.apple.reminders",
                  "command": "osascript -e 'tell application \\"Reminders\\" to count (reminders whose completed is false)'",
                  "interval": 120
                }
              ]
            }
            """
        try? template.write(to: badgesURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Progress

    func loadProgressConfiguration() -> ProgressConfiguration {
        load(ProgressConfiguration.self, from: progressURL) ?? ProgressConfiguration()
    }

    /// The same self-documenting empty file as `badges.json`, for the same reason.
    func seedProgressConfigurationIfMissing() {
        guard !FileManager.default.fileExists(atPath: progressURL.path) else { return }
        let template = """
            {
              "sources": [],

              "_readme": [
                "Each source draws a progress bar across one cell of the bar.",
                "bundleID: the app's bundle identifier, or an absolute path for a folder cell.",
                "command: run through /bin/sh; the first number in its output becomes the bar.",
                "A number above 1 is read as a percentage, 0-1 as a fraction; a trailing % forces it.",
                "interval: seconds between runs (2-3600, default 5).",
                "No bar is drawn when the command prints nothing or fails.",
                "Music, Spotify and VLC are already known; turn on Media Progress in Settings.",
                "Files landing in a folder on the bar are picked up on their own, with no command."
              ],

              "_examples": [
                {
                  "bundleID": "com.apple.dt.Xcode",
                  "command": "cat /tmp/build-percent 2>/dev/null",
                  "interval": 2
                },
                {
                  "bundleID": "/Users/you/Renders",
                  "command": "echo $(( 100 * $(ls /Users/you/Renders | wc -l) / 240 ))%",
                  "interval": 10
                }
              ]
            }
            """
        try? template.write(to: progressURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Recent apps

    func loadRecents() -> [String] {
        load([String].self, from: recentsURL) ?? []
    }

    func saveRecents(_ bundleIDs: [String]) {
        write(bundleIDs, to: recentsURL)
    }

    // MARK: - IO

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Keep the bad file for diagnosis rather than silently overwriting the user's layout.
            let corrupt = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: corrupt)
            try? FileManager.default.moveItem(at: url, to: corrupt)
            NSLog("Eskele: could not read \(url.lastPathComponent) (\(error)); moved aside")
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? Self.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The format of every file here. Exporting settings uses it too, so an export and
    /// `settings.json` are the same bytes.
    nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
