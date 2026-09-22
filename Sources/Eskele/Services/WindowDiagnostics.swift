import AppKit
import ApplicationServices

/// What Accessibility says about every running app's windows, next to what the window server says.
///
/// `--diagnose` explains permissions; this explains what AX actually *reports*. The AX-dependent
/// features are the ones whose bugs are invisible from outside — a window silently missing from a
/// list looks exactly like a window that does not exist — so this puts AX's answer beside
/// `CGWindowList`'s, which needs no permission and sees every space. A window the window server has
/// and AX does not is the signature of a window we cannot reach.
@MainActor
enum WindowDiagnostics {
    static func report(service: WindowService) -> String {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var report = """
            accessibility: \(service.isTrusted ? "granted" : "NOT granted")
            active space:  \(spaceDescription())

            """

        let serverWindows = windowServerWindows()

        // The verdict the bar actually acts on. A display listed here makes "In Full Screen" apply,
        // so anything listed while the user is on an ordinary desktop is a bug in the making.
        var fullScreenDisplays: Set<CGDirectDisplayID> = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            fullScreenDisplays.formUnion(service.fullScreenDisplays(
                among: service.windows(for: app.processIdentifier, includingOffSpace: true)))
        }
        report += "displays in a full-screen space: "
        report += fullScreenDisplays.isEmpty ? "none\n\n" : "\(fullScreenDisplays.sorted())\n\n"

        // The menu-bar agents `AccessoryAppsService` would put on the bar, reported whether or not
        // the feature is switched on: the question this answers is "can we see that window at all",
        // which is worth answering before the setting is blamed for the answer being no.
        let accessory = AccessoryAppsService.scan(
            accessory: Set(
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .accessory }
                    .map(\.processIdentifier)))
        report += "menu-bar apps with a window: "
        report += accessory.isEmpty
            ? "none\n\n"
            : accessory
                .compactMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
                .sorted().joined(separator: ", ") + "\n\n"

        let listed = NSWorkspace.shared.runningApplications.filter {
            WindowInfoService.isTracked(
                policy: $0.activationPolicy, pid: $0.processIdentifier, accessory: accessory)
        }
        for app in listed {
            let pid = app.processIdentifier
            let windows = service.windows(for: pid, includingOffSpace: true)
            let listable = windows.filter(\.isListable)
            let wantsAttention = windows.contains(where: \.isDialog) && pid != frontmost

            report += "\(app.localizedName ?? "?")  pid \(pid)"
            report += app.activationPolicy == .accessory ? "  [menu-bar app]" : ""
            report += pid == frontmost ? "  [frontmost]" : ""
            report += wantsAttention ? "  [NEEDS ATTENTION]" : ""
            report += "\n  AX: \(windows.count) entries, \(listable.count) listable\n"
            for window in windows {
                report += "    \(describe(window))\n"
            }

            let server = serverWindows[pid] ?? []
            report += "  window server: \(server.count) plausible windows\n"
            for window in server {
                report += "    \(window)\n"
            }

            report += "  AXFocusedWindow: \(named(pid, kAXFocusedWindowAttribute))\n"
            report += "  AXMainWindow:    \(named(pid, kAXMainWindowAttribute))\n\n"
        }
        return report
    }

    private static func describe(_ window: AppWindow) -> String {
        let flags = [
            window.isListable ? "listed" : "skipped",
            window.subrole.isEmpty ? "no-subrole" : window.subrole,
            window.isFullScreen ? "FULLSCREEN" : nil,
            window.isMinimized ? "minimised" : nil,
            window.isDialog ? "DIALOG" : nil,
            window.isOffSpace ? "off-space" : nil,
            window.isMenuProxy ? "via-window-menu" : nil,
        ].compactMap { $0 }.joined(separator: " ")
        return "\(window.title.isEmpty ? "<untitled>" : window.title)  — \(flags)"
    }

    /// Layer-0 windows big enough to be real, across every space. Titles need Screen Recording, so
    /// this reports geometry — which is enough to count them and to spot a full-screen one.
    private static func windowServerWindows() -> [pid_t: [String]] {
        let list = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? []
        var byPID: [pid_t: [String]] = [:]
        let displays = NSScreen.screens.map(\.frame.size)

        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  // Toolbars, shadows and the menu-bar-height shims apps keep around.
                  width > 200, height > 120
            else { continue }

            let onscreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false
            // A window as wide as a display and nearly as tall is either full-screen or zoomed;
            // the window server cannot tell us which, only AX can, which is rather the point.
            let coversDisplay = displays.contains { width >= $0.width - 1 && height >= $0.height - 60 }
            let name = entry[kCGWindowName as String] as? String ?? ""
            byPID[pid, default: []].append(
                "\(Int(width))x\(Int(height))"
                + (onscreen ? " on-screen" : " off-space")
                + (coversDisplay ? " display-sized" : "")
                + (name.isEmpty ? "" : "  \"\(name)\""))
        }
        return byPID
    }

    private static func named(_ pid: pid_t, _ attribute: String) -> String {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute as CFString, &value) == .success,
              let value
        else { return "none" }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(value as! AXUIElement, kAXTitleAttribute as CFString, &title)
        return (title as? String).map { $0.isEmpty ? "<untitled>" : $0 } ?? "<no title>"
    }

    /// Whether the display the pointer is on is showing a full-screen space, as far as the
    /// frontmost app's focused window can tell us.
    private static func spaceDescription() -> String {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return "unknown" }
        let service = WindowService()
        guard let verdict = service.focusedWindowFullScreen(pid: frontmost.processIdentifier) else {
            return "unknown (frontmost app has no focused window)"
        }
        return verdict.isFullScreen ? "FULL SCREEN on display \(verdict.display)" : "normal"
    }
}
