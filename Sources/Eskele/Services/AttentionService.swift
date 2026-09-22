import AppKit

/// Tracks which apps are asking to be looked at.
///
/// **What macOS does not let us see.** `NSApplication.requestUserAttention` — the call behind a
/// bouncing Dock icon — is delivered privately to the Dock process. There is no notification, no
/// `NSRunningApplication` property and no Accessibility attribute that reports it, for the same
/// reason badges are unreadable (ARCHITECTURE §2, row 11): the state lives in the Dock, not in the
/// app. So a literal "is it bouncing?" is out of reach.
///
/// **What it does let us see**, given the Accessibility permission the window list already uses, is
/// the thing bouncing usually accompanies: the app has put a modal in front of the user while they
/// were working somewhere else. Two shapes of that are visible —
///
/// - a window whose AX subrole is `AXDialog` or `AXSystemDialog`, which every sweep re-checks, and
/// - a sheet, which is a child of its parent window rather than an entry in the window list, so
///   `kAXSheetCreatedNotification` is the only trace of it. That one is latched and cleared when the
///   user next activates the app — the same moment a bouncing icon would stop.
///
/// An app that is frontmost never needs attention: the user is already looking at it.
@MainActor
final class AttentionService {
    private(set) var pids: Set<pid_t> = []
    var onChange: (() -> Void)?

    /// Apps whose sheet we were told about and which the user has not visited since.
    private var latched: Set<pid_t> = []
    private var dialogs: Set<pid_t> = []
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Read the pid out here: the notification itself is not Sendable, but the number is.
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                MainActor.assumeIsolated { self?.clear(pid) }
            })
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
    }

    func noteSheet(pid: pid_t) {
        // A sheet on the app you are already using is not a summons.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else { return }
        guard !latched.contains(pid) else { return }
        latched.insert(pid)
        recompute()
    }

    func setDialogPIDs(_ next: Set<pid_t>) {
        guard dialogs != next else { return }
        dialogs = next
        recompute()
    }

    /// Visiting an app answers whatever it was asking.
    ///
    /// Always recomputes, even when this app was not the one asking: the app the user *left* may
    /// have a dialog of its own that only counts now that it is no longer in front of them.
    private func clear(_ pid: pid_t?) {
        if let pid {
            latched.remove(pid)
            dialogs.remove(pid)
        }
        recompute()
    }

    private func recompute() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let next = latched.union(dialogs).subtracting(frontmost.map { [$0] } ?? [])
        guard next != pids else { return }
        pids = next
        onChange?()
    }
}
