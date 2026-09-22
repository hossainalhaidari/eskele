import AppKit
import ApplicationServices

/// Event-driven notifications for window changes, so the bar does not have to poll for them.
///
/// The workspace only tells us about apps — launching, quitting, activating. Anything that happens
/// *inside* an app (a window opening, closing, being renamed) raises nothing at that level, which is
/// why this started life as a 2s poll. Polling fast enough to feel immediate would mean an AX sweep
/// several times a second; these notifications cost nothing while idle and arrive at once.
@MainActor
final class WindowObserver {
    /// Called with the pid whose windows changed, and the AX notification that said so. The name
    /// matters for `kAXSheetCreatedNotification`: a sheet is not in the app's window list, so the
    /// notification is the only trace of it we ever get.
    var onChange: ((pid_t, String) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: [pid_t: [AXUIElement]] = [:]

    /// Delivered by the application element itself.
    private static let applicationNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXSheetCreatedNotification,
    ]

    /// Only ever delivered by the individual window they concern, so these have to be registered
    /// again whenever an app's set of windows changes.
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
    ]

    init() {
        axWindowChangeHandler = { pid, notification in
            MainActor.assumeIsolated { sharedWindowObserver?.onChange?(pid, notification) }
        }
        sharedWindowObserver = self
    }

    /// Starts observing the given apps and stops observing any others.
    func sync(pids: Set<pid_t>) {
        for pid in pids where observers[pid] == nil { start(pid) }
        for pid in Array(observers.keys) where !pids.contains(pid) { stop(pid) }
    }

    /// Registers the per-window notifications for any windows not already being watched.
    ///
    /// Deliberately additive. Re-registering everything on each refresh cost about a second per
    /// sweep, because `AXObserverRemoveNotification` against a window that has since closed blocks
    /// until the messaging timeout — and a closed window is exactly the case that triggers a
    /// refresh. Registrations on a destroyed element die with it, so there is nothing to clean up.
    func observe(windows: [AppWindow], for pid: pid_t) {
        guard let observer = observers[pid] else { return }

        let known = observedWindows[pid] ?? []
        let unwatched = windows.filter { window in
            !known.contains { CFEqual($0, window.element) }
        }
        guard !unwatched.isEmpty else { return }

        let context = UnsafeMutableRawPointer(bitPattern: Int(pid))
        for window in unwatched {
            for name in WindowObserver.windowNotifications {
                AXObserverAddNotification(observer, window.element, name as CFString, context)
            }
        }
        // Only the windows still open are worth remembering; the rest can never match again.
        observedWindows[pid] = windows.map(\.element)
    }

    func stopAll() {
        for pid in Array(observers.keys) { stop(pid) }
        sharedWindowObserver = nil
        axWindowChangeHandler = nil
    }

    private func start(_ pid: pid_t) {
        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success,
              let observer
        else { return }

        let application = AXUIElementCreateApplication(pid)
        let context = UnsafeMutableRawPointer(bitPattern: Int(pid))
        for name in WindowObserver.applicationNotifications {
            AXObserverAddNotification(observer, application, name as CFString, context)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func stop(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observedWindows.removeValue(forKey: pid)
    }
}

// The AX callback is a C function pointer and cannot capture, so it reaches the observer through
// file-scope globals. Both are only ever touched on the main thread: the callback fires on the run
// loop the observer's source was added to, which is the main one.
private nonisolated(unsafe) weak var sharedWindowObserver: WindowObserver?
private nonisolated(unsafe) var axWindowChangeHandler: (@Sendable (pid_t, String) -> Void)?

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    axWindowChangeHandler?(pid_t(Int(bitPattern: context)), notification as String)
}
