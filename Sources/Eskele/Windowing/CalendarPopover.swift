import AppKit

/// The month that appears when the pointer rests on the clock.
///
/// An `NSDatePicker` in its graphical style rather than a hand-drawn grid: it already knows which
/// day the week starts on, how the month is named in the user's language, and which day today is —
/// all of which a grid of my own would get wrong for somebody.
@MainActor
final class CalendarPopover {
    private let panel: NSPanel
    private let picker = NSDatePicker()
    private var pending: DispatchWorkItem?

    /// Slower than the hover label. A calendar is a bigger interruption than a line of text, so it
    /// should not appear from brushing past the clock on the way to the Trash.
    private static let delay: TimeInterval = 0.45
    private static let padding: CGFloat = 8
    private static let gap: CGFloat = 6

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        // Read, not used: clicking a date would set a date on nothing.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)

        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = [.yearMonthDay]
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.sizeToFit()

        let effect = NSVisualEffectView()
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.material = .menu
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        effect.addSubview(picker)
        panel.contentView = effect
    }

    var appearance: NSAppearance? {
        get { panel.appearance }
        set { panel.appearance = newValue }
    }

    func schedule(beside rect: NSRect, edge: BarEdge, on screen: NSScreen?) {
        cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.show(beside: rect, edge: edge, on: screen) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CalendarPopover.delay, execute: work)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    func hide() {
        cancel()
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    private func show(beside rect: NSRect, edge: BarEdge, on screen: NSScreen?) {
        // Re-read every time: left open across midnight it would otherwise still be showing
        // yesterday, with yesterday circled.
        picker.dateValue = Date()
        picker.sizeToFit()

        let size = picker.fittingSize
        let frame = NSRect(
            x: 0, y: 0,
            width: size.width + 2 * CalendarPopover.padding,
            height: size.height + 2 * CalendarPopover.padding)
        picker.frame = NSRect(
            x: CalendarPopover.padding, y: CalendarPopover.padding,
            width: size.width, height: size.height)

        let bounds = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(
            HoverTooltip.place(frame, beside: rect, edge: edge, within: bounds), display: true)
        panel.orderFrontRegardless()
    }
}
