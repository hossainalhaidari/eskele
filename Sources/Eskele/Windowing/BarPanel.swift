import AppKit

/// The bar's window.
///
/// Level 21 = `kCGDockWindowLevel + 1`: above the system Dock (so we occlude its reveal strip even
/// if the preference-based suppression is ever defeated) and below the menu bar and menus.
final class BarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
    }

    /// Set only while the bar has been handed the keyboard (§5.27), which is the one time it should
    /// take focus.
    var acceptsKeyboard = false

    /// Otherwise never take focus: clicking a cell must not deactivate whatever the user was
    /// working in before we get the chance to activate the app they picked.
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}
