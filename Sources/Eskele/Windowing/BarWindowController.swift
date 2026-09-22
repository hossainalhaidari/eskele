import AppKit

/// Owns one bar panel on one screen and keeps its frame pinned to the chosen edge.
@MainActor
final class BarWindowController {
    let panel = BarPanel()
    let content = BarContentView()

    private(set) var screen: NSScreen
    private var settings: Settings

    private let trigger = EdgeTriggerWindow()
    private var isRevealed = true
    private var shownFrame: NSRect = .zero
    private var hiddenFrame: NSRect = .zero
    private var isFullScreen = false
    private var leaveTimer: Poll?
    private var revealWork: DispatchWorkItem?
    private var pointerLeftAt: Date?
    /// The app that was in front when the bar took the keyboard, which gets it back on Escape.
    private(set) var keyboardReturn: NSRunningApplication?
    private var resignKeyObserver: NSObjectProtocol?

    private static let slideDuration: TimeInterval = 0.16

    init(screen: NSScreen, settings: Settings, delegate: BarContentViewDelegate) {
        self.screen = screen
        self.settings = settings
        content.delegate = delegate
        panel.contentView = content
        panel.orderFrontRegardless()
        trigger.onEnter = { [weak self] in self?.pointerEnteredEdge() }
        content.onLeaveKeyboard = { [weak self] in self?.releaseKeyboard(restoringFocus: true) }
    }

    /// True when the bar should behave as if auto-hide were on: either the user asked for it, or we
    /// are in a full-screen space and they chose reveal-on-hover there.
    private var effectiveAutohide: Bool {
        if settings.autohide { return true }
        return isFullScreen && settings.fullScreenBehavior == .revealOnHover
    }

    private var isSuppressedByFullScreen: Bool {
        isFullScreen && settings.fullScreenBehavior == .hide
    }

    func update(items: [DockItem], settings: Settings, screen: NSScreen, isFullScreen: Bool) {
        let autohideWas = effectiveAutohide
        self.settings = settings
        self.screen = screen
        self.isFullScreen = isFullScreen
        // Coming out of an auto-hidden full-screen space should not leave the bar stranded off-screen.
        if autohideWas && !effectiveAutohide { isRevealed = true }

        // On the panel rather than the content view, so the tooltip and any menu it opens inherit
        // it too — a dark bar whose hover label is light reads as two different applications.
        panel.appearance = settings.appearance.nsAppearance

        // One row's thickness for the cells, every row of it for the window.
        content.configure(
            items: items,
            settings: settings,
            thickness: settings.rowThickness,
            scale: screen.backingScaleFactor
        )
        reposition(thickness: settings.totalThickness)
    }

    /// Positioned against `screen.frame`, not `visibleFrame`: we want the physical screen edge, both
    /// so the bar reads as part of the display's chrome and so it covers the strip the system Dock
    /// would otherwise reveal on hover.
    ///
    /// The one region we must not take is the menu bar's, which a left- or right-hand bar runs the
    /// full length of the display straight into.
    private func reposition(thickness: CGFloat) {
        let rect = BarFrameSolver.frame(
            screen: screen.frame,
            menuBarInset: ScreenMetrics.menuBarInset(for: screen),
            edge: settings.edge,
            spanMode: settings.spanMode,
            thickness: thickness,
            preferredLength: content.preferredLength,
            endMargin: 12
        )

        shownFrame = rect.integral
        hiddenFrame = BarWindowController.offscreenFrame(
            for: shownFrame, edge: settings.edge, thickness: thickness)
        content.needsLayout = true

        if isSuppressedByFullScreen {
            releaseKeyboard(restoringFocus: true)
            cancelAutohide()
            panel.orderOut(nil)
            return
        }

        if effectiveAutohide {
            positionTrigger()
            // Settings can change while the bar is out; keep whichever state we were in.
            panel.setFrame(isRevealed ? shownFrame : hiddenFrame, display: true)
            if isRevealed { startLeaveTracking() } else { trigger.orderFrontRegardless() }
        } else {
            cancelAutohide()
            isRevealed = true
            panel.setFrame(shownFrame, display: true)
        }
        panel.orderFrontRegardless()
    }

    // Teardown happens in `close()`, which the coordinator always calls; a nonisolated `deinit`
    // could not touch this main-actor state anyway.

    /// Slid entirely off the display, so nothing of the bar remains visible or clickable.
    private static func offscreenFrame(for frame: NSRect, edge: BarEdge, thickness: CGFloat) -> NSRect {
        var hidden = frame
        switch edge {
        case .bottom: hidden.origin.y -= thickness
        case .left: hidden.origin.x -= thickness
        case .right: hidden.origin.x += thickness
        }
        return hidden
    }

    // MARK: - Auto-hide

    /// The trigger spans exactly as much of the edge as the bar itself, so a bar that hugs its icons
    /// does not arm the whole screen edge — and a vertical bar does not arm the menu bar's corner.
    private func positionTrigger() {
        let t = EdgeTriggerWindow.thickness
        let frame = screen.frame
        let rect: NSRect = switch settings.edge {
        case .bottom:
            NSRect(x: shownFrame.minX, y: frame.minY, width: shownFrame.width, height: t)
        case .left:
            NSRect(x: frame.minX, y: shownFrame.minY, width: t, height: shownFrame.height)
        case .right:
            NSRect(x: frame.maxX - t, y: shownFrame.minY, width: t, height: shownFrame.height)
        }
        trigger.setFrame(rect.integral, display: false)
    }

    private func pointerEnteredEdge() {
        guard effectiveAutohide, !isRevealed else { return }
        revealWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reveal() }
        }
        revealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.revealDelay, execute: work)
    }

    /// The Apps Menu cell in screen coordinates, measured against the bar's *shown* frame.
    ///
    /// Against `shownFrame` rather than the live window frame because the hot key reveals a hidden
    /// bar first, and `reveal()` animates: read from the window mid-slide, the anchor would be
    /// wherever the bar had got to rather than where it is going.
    var appsMenuAnchor: NSRect {
        let local = content.appsMenuAnchorInBar
        return NSRect(
            x: shownFrame.minX + local.minX,
            y: shownFrame.minY + local.minY,
            width: local.width,
            height: local.height)
    }

    func reveal() {
        guard !isRevealed else { return }
        isRevealed = true
        trigger.orderOut(nil)
        panel.orderFrontRegardless()
        animate(to: shownFrame)
        pointerLeftAt = nil
        startLeaveTracking()
    }

    func hide() {
        guard isRevealed, effectiveAutohide else { return }
        // Sliding away with the keyboard still on it would leave focus in a bar nobody can see.
        releaseKeyboard(restoringFocus: true)
        content.hideTooltip()
        isRevealed = false
        stopLeaveTracking()
        animate(to: hiddenFrame)
        positionTrigger()
        trigger.orderFrontRegardless()
    }

    func toggleReveal() {
        guard effectiveAutohide else { return }
        if isRevealed { hide() } else { reveal() }
    }

    private func animate(to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = BarWindowController.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Polls only while the bar is out — the trigger window handles the idle case for free.
    private func startLeaveTracking() {
        stopLeaveTracking()
        leaveTimer = Poll(every: 0.1, tolerance: 0.05, stretchesInLowPowerMode: false) { [weak self] in
            self?.checkPointer()
        }
    }

    private func stopLeaveTracking() {
        leaveTimer?.invalidate()
        leaveTimer = nil
    }

    private func checkPointer() {
        guard effectiveAutohide, isRevealed else { return }
        // A menu is open or something is being dragged: leave the bar alone.
        guard !content.isInteracting else {
            pointerLeftAt = nil
            return
        }
        let hotZone = shownFrame.insetBy(dx: -8, dy: -8)
        if hotZone.contains(NSEvent.mouseLocation) {
            pointerLeftAt = nil
            return
        }
        guard let left = pointerLeftAt else {
            pointerLeftAt = Date()
            return
        }
        if Date().timeIntervalSince(left) >= settings.hideDelay { hide() }
    }

    private func cancelAutohide() {
        revealWork?.cancel()
        revealWork = nil
        stopLeaveTracking()
        pointerLeftAt = nil
        trigger.orderOut(nil)
    }

    // MARK: - Keyboard

    /// Whether this bar has the keyboard (§5.27).
    var hasKeyboard: Bool { panel.acceptsKeyboard }

    /// Moves focus to the bar: activates Eskele, makes the panel key, and puts the keyboard on the
    /// cell of the app that was in front.
    ///
    /// Activating is the cost, and it is the launcher's too: an agent is never the active app, and
    /// an inactive app's window receives no keys. What makes it bearable is that the keyboard goes
    /// back where it came from — see `releaseKeyboard`.
    ///
    /// - Parameter fallback: who to give the keyboard back to when Eskele is already in front —
    ///   because the launcher had it, and is handing over the app *it* took it from.
    /// - Returns: `false` when this bar cannot take it: full screen has put it away, or it has no
    ///   cell to put the keyboard on.
    @discardableResult
    func takeKeyboard(returningTo fallback: NSRunningApplication?) -> Bool {
        guard !hasKeyboard else { return true }
        guard !isSuppressedByFullScreen, panel.isVisible, BarNavigation.entry(in: content.items) != nil
        else { return false }

        reveal()
        let front = NSWorkspace.shared.frontmostApplication
        keyboardReturn = front == .current ? fallback : front
        panel.acceptsKeyboard = true
        // Before activating: until then the cells still say which app is in front.
        content.beginKeyboardNavigation()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        // However the keyboard leaves — Return opening an app, a click somewhere else, the launcher
        // taking over — the panel stops being key, and that is the one signal all of them share.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseKeyboard(restoringFocus: false) }
        }
        return true
    }

    /// - Parameter restoringFocus: hand the keyboard back to the app it was taken from. Only for
    ///   leaving on purpose — Escape, the key again — and only while Eskele is still in front: once
    ///   another app is, the user has already said where the keyboard goes.
    func releaseKeyboard(restoringFocus: Bool) {
        guard hasKeyboard else { return }
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        resignKeyObserver = nil
        content.endKeyboardNavigation()
        panel.acceptsKeyboard = false
        let returnApp = keyboardReturn
        keyboardReturn = nil

        guard restoringFocus, NSWorkspace.shared.frontmostApplication == .current else { return }
        if let returnApp, returnApp != .current, !returnApp.isTerminated {
            returnApp.activate()
        } else {
            // Nobody to go back to — the app that was in front has quit since. Stepping aside lets
            // macOS pick, which beats leaving the keyboard with an agent that owns no windows.
            NSApp.deactivate()
        }
    }

    func close() {
        releaseKeyboard(restoringFocus: true)
        cancelAutohide()
        content.stopPulse()
        content.hideTooltip()
        trigger.close()
        panel.orderOut(nil)
        panel.close()
    }
}
