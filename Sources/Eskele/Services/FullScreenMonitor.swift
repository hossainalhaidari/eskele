import AppKit

/// Tracks which displays are currently showing a native full-screen space.
///
/// **This needs Accessibility.** There is no public API for "is the active space full-screen", and
/// the obvious permission-free guess — look for a window that covers the whole display — does not
/// work: an ordinary window the user has sized to fill the screen is byte-for-byte identical to a
/// full-screen one. Measured on macOS 26.6, that heuristic reported a plain editor window as
/// full-screen continuously, so it was removed rather than shipped as a source of random misbehaviour.
///
/// Without Accessibility this reports nothing, which makes the full-screen setting behave as
/// "Always Show" — the safe direction to fail in.
@MainActor
final class FullScreenMonitor {
    private(set) var fullScreenDisplays: Set<CGDirectDisplayID> = []
    var onChange: (() -> Void)?

    private let windows: WindowService
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    /// Displays the window sweep found a full-screen window on. The frontmost check below is
    /// immediate but sees only one app; the sweep sees every app, including one sitting full-screen
    /// on a display the user is not currently looking at.
    private var sweepDisplays: Set<CGDirectDisplayID> = []

    /// The space transition animates for about a second, and AX reports the old geometry until it
    /// settles, so one sample on the notification is not enough.
    private static let resampleDelays: [TimeInterval] = [0.4, 1.1]

    var requiresAccessibility: Bool { !windows.isTrusted }

    init(windows: WindowService) {
        self.windows = windows

        let center = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        refresh()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
    }

    func scheduleRefresh() {
        refresh()
        for delay in FullScreenMonitor.resampleDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// Only the frontmost app is examined. An app sitting full-screen on a second display while the
    /// user works elsewhere is not detected — acceptable, since the bar on that display is not in
    /// anyone's way at that moment.
    func setSweepDisplays(_ displays: Set<CGDirectDisplayID>) {
        guard sweepDisplays != displays else { return }
        sweepDisplays = displays
        refresh()
    }

    func refresh() {
        var detected = sweepDisplays
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let verdict = windows.focusedWindowFullScreen(pid: frontmost.processIdentifier),
           verdict.isFullScreen {
            detected.insert(verdict.display)
        }

        guard detected != fullScreenDisplays else { return }
        fullScreenDisplays = detected
        onChange?()
    }

    func isFullScreen(_ display: CGDirectDisplayID?) -> Bool {
        guard let display else { return false }
        return fullScreenDisplays.contains(display)
    }
}
