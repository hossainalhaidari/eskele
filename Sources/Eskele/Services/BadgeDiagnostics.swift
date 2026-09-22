import AppKit
import ApplicationServices

/// What the Dock's own tiles say, next to what the bar concluded from them.
///
/// A missing badge has several indistinguishable causes from the outside — Accessibility was never
/// granted, the app is not badging at all, its badge is not a number, or the tile could not be
/// matched to the app the bar knows. This prints the raw attribute for every tile, so a report of
/// "Mail shows nothing" can be answered with what the Dock was actually drawing.
///
/// Must be run through LaunchServices to mean anything — a process started from a shell reports the
/// terminal's Accessibility permission, not Eskele's:
///
///     open -n <Eskele.app> --args --diagnose-badges
@MainActor
enum BadgeDiagnostics {
    static func report(persistence: Persistence, settings: Settings) -> String {
        let trusted = AXIsProcessTrusted()
        var report = """
            Eskele — badges

            settings
              show badges:   \(settings.showBadges ? "on" : "OFF — no badge is drawn from any source")
              accessibility: \(trusted ? "granted" : "NOT granted — the Dock's own badges cannot be read")

            dock tiles
            """

        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return report + "\n  no Dock process is running\n" }

        let element = AXUIElementCreateApplication(dock.processIdentifier)
        let tiles = children(of: element).flatMap(children(of:))
        if tiles.isEmpty {
            report += trusted
                ? "\n  the Dock reported no tiles\n"
                : "\n  unreadable without Accessibility\n"
        }
        for tile in tiles {
            let title = value(tile, kAXTitleAttribute) as? String ?? "—"
            let subrole = value(tile, kAXSubroleAttribute) as? String ?? "—"
            let label = value(tile, "AXStatusLabel") as? String
            let url = value(tile, kAXURLAttribute) as? URL
            let identifier = url.flatMap { Bundle(url: $0)?.bundleIdentifier }

            report += "\n  \(title)  [\(subrole.replacingOccurrences(of: "AX", with: ""))]\n"
            report += "    AXStatusLabel: \(label.map { "\"\($0)\"" } ?? "none")\n"
            if let label, BadgeService.firstNumber(in: label) == nil {
                report += "      no number in it — nothing to draw\n"
            }
            report += "    bundle ID:     \(identifier ?? "could not be resolved from \(url?.path ?? "no URL")")\n"
        }

        let sources = persistence.loadBadgeConfiguration().sources.filter(\.isEnabled)
        report += "\nconfigured commands\n"
        if sources.isEmpty {
            report += "  none — every badge below comes from the Dock\n"
        }
        for source in sources {
            report += "  \(source.bundleID) every \(Int(source.period))s: \(source.command)\n"
        }

        // The verdict, from the same code path the bar uses.
        let reader = DockBadgeReader()
        reader.isEnabled = true
        report += "\nwhat the bar would draw\n"
        let badges = reader.badges
        reader.stop()
        if badges.isEmpty {
            report += "  nothing from the Dock\n"
        }
        for (identifier, count) in badges.sorted(by: { $0.key < $1.key }) {
            let overridden = sources.contains { $0.bundleID == identifier }
            report += "  \(identifier): \(count)\(overridden ? "  (a command overrides this)" : "")\n"
        }
        return report
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
        else { return nil }
        return result
    }
}
