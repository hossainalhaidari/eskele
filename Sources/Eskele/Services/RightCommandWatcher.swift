import AppKit

/// Fires when the right ⌘ key is tapped on its own — the Windows key's gesture, on a keyboard that
/// has no Windows key.
///
/// **Why this one costs a permission.** The other two Apps Menu keys are combinations, which Carbon
/// registers without asking for anything (see `GlobalHotKey`). A bare modifier is not a combination:
/// there is no key press to register, only a flag going up and coming back down, and the only way to
/// see that from outside the frontmost app is `NSEvent.addGlobalMonitorForEvents(.flagsChanged)`,
/// which macOS delivers to trusted processes alone. Polling `NSEvent.modifierFlags` — the trick
/// `ModifierWatcher` uses to stay permission-free — cannot work here: it would see ⌘ appear and
/// disappear during ⌘S exactly as it does during a tap, because the S is invisible without the same
/// permission. So this is the one shortcut that is offered with a condition attached.
///
/// **What counts as a tap.** Right ⌘ goes down with nothing else already held, nothing else happens
/// while it is down, and it comes back up promptly. A key press, a mouse click, or another modifier
/// joining in cancels it, so ⌘S and ⌘-click never open the launcher; so does holding it, because a
/// held ⌘ is someone reaching for a combination they have not finished typing.
@MainActor
final class RightCommandWatcher {
    var onTap: (() -> Void)?

    var isEnabled: Bool = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    /// Whether the permission this needs has been granted. The setting can be chosen without it —
    /// the preferences pane says so rather than refusing the choice.
    var isTrusted: Bool { AXIsProcessTrusted() }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Whether right ⌘ is down right now, and when it went down. Tracked as a transition rather
    /// than read per event, because a second modifier joining in re-reports the ⌘ that is already
    /// held — which would otherwise restart the clock on a press that should have been cancelled.
    private var isDown = false
    private var pressedAt = Date.distantPast
    /// Something happened while ⌘ was held, so releasing it is the end of a combination.
    private var isDisqualified = false

    /// Longer than any tap, shorter than a deliberate hold. A ⌘ still down after this is someone
    /// part-way through a combination, not someone asking for the launcher.
    private static let holdLimit: TimeInterval = 0.4

    /// The device-dependent bit for the *right* command key. `NSEvent.ModifierFlags.command` says a
    /// command key is down; only these raw bits say which one, and the left key must stay alone
    /// because ⌘ on the left is where every shortcut on the machine begins.
    private static let rightCommandMask: UInt = 0x0000_0010

    /// The modifiers that disqualify a press by joining it.
    private static let otherModifiers: NSEvent.ModifierFlags = [
        .shift, .control, .option, .function,
    ]

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isDown = false
        isDisqualified = false
    }

    private func start() {
        // Global sees the rest of the system; local sees the events that land on Eskele itself,
        // which is what a second tap has to reach to close a launcher that is already open.
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            // A key or a click while ⌘ is held: this was a combination after all.
            isDisqualified = true
            return
        }

        let flags = event.modifierFlags
        let rightIsDown = flags.rawValue & RightCommandWatcher.rightCommandMask != 0

        if rightIsDown, !isDown {
            isDown = true
            pressedAt = Date()
            // Down alongside something else already held is a combination from the start.
            isDisqualified = !flags.intersection(RightCommandWatcher.otherModifiers).isEmpty
        } else if !rightIsDown, isDown {
            isDown = false
            let held = Date().timeIntervalSince(pressedAt)
            guard !isDisqualified, held <= RightCommandWatcher.holdLimit else { return }
            onTap?()
        } else if isDown {
            // Another modifier came or went while ⌘ was held.
            isDisqualified = true
        }
    }
}
