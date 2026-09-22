import AppKit

/// The launcher's window.
///
/// The one window in this app that takes keyboard focus, because a search field is useless without
/// it. `NSMenu`, which the launcher used to be, runs its own event-tracking loop and hands key
/// events to itself; a view-based menu item can hold a search field but never the first responder,
/// and menu windows answer `false` to `canBecomeKey` by design. So this is a panel.
///
/// `.nonactivatingPanel` keeps the *bar* from stealing focus when this opens over it; the app is
/// activated deliberately by the controller instead, and the previously frontmost app is put back
/// in front when the launcher closes without launching anything.
final class LauncherPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        // Menu level: above the bar and the system Dock, below nothing the user is looking at.
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    /// Key, but never main: an agent's launcher is not a document window.
    override var canBecomeMain: Bool { false }
}
