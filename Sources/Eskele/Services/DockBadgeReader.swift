import AppKit
import ApplicationServices

/// Reads the real Dock badges — the numbers macOS itself draws on the Dock's tiles.
///
/// **How this is possible at all.** A badge lives in the owning app's `NSDockTile` and is handed
/// privately to the Dock, so no public API asks an app for its own badge. But the Dock is an
/// ordinary application, and its tiles are ordinary Accessibility elements: each one carries an
/// `AXStatusLabel` holding exactly the string the Dock is drawing. Measured against a test app and
/// against Mail receiving a live message, that attribute is the badge, updated as it changes, and
/// it stays readable while Eskele has the Dock hidden. Accessibility is the only permission needed —
/// the same one the window counts already ask for.
///
/// **Why it polls.** Badge changes arrive as no notification: registering for `AXValueChanged`,
/// `AXTitleChanged` and `AXLayoutChanged` on the Dock all return `kAXErrorNotificationUnsupported`,
/// and nothing fires on a change. A sweep of every tile measured at well under two milliseconds, so
/// a poll a second or two apart costs less than the window sweep already running.
///
/// **What it cannot do.** A badge that is not a number — the plain dot some apps show — has no
/// number to draw, and is reported as no badge. An app that is neither running nor kept in the
/// system Dock has no tile, but it also has no way to badge, so there is nothing to miss.
///
/// **The one real gap.** A badge lives in the Dock process, and Eskele restarts the Dock to hide
/// it. Measured: a badge set before that restart is gone from the new Dock's tile, because macOS
/// does not re-push it — the same thing that happens on any `killall Dock`. So a count that was
/// already standing when Eskele launched stays missing until the app next changes it, which for a
/// mail count means the next message. Nothing can ask an app to re-publish its badge, so this is
/// documented rather than worked around.
@MainActor
final class DockBadgeReader {
    /// Latest badge per bundle ID. Absent means "no badge".
    private(set) var badges: [String: Int] = [:]
    var onChange: (() -> Void)?

    /// Off while the bar is not drawing badges, so the poll costs nothing when nobody is looking.
    var isEnabled: Bool = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    private var poll: Poll?
    /// The Dock's application element, with the pid it was made for. Eskele restarts the Dock to
    /// hide it, so the pid changes underneath us and the cached element goes stale with it.
    private var dock: (pid: pid_t, element: AXUIElement)?
    /// Bundle ID per tile URL. A tile answers with the app's location; turning that into an
    /// identifier reads the app's `Info.plist`, which is not something to do every two seconds.
    private var bundleIDByURL: [String: String] = [:]

    /// Frequent enough that a new message badges the bar while the user is still looking at it,
    /// rare enough to disappear into the noise. See the sweep cost above.
    private static let interval: TimeInterval = 2

    /// The Dock's own attribute for the string on a tile. Not in the `kAX…` constants Swift
    /// imports, but long-standing and stable — it is what the Dock's own Accessibility support
    /// publishes, and what VoiceOver reads out as "3 items".
    private static let statusLabel = "AXStatusLabel"

    func stop() {
        poll?.invalidate()
        poll = nil
        dock = nil
        guard !badges.isEmpty else { return }
        badges = [:]
        onChange?()
    }

    private func start() {
        poll = Poll(every: DockBadgeReader.interval, tolerance: DockBadgeReader.interval / 2) {
            [weak self] in self?.sweep()
        }
        sweep()
    }

    /// Re-reads every tile. Cheap enough to do wholesale: the alternative is tracking which tiles
    /// came and went, which costs more than reading them all.
    private func sweep() {
        guard isTrusted, let dock = dockElement() else {
            guard !badges.isEmpty else { return }
            badges = [:]
            onChange?()
            return
        }

        var found: [String: Int] = [:]
        for list in children(of: dock) {
            for tile in children(of: list) {
                guard subrole(of: tile) == "AXApplicationDockItem",
                      let label = value(tile, DockBadgeReader.statusLabel) as? String,
                      let count = DockBadgeReader.count(fromStatusLabel: label),
                      let bundleID = bundleID(of: tile)
                else { continue }
                // Two tiles for one app is not a thing the Dock does, but a maximum rather than a
                // last-one-wins keeps the answer stable if it ever were.
                found[bundleID] = max(found[bundleID] ?? 0, count)
            }
        }

        guard found != badges else { return }
        badges = found
        onChange?()
    }

    /// The number to draw for a tile's label, or `nil` when there is none to draw.
    ///
    /// The Dock draws a string, not a number: mostly a count, sometimes `"99+"`, and for a few apps
    /// a bare dot meaning "something". A dot has no number in it and is reported as no badge, which
    /// is the honest answer for a cell whose badge is a number or nothing.
    nonisolated static func count(fromStatusLabel label: String) -> Int? {
        guard let count = BadgeService.firstNumber(in: label), count > 0 else { return nil }
        return count
    }

    /// The Dock's application element, remade whenever the Dock process has been replaced.
    private func dockElement() -> AXUIElement? {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else {
            dock = nil
            return nil
        }
        if let dock, dock.pid == app.processIdentifier { return dock.element }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        dock = (app.processIdentifier, element)
        return element
    }

    /// The app a tile stands for, via the file URL the tile reports.
    ///
    /// By URL rather than by title, because a title is the user-facing name — localised, and not
    /// unique across two apps of the same name in different places.
    private func bundleID(of tile: AXUIElement) -> String? {
        guard let url = value(tile, kAXURLAttribute) as? URL else { return nil }
        let key = url.path
        if let cached = bundleIDByURL[key] { return cached }
        guard let identifier = Bundle(url: url)?.bundleIdentifier else { return nil }
        bundleIDByURL[key] = identifier
        return identifier
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func subrole(of element: AXUIElement) -> String? {
        value(element, kAXSubroleAttribute) as? String
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
        else { return nil }
        return result
    }
}
