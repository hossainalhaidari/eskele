import AppKit

/// A sliver of window along the screen edge whose only job is to notice the pointer arriving.
///
/// This is why revealing an auto-hidden bar needs no permissions: a global `NSEvent` monitor would
/// be the obvious approach, but mouse-moved monitors are exactly the kind of thing macOS gates
/// behind Accessibility. A tracking area in our own window is free, and costs nothing when idle —
/// unlike polling the pointer.
final class EdgeTriggerWindow: NSPanel {
    /// Deliberately more than 1pt: a single point is hard to hit when the pointer is moving fast and
    /// the window server coalesces motion events.
    static let thickness: CGFloat = 2

    var onEnter: (() -> Void)? {
        get { triggerView.onEnter }
        set { triggerView.onEnter = newValue }
    }

    private let triggerView = TriggerView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: EdgeTriggerWindow.thickness),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        // Above the bar itself, so it still gets the pointer when the two overlap.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
        contentView = triggerView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TriggerView: NSView {
    var onEnter: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // A window with a fully transparent content view is not hit-tested. An almost-invisible
        // fill keeps it in the event path without being perceptible.
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.002).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
}
