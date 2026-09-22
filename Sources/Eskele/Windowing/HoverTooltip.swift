import AppKit

/// The label that appears when the pointer rests on a cell.
///
/// Deliberately not `NSView.toolTip`. AppKit's tooltips are driven by the tooltip manager, which
/// expects an ordinary app with an ordinary key window; this bar lives in a borderless,
/// non-activating panel belonging to an agent that is never active, and tooltips there are at best
/// unreliable. Owning the panel also means it can be placed against the bar's edge rather than at
/// the pointer, which is what a taskbar does.
@MainActor
final class HoverTooltip {
    private let panel: NSPanel
    private let label = HoverTooltip.makeLabel()
    private let thumbnail = NSImageView()
    private let effect = NSVisualEffectView()
    private var pending: DispatchWorkItem?

    /// Bumped by every `schedule` and `hide`. A preview arrives long after the hover that asked for
    /// it, and by then the pointer may be on another cell — or off the bar entirely — so a capture
    /// is only shown if the tooltip it belongs to is still the one on screen.
    private var generation = 0

    /// Long enough that sweeping along a full-width bar does not strobe, short enough to feel like
    /// an answer to hovering rather than an accident.
    static let delay: TimeInterval = 0.4
    private static let padding = NSSize(width: 9, height: 5)
    private static let gap: CGFloat = 6
    /// Space between the thumbnail and the title under it.
    static let previewGap: CGFloat = 5
    /// A preview is a glance, not a window: past this it stops helping and starts covering the
    /// screen it is describing.
    static let maximumPreview = NSSize(width: 280, height: 190)

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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        // One above the bar, so it is never occluded by the strip it belongs to.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)

        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.material = .toolTip
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 5
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 3
        thumbnail.layer?.masksToBounds = true
        thumbnail.isHidden = true

        effect.addSubview(thumbnail)
        effect.addSubview(label)
        panel.contentView = effect
    }

    /// Shows `text` beside `rect` (in screen coordinates) after the hover delay.
    ///
    /// - Parameter preview: asked for a picture only once the delay has elapsed, so sweeping along a
    ///   full-width bar never captures anything. The text appears the moment the delay is up and the
    ///   thumbnail fills in behind it, which is what keeps the label as quick as it was before
    ///   previews existed.
    func schedule(
        _ text: String,
        beside rect: NSRect,
        edge: BarEdge,
        on screen: NSScreen?,
        preview: (() async -> NSImage?)? = nil
    ) {
        cancel()
        guard !text.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.show(text, image: nil, beside: rect, edge: edge, on: screen)
                guard let preview else { return }
                let token = self.generation
                Task { [weak self] in
                    let image = await preview()
                    guard let self, let image, self.generation == token else { return }
                    self.show(text, image: image, beside: rect, edge: edge, on: screen)
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HoverTooltip.delay, execute: work)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        generation &+= 1
    }

    func hide() {
        cancel()
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    /// Follows the bar's own appearance. The tooltip is a separate window, so it inherits nothing
    /// from the panel it belongs to — a dark bar with a light hover label reads as two applications.
    var appearance: NSAppearance? {
        get { panel.appearance }
        set { panel.appearance = newValue }
    }

    private func show(
        _ text: String, image: NSImage?, beside rect: NSRect, edge: BarEdge, on screen: NSScreen?
    ) {
        let bounds = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        // Never wider than half the display: a window title can be arbitrarily long.
        let maximum = max(120, bounds.width / 2)
        let textSize = HoverTooltip.contentSize(
            of: label, showing: text, maximumWidth: maximum - 2 * HoverTooltip.padding.width)
        let layout = HoverTooltip.layout(
            textSize: textSize, previewSize: image.map(HoverTooltip.fitted) ?? .zero)

        thumbnail.image = image
        thumbnail.isHidden = image == nil
        thumbnail.frame = layout.preview
        label.frame = layout.label

        panel.setFrame(
            HoverTooltip.place(layout.frame, beside: rect, edge: edge, within: bounds), display: true)
        panel.orderFrontRegardless()
    }

    /// The thumbnail's drawn size: scaled to fit inside `maximumPreview`, keeping its aspect ratio,
    /// and never scaled up past the pixels actually captured.
    static func fitted(_ image: NSImage) -> NSSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return .zero }
        let factor = min(
            1,
            min(maximumPreview.width / size.width, maximumPreview.height / size.height))
        return NSSize(
            width: max(1, (size.width * factor).rounded()),
            height: max(1, (size.height * factor).rounded()))
    }

    /// Where the thumbnail and the title sit, and how big the panel has to be to hold them.
    ///
    /// Pure, because the arithmetic has three cases that are tedious to reach by hand — no preview,
    /// a preview wider than its title, and a title wider than its preview — and getting the last one
    /// wrong truncates a window title that had plenty of room.
    static func layout(textSize: NSSize, previewSize: NSSize)
        -> (frame: NSRect, preview: NSRect, label: NSRect) {
        let hasPreview = previewSize.width > 0 && previewSize.height > 0
        let contentWidth = max(textSize.width, hasPreview ? previewSize.width : 0)
        let contentHeight = textSize.height + (hasPreview ? previewSize.height + previewGap : 0)

        let frame = NSRect(
            x: 0, y: 0,
            width: contentWidth + 2 * padding.width,
            height: contentHeight + 2 * padding.height)

        // Bottom-up: the panel is not flipped, so the label sits below the thumbnail.
        let label = NSRect(
            x: (frame.width - textSize.width) / 2,
            y: padding.height,
            width: textSize.width,
            height: textSize.height)
        let preview = hasPreview
            ? NSRect(
                x: (frame.width - previewSize.width) / 2,
                y: label.maxY + previewGap,
                width: previewSize.width,
                height: previewSize.height)
            : .zero
        return (frame.integral, preview.integral, label.integral)
    }

    /// The tooltip's label, built the one way it is built — a factory so a test can measure exactly
    /// what the tooltip measures.
    static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }

    /// The size `label` needs in order to draw `text` in full, clamped to `maximumWidth`.
    ///
    /// From `cellSize`, **not** `intrinsicContentSize`. The latter reports the width of the glyphs
    /// alone, while `NSTextFieldCell` insets the text it draws by 2pt on each side — so a frame
    /// sized from the intrinsic width is 4pt short of what it takes to draw. `.byTruncatingTail`
    /// does not degrade gracefully over 4pt: it drops characters and appends an ellipsis, which is
    /// how a 45pt-wide "Terminal" came out as "Ter…".
    static func contentSize(of label: NSTextField, showing text: String, maximumWidth: CGFloat) -> NSSize {
        label.stringValue = text
        let needed = label.cell?.cellSize ?? label.intrinsicContentSize
        return NSSize(width: min(ceil(needed.width), maximumWidth), height: ceil(needed.height))
    }

    /// Puts the label on the screen-facing side of the bar, aligned to the cell, and keeps it on the
    /// display. Pure so the clamping can be tested rather than discovered on a second monitor.
    static func place(_ frame: NSRect, beside rect: NSRect, edge: BarEdge, within bounds: NSRect) -> NSRect {
        var placed = frame
        switch edge {
        case .bottom:
            placed.origin = NSPoint(x: rect.midX - frame.width / 2, y: rect.maxY + gap)
        case .left:
            placed.origin = NSPoint(x: rect.maxX + gap, y: rect.midY - frame.height / 2)
        case .right:
            placed.origin = NSPoint(x: rect.minX - gap - frame.width, y: rect.midY - frame.height / 2)
        }
        placed.origin.x = min(max(placed.origin.x, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
        placed.origin.y = min(max(placed.origin.y, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
        return placed.integral
    }
}
