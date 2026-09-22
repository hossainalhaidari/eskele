import AppKit

@MainActor
protocol ItemViewDelegate: AnyObject {
    func itemViewBeginInteraction(_ view: ItemView)
    func itemViewEndInteraction(_ view: ItemView)
    func itemView(_ view: ItemView, clicked action: ClickAction)
    func itemViewMenu(for view: ItemView) -> NSMenu?
    func itemViewShouldBeginDrag(_ view: ItemView) -> Bool
    func itemViewDraggedOutOfBar(_ view: ItemView, at screenPoint: NSPoint)
    func itemView(_ view: ItemView, hoverChanged isHovered: Bool)
}

/// A single cell: icon, hover highlight, running indicator, drag source.
final class ItemView: NSView {
    weak var delegate: ItemViewDelegate?

    var item: DockItem { didSet { needsDisplay = true } }
    var edge: BarEdge { didSet { needsDisplay = true } }
    var metrics: BarMetrics { didSet { needsDisplay = true } }
    var icon: NSImage? { didSet { needsDisplay = true } }
    var isDropTarget = false { didSet { needsDisplay = true } }
    /// This cell has room to draw the app's name beside its icon.
    var showsLabel = false { didSet { needsDisplay = true } }
    /// Compact bars reserve a strip for the running dot. Labelled bars show running state as a
    /// button fill instead, so the lane goes away and the icons grow into it.
    var usesIndicatorLane = true { didSet { needsDisplay = true } }
    /// 0…1, driven by the strip's pulse timer. Only read when the item needs attention.
    var attentionPhase: CGFloat = 0 { didSet { if item.needsAttention { needsDisplay = true } } }
    /// Zero-based slot this cell answers to while ⌃⌥ is held; nil the rest of the time, and for
    /// cells no key addresses.
    var slotNumber: Int? { didSet { if slotNumber != oldValue { needsDisplay = true } } }
    /// Processor and memory figures to draw over this cell while ⇧⌥ is held; nil the rest of the
    /// time, and for cells that are not a running app.
    var activity: ActivitySample? { didSet { if activity != oldValue { needsDisplay = true } } }
    /// What this cell is part-way through — a track, a file operation, a command's number — or nil
    /// when it is not part-way through anything.
    var progress: ProgressReport? { didSet { if progress != oldValue { needsDisplay = true } } }
    /// The keyboard is on this cell. Set by the strip, which owns where the keyboard is.
    var hasKeyboardFocus = false { didSet { if hasKeyboardFocus != oldValue { needsDisplay = true } } }

    /// How far the pointer may travel before a press becomes a drag rather than a click.
    static let dragThreshold: CGFloat = 4
    /// AppKit numbers the buttons from zero, so the wheel is the third.
    private static let middleButton = 2

    private var isHovered = false { didSet { needsDisplay = true } }
    private var mouseDownPoint: NSPoint?
    private var isDragging = false
    /// Set when the drag began with ⌘ held: an explicit "move this", which must not double as
    /// "take it off the bar" if the pointer strays outside while rearranging.
    private var isMoveOnly = false

    /// ⌘ at the start of the drag *or* right now, so the user can reach for it mid-drag once they
    /// see the disappearing-item cursor — which is exactly when they realise they want it.
    private var isMoveGesture: Bool {
        isMoveOnly || NSEvent.modifierFlags.contains(.command)
    }
    private var trackingArea: NSTrackingArea?

    init(item: DockItem, edge: BarEdge, metrics: BarMetrics) {
        self.item = item
        self.edge = edge
        self.metrics = metrics
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Tracking

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

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        delegate?.itemView(self, hoverChanged: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        delegate?.itemView(self, hoverChanged: false)
    }

    // MARK: - Geometry

    /// The lane reserved for the running indicator always sits on the screen-facing edge, so the
    /// dot is between the icon and the outside of the display — as it is in the system Dock.
    /// Across the bar the icon is pinned `outerInset` from the screen-facing edge; along it, a
    /// labelled button puts the icon at the leading edge and everything else centres it.
    private var iconRect: NSRect {
        let size = metrics.iconSize
        switch edge {
        case .bottom:
            let x = showsLabel ? metrics.horizontalPadding : (bounds.width - size) / 2
            return NSRect(x: x, y: metrics.outerInset, width: size, height: size).integral
        case .left:
            return NSRect(x: metrics.outerInset, y: (bounds.height - size) / 2, width: size, height: size).integral
        case .right:
            return NSRect(
                x: bounds.width - metrics.outerInset - size,
                y: (bounds.height - size) / 2,
                width: size, height: size
            ).integral
        }
    }

    // MARK: - Drawing

    /// Set by the strip: the lines the clock cell reads, already formatted for this edge.
    var clockLines: [String] = []
    var clockStyle: ClockStyle = .digital
    /// The moment the dial shows. Settable so it can be drawn at a known time and checked.
    var clockDate = Date()

    override func draw(_ dirtyRect: NSRect) {
        if item.isSeparator {
            drawSeparator()
            return
        }
        // Over everything, the clock included — it returns early below.
        defer { if hasKeyboardFocus { drawKeyboardFocus() } }

        drawBackground()
        // Under the icon and the name, which are what the cell is for. A labelled button that filled
        // over its own label would be reporting progress by hiding the thing it is progressing.
        if let progress, !usesIndicatorLane { drawProgressFill(progress) }

        if item.isClock {
            switch clockStyle {
            case .digital: drawDigitalClock()
            case .analog: drawDial()
            }
            return
        }

        if let icon {
            // Hidden apps read as dimmed, matching how the system Dock treats them.
            icon.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: item.isHidden ? 0.55 : 1.0
            )
        }

        // Stripes under the label, not over it: the name and the window title are information, and
        // trading them away to report a status the icon can carry on its own is a poor exchange.
        drawStatusStripes()
        if showsLabel { drawLabel() }
        drawIndicator()
        drawBadge()
        if let activity { drawActivity(activity) }
        if let slotNumber { drawSlotNumber(slotNumber) }
    }

    /// Processor and memory use, over the cell, while ⇧⌥ is held.
    ///
    /// A scrim rather than a chip in a corner: two figures need more room than a corner has, and
    /// unlike the slot number this is the thing you are reading — you already know which app you are
    /// looking at, because you went to it deliberately. The icon stays faintly visible through the
    /// scrim so the column can still be scanned.
    ///
    /// A labelled button has room to put the figures where the name is, so it does, and keeps its
    /// icon untouched.
    private func drawActivity(_ sample: ActivitySample) {
        let cpu = ActivitySample.cpuText(sample.cpu)
        if showsLabel {
            drawActivityLabel(cpu: cpu, memory: ActivitySample.memoryText(sample.memory))
        } else {
            drawActivityScrim(cpu: cpu, memory: ActivitySample.compactMemoryText(sample.memory))
        }
    }

    /// Two stacked lines over the icon, for a cell one icon thick.
    private func drawActivityScrim(cpu: String, memory: String) {
        let rect = backgroundRect
        let radius = max(4, metrics.iconSize * 0.2)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        // Dark enough to carry white text, light enough that the icon still shows through it —
        // "which app is eating the battery" is not a question you can answer off a covered icon.
        // The shadow below is what buys the extra contrast the missing opacity would have given.
        NSColor(white: 0.07, alpha: 0.58).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        // Sized to the cell rather than fixed: the two lines have to fit a 32pt bar as well as a
        // 48pt one, and monospaced digits stop the width jumping as the numbers change.
        let size = max(7, (rect.height * 0.27).rounded())
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 2.5
        shadow.shadowOffset = .zero

        let lines = [
            (cpu, NSColor.white),
            (memory, NSColor.white.withAlphaComponent(0.82)),
        ]
        let lineHeight = ceil(font.ascender - font.descender)
        var y = rect.midY + lineHeight - 1
        for (text, colour) in lines {
            y -= lineHeight
            (text as NSString).draw(
                in: NSRect(x: rect.minX, y: y, width: rect.width, height: lineHeight),
                withAttributes: [
                    .font: font, .foregroundColor: colour, .paragraphStyle: paragraph,
                    .shadow: shadow,
                ])
        }
    }

    /// The figures in place of the app's name, on a labelled button.
    private func drawActivityLabel(cpu: String, memory: String) {
        let x = iconRect.maxX + metrics.labelGap
        let width = bounds.maxX - metrics.horizontalPadding - x
        guard width > 8 else { return }

        // Painted over the name rather than beside it — there is only one label's worth of room, and
        // the icon already says which app this is.
        let strip = NSRect(x: x - 2, y: backgroundRect.minY, width: width + 4, height: backgroundRect.height)
        NSColor(white: 0.09, alpha: 0.80).setFill()
        NSBezierPath(roundedRect: strip.intersection(backgroundRect), xRadius: 3, yRadius: 3).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = "\(cpu)  ·  \(memory)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: metrics.labelFont.pointSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let height = ceil(text.size(withAttributes: attributes).height)
        text.draw(
            in: NSRect(x: x, y: bounds.midY - height / 2, width: width, height: height),
            withAttributes: attributes)
    }

    /// Diagonal hatching across the cell for an app that is starting or has stopped answering.
    ///
    /// Over the icon rather than behind it, because behind an icon that fills its cell is nowhere at
    /// all — an icons-only bar has no visible background to tint. Struck at a low alpha so the icon
    /// still reads through: the question the stripes answer is "what is wrong with *this* app",
    /// which needs the app to stay recognisable.
    ///
    /// The badge and the ⌃⌥ chip are drawn afterwards, so neither ends up behind the hatching.
    private func drawStatusStripes() {
        guard let colour = statusStripeColour else { return }
        let rect = backgroundRect
        guard rect.width > 1, rect.height > 1 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Clipped to the cell's own slab so a full-width labelled button does not bleed into its
        // neighbours, and a compact cell keeps its rounded corners.
        NSBezierPath(
            roundedRect: rect,
            xRadius: max(4, metrics.iconSize * 0.2),
            yRadius: max(4, metrics.iconSize * 0.2)
        ).addClip()

        let weight = max(1.5, (metrics.iconSize * 0.09).rounded())
        let gap = weight * 2.6
        let path = NSBezierPath()
        path.lineWidth = weight
        // 45°, so the run starts a full cell height to the left of the slab and ends past its right.
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            path.move(to: NSPoint(x: x, y: rect.minY))
            path.line(to: NSPoint(x: x + rect.height, y: rect.maxY))
            x += gap
        }
        colour.setStroke()
        path.stroke()
    }

    /// Red for an app that has stopped answering, neutral for one that is merely starting.
    ///
    /// `labelColor` rather than uBar's literal white: it has to be visible on a light bar as well as
    /// a dark one, and "the colour text would be" is what that means on this platform.
    private var statusStripeColour: NSColor? {
        if item.isUnresponsive { return NSColor.systemRed.withAlphaComponent(0.55) }
        if item.isLaunching { return NSColor.labelColor.withAlphaComponent(0.28) }
        return nil
    }

    /// The ⌃⌥ number, on the icon's inward bottom corner, while the modifiers are held.
    ///
    /// In a corner rather than over the middle, because the question the overlay answers is "which
    /// number is Safari?" — a chip large enough to be read comfortably is also large enough to hide
    /// the icon that makes the number worth knowing, and at Small it hides it completely.
    ///
    /// Diagonally opposite the badge, which sits on the top outward corner, so the two can never
    /// land on top of each other. Near-black rather than the accent colour: white on a yellow accent
    /// is barely legible, and a coloured capsule here would read as another badge.
    private func drawSlotNumber(_ slot: Int) {
        let icon = iconRect
        let side = max(14, (icon.width * 0.55).rounded())
        // Centred on the corner itself, then pulled back inside the cell's own slab — on a bar one
        // icon thick there is no room to hang over the edge.
        var rect = NSRect(
            x: icon.minX - side * 0.35,
            y: icon.minY - side * 0.35,
            width: side,
            height: side)
        let limit = backgroundRect
        rect.origin.x = min(max(rect.origin.x, limit.minX), max(limit.minX, limit.maxX - side))
        rect.origin.y = min(max(rect.origin.y, limit.minY), max(limit.minY, limit.maxY - side))
        rect = rect.integral

        let radius = side * 0.28
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor(white: 0.11, alpha: 0.92).setFill()
        path.fill()
        // Separates the chip from a dark icon, which would otherwise swallow its edge.
        NSColor.white.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = GlobalHotKey.slotLabel(slot) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: (side * 0.60).rounded(), weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes)
    }

    // MARK: - Badge

    /// The unread-style number, on the icon's outward top corner.
    ///
    /// Drawn over the icon rather than beside it so it lands in the same place whether the cell is a
    /// bare icon or a labelled button — the number has to be findable at a glance in both.
    private func drawBadge() {
        guard let badge = item.badge, badge > 0 else { return }

        let text = (badge > 99 ? "99+" : "\(badge)") as NSString
        let height = max(11, (metrics.iconSize * 0.44).rounded())
        let font = NSFont.systemFont(ofSize: (height * 0.68).rounded(), weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let width = max(height, ceil(textSize.width) + height * 0.55)

        let icon = iconRect
        var rect = NSRect(
            x: icon.maxX - width * 0.55,
            y: icon.maxY - height * 0.45,
            width: width,
            height: height)
        // Kept inside the cell's own slab, which on a bar exactly as thick as the icon is the
        // difference between a badge and a shape welded to the top edge of the screen.
        let limit = backgroundRect
        rect.origin.x = min(max(rect.origin.x, limit.minX), max(limit.minX, limit.maxX - width))
        rect.origin.y = min(max(rect.origin.y, limit.minY), max(limit.minY, limit.maxY - height))

        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        NSColor.systemRed.setFill()
        path.fill()
        // A hairline of the bar's own material keeps the capsule legible against a busy icon.
        NSColor.windowBackgroundColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1
        path.stroke()

        text.draw(
            at: NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2),
            withAttributes: attributes)
    }

    /// One short pill per window, up to a limit, in the outer margin.
    ///
    /// A labelled bar normally shows running state as a button fill and draws nothing here — but a
    /// window *count* is information the fill cannot carry, so multi-window apps get their dashes in
    /// both modes.
    private func drawIndicator() {
        // The lane holds one thing. An app that is part-way through a track is self-evidently
        // running, so the bar says everything the dashes would have and one thing more; drawing both
        // into three points of margin would leave neither legible. A labelled bar keeps its dashes,
        // because there the progress is a fill behind the button rather than anything in the lane.
        if let progress, usesIndicatorLane {
            drawProgressBar(progress)
            return
        }
        guard item.isRunning else { return }
        let multiple = item.windowCount > 1
        guard usesIndicatorLane || multiple else { return }

        let dashes = WindowIndicator.dashCount(forWindows: item.windowCount)
        let layout = WindowIndicator.layout(
            dashes: dashes,
            iconSize: metrics.iconSize,
            weight: metrics.indicatorWeight,
            isFrontmost: item.isFrontmost)

        let weight = metrics.indicatorWeight
        // A labelled bar has no indicator lane, so the dashes ride just inside the button's own
        // edge rather than the cell's — otherwise they would hang outside the slab.
        let lane = max(0, (metrics.outerInset - weight) / 2)
        let offset = usesIndicatorLane ? lane : lane + metrics.crossInset
        NSColor.labelColor
            .withAlphaComponent(item.isFrontmost ? 0.85 : 0.45)
            .setFill()

        // Laid out along the bar's long axis, centred on the cell.
        var position = (edge.isVertical ? bounds.midY : bounds.midX) - layout.total / 2
        for _ in 0..<dashes {
            let rect: NSRect = switch edge {
            case .bottom:
                NSRect(x: position, y: offset, width: layout.dash, height: weight)
            case .left:
                NSRect(x: offset, y: position, width: weight, height: layout.dash)
            case .right:
                NSRect(x: bounds.maxX - offset - weight, y: position, width: weight, height: layout.dash)
            }
            NSBezierPath(roundedRect: rect, xRadius: weight / 2, yRadius: weight / 2).fill()
            position += layout.dash + layout.gap
        }
    }

    /// The rounded slab a cell draws behind itself. Exposed so the spacing between adjacent
    /// buttons can be asserted rather than eyeballed.
    var backgroundRect: NSRect {
        // The long axis runs vertically on a side bar, so which inset is which swaps with the edge.
        edge.isVertical
            ? bounds.insetBy(dx: metrics.crossInset, dy: metrics.backgroundInset)
            : bounds.insetBy(dx: metrics.backgroundInset, dy: metrics.crossInset)
    }

    /// The bar for an icons-only cell: a track along the screen-facing edge, in the lane the running
    /// dashes would otherwise use.
    ///
    /// A track *and* a fill, not a fill alone — a bar 12% along with nothing behind it is a short
    /// dash, which is exactly what the running indicator looks like. The track is what makes the
    /// same mark read as "12% of the way" rather than "one window".
    private func drawProgressBar(_ report: ProgressReport) {
        let weight = metrics.indicatorWeight
        let lane = max(0, (metrics.outerInset - weight) / 2)
        let offset = usesIndicatorLane ? lane : lane + metrics.crossInset
        let length = (metrics.iconSize * 0.85).rounded()
        let start = (edge.isVertical ? bounds.midY : bounds.midX) - length / 2
        let filled = (length * report.fraction).rounded()

        func rect(from: CGFloat, _ extent: CGFloat) -> NSRect {
            switch edge {
            case .bottom: NSRect(x: from, y: offset, width: extent, height: weight)
            case .left: NSRect(x: offset, y: from, width: weight, height: extent)
            case .right: NSRect(x: bounds.maxX - offset - weight, y: from, width: weight, height: extent)
            }
        }

        // On a side bar the long axis runs downward, so the fill has to grow from the top rather
        // than from the smaller coordinate — otherwise a track plays upwards.
        let fillStart = edge.isVertical ? start + length - filled : start
        let radius = weight / 2

        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: rect(from: start, length), xRadius: radius, yRadius: radius).fill()
        guard filled > 0 else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect(from: fillStart, filled), xRadius: radius, yRadius: radius).fill()
    }

    /// The bar for a labelled button: the slab fills from its leading edge, the way a Windows
    /// taskbar button does.
    ///
    /// The fill is the thing labelled mode has that compact mode has not — room. It reads at a
    /// glance across a whole row, it survives a button narrow enough to have dropped its text, and
    /// it leaves the icon, the name and the running dashes exactly where they were.
    ///
    /// Only ever on a horizontal bar: labels are refused on a side bar, so a labelled cell there
    /// does not exist and this is never reached with a vertical axis to think about.
    private func drawProgressFill(_ report: ProgressReport) {
        let rect = backgroundRect
        guard rect.width > 2, rect.height > 0 else { return }
        let radius = max(4, metrics.iconSize * 0.2)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()

        var fill = rect
        fill.size.width = (rect.width * report.fraction).rounded()
        NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
        fill.fill()

        // A brighter edge at the head of the fill. Without it a slab tinted at 28% is a slab that
        // might just be selected; the moving line is what says it is going somewhere.
        guard fill.width >= 1, fill.maxX < rect.maxX else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSRect(x: fill.maxX - 1, y: rect.minY, width: 1.5, height: rect.height).fill()
    }

    private func drawBackground() {
        var alpha = 0.0
        // Without the indicator lane, the fill *is* the running indicator — the taskbar idiom.
        if item.isRunning && !usesIndicatorLane {
            alpha = item.isFrontmost ? 0.16 : 0.07
        }
        if isHovered || hasKeyboardFocus { alpha += 0.10 }
        if isDropTarget { alpha = 0.22 }

        let radius = max(4, metrics.iconSize * 0.2)
        let path = NSBezierPath(roundedRect: backgroundRect, xRadius: radius, yRadius: radius)

        if item.needsAttention {
            // Amber rather than the accent colour: the accent is already the drop target's, and an
            // app asking for you should not look like a place to drop a file.
            NSColor.systemOrange.withAlphaComponent(0.10 + 0.13 * attentionPhase).setFill()
            path.fill()
            NSColor.systemOrange.withAlphaComponent(0.50 + 0.35 * attentionPhase).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        if alpha > 0 {
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            path.fill()
        }
        if isDropTarget {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    /// Where the keyboard is, while the bar has it.
    ///
    /// Drawn by the cell rather than left to AppKit's focus ring, which is drawn *outside* the view's
    /// shape — and on a bar one icon thick the outside is off the edge of the strip, where it is
    /// clipped. Inside the slab it is whole on every edge and at every size.
    ///
    /// The system's focus colour, at full strength: it comes at half, which is meant for a ring
    /// drawn over a control's border and disappears over an icon of the same hue.
    private func drawKeyboardFocus() {
        let width = max(2, (metrics.iconSize * 0.09).rounded())
        let rect = backgroundRect.insetBy(dx: width / 2, dy: width / 2)
        let radius = max(2, max(4, metrics.iconSize * 0.2) - width / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.lineWidth = width
        NSColor.keyboardFocusIndicatorColor.withAlphaComponent(1).setStroke()
        path.stroke()
    }

    private func drawLabel() {
        let x = iconRect.maxX + metrics.labelGap
        let width = bounds.maxX - metrics.horizontalPadding - x
        guard width > 8 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: metrics.labelFont,
            .foregroundColor: item.isFrontmost ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let text = item.displayName as NSString
        let height = ceil(text.size(withAttributes: attributes).height)
        text.draw(
            in: NSRect(x: x, y: bounds.midY - height / 2, width: width, height: height),
            withAttributes: attributes)
    }

    // MARK: - Clock

    /// The time, on one line across a horizontal bar and two down a vertical one.
    private func drawDigitalClock() {
        guard !clockLines.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping

        // A single line gets the label's own size; two stacked lines have to share the height, so
        // they are sized from the cell rather than from the font the labels use.
        let size = clockLines.count > 1
            ? max(8, (backgroundRect.height * 0.34).rounded())
            : metrics.labelFontSize
        // Monospaced digits: without them the cell changes width as the minutes tick over, and a
        // full-width bar reflows every button beside it once a minute.
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]

        let lineHeight = ceil(font.ascender - font.descender)
        var y = bounds.midY + (lineHeight * CGFloat(clockLines.count)) / 2
        for line in clockLines {
            y -= lineHeight
            (line as NSString).draw(
                in: NSRect(x: bounds.minX, y: y, width: bounds.width, height: lineHeight),
                withAttributes: attributes)
        }
    }

    /// A drawn dial rather than a supplied image.
    ///
    /// uBar's "timepieces" are folders of PNGs with a plist describing them; that is a plug-in
    /// format, and a plug-in format with one implementation is just a file layout to maintain. A
    /// face drawn from the current appearance's own colours suits a bar that is already following
    /// the system's light and dark.
    private func drawDial() {
        let face = iconRect.insetBy(dx: 1, dy: 1)
        guard face.width > 6 else { return }

        let rim = NSBezierPath(ovalIn: face)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        rim.fill()
        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
        rim.lineWidth = max(1, face.width * 0.045)
        rim.stroke()

        let centre = NSPoint(x: face.midX, y: face.midY)
        let radius = face.width / 2
        let parts = Calendar.current.dateComponents([.hour, .minute], from: clockDate)
        let turns = ClockContent.handTurns(hour: parts.hour ?? 0, minute: parts.minute ?? 0)

        func hand(turns: Double, length: CGFloat, weight: CGFloat, alpha: CGFloat) {
            let direction = ClockContent.handVector(turns: turns)
            let path = NSBezierPath()
            path.move(to: centre)
            path.line(to: NSPoint(
                x: centre.x + direction.x * radius * length,
                y: centre.y + direction.y * radius * length))
            path.lineWidth = weight
            path.lineCapStyle = .round
            NSColor.labelColor.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }

        // Short and thick for the hour, long and thin for the minute — the only thing that tells
        // them apart on a face this small, which has no numerals to read.
        hand(turns: turns.hour, length: 0.52, weight: max(1.5, radius * 0.20), alpha: 0.95)
        hand(turns: turns.minute, length: 0.82, weight: max(1, radius * 0.10), alpha: 0.75)

        // A hub, so the two hands read as joined at the middle rather than crossing there.
        let hub = max(1.2, radius * 0.11)
        NSColor.labelColor.withAlphaComponent(0.95).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: centre.x - hub, y: centre.y - hub, width: hub * 2, height: hub * 2)).fill()
    }

    private func drawSeparator() {
        NSColor.separatorColor.setFill()
        let reach = metrics.iconSize * 0.45
        let line: NSRect = if edge.isVertical {
            NSRect(x: bounds.midX - reach, y: bounds.midY - 0.5, width: reach * 2, height: 1)
        } else {
            NSRect(x: bounds.midX - 0.5, y: bounds.midY - reach, width: 1, height: reach * 2)
        }
        line.fill()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu()
            return
        }
        mouseDownPoint = event.locationInWindow
        isDragging = false
        delegate?.itemView(self, hoverChanged: false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !isDragging, !item.isSeparator else { return }
        let delta = hypot(
            event.locationInWindow.x - start.x,
            event.locationInWindow.y - start.y
        )
        guard delta > ItemView.dragThreshold else { return }
        guard delegate?.itemViewShouldBeginDrag(self) == true else { return }
        isMoveOnly = event.modifierFlags.contains(.command)
        isDragging = true
        delegate?.itemViewBeginInteraction(self)
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !isDragging, landed(event) else { return }
        // ⌘ is read here rather than at mouse-down because ⌘-*drag* means something else entirely
        // (move-only); a press that never became a drag is still just a click.
        guard let action = ClickAction.resolve(modifiers: event.modifierFlags, for: item) else { return }
        delegate?.itemView(self, clicked: action)
    }

    /// The middle button is a click like any other, but AppKit routes it separately.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == ItemView.middleButton else { return }
        mouseDownPoint = event.locationInWindow
    }

    override func otherMouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard event.buttonNumber == ItemView.middleButton, landed(event) else { return }
        guard let action = ClickAction.resolve(
            modifiers: event.modifierFlags, button: .middle, for: item) else { return }
        delegate?.itemView(self, clicked: action)
    }

    /// Whether a release counts as a click on this cell.
    ///
    /// Released inside the cell, or barely moved at all. Testing only the release point loses clicks
    /// to a couple of points of hand tremor: a press near a cell edge that drifts 2pt outside is
    /// under the drag threshold, so no drag ever starts either, and the click simply vanishes — on a
    /// bar one icon thick, that edge is most of the cell.
    private func landed(_ event: NSEvent) -> Bool {
        guard !item.isSeparator, let start = mouseDownPoint else { return false }
        let slip = hypot(
            event.locationInWindow.x - start.x,
            event.locationInWindow.y - start.y
        )
        return bounds.contains(convert(event.locationInWindow, from: nil))
            || slip <= ItemView.dragThreshold
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu()
    }

    /// The context menu, however it was asked for: a right- or ⌃-click, a key, or VoiceOver.
    func showMenu() {
        guard let menu = delegate?.itemViewMenu(for: self) else { return }
        present(menu)
    }

    /// Where this cell is on screen, for a popup that places itself rather than being handed to
    /// `NSMenu.popUp`.
    var screenFrame: NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    /// Anchored to the inward edge of the cell so the menu opens over the screen, not off it.
    func present(_ menu: NSMenu) {
        delegate?.itemViewBeginInteraction(self)
        defer { delegate?.itemViewEndInteraction(self) }
        let location: NSPoint = switch edge {
        case .bottom: NSPoint(x: 0, y: bounds.maxY + 4)
        case .left: NSPoint(x: bounds.maxX + 4, y: bounds.maxY)
        case .right: NSPoint(x: -4, y: bounds.maxY)
        }
        menu.popUp(positioning: nil, at: location, in: self)
    }

    // MARK: - Keyboard

    /// Only the cell the strip put the keyboard on. Keys arrive here and go up the responder chain
    /// to the strip, which is what interprets them.
    override var acceptsFirstResponder: Bool { hasKeyboardFocus }

    /// Refused here as well, because `NSWindow.makeFirstResponder` never asks the property above —
    /// only a click does. Without this any caller could put the keyboard on a cell the strip does
    /// not know about, and the ring and VoiceOver would both be describing a different one.
    override func becomeFirstResponder() -> Bool { hasKeyboardFocus }

    // MARK: - Accessibility

    /// A button to VoiceOver, named and described by `CellDescription`. The separator is not an
    /// element at all: it is a gap, and announcing it would be announcing nothing.
    override func isAccessibilityElement() -> Bool { !item.isSeparator }

    override func accessibilityRole() -> NSAccessibility.Role? {
        switch CellDescription(item: item)?.role {
        case .button: .button
        case .menuButton: .menuButton
        case nil: nil
        }
    }

    override func accessibilityLabel() -> String? {
        CellDescription(item: item)?.label
    }

    /// Asked for when read, never stored: the clock's reading and a track's position change without
    /// the cell being told.
    override func accessibilityValue() -> Any? {
        CellDescription(item: item, progress: progress)?.value
    }

    override func isAccessibilityFocused() -> Bool { hasKeyboardFocus }

    /// The plain click. Performed after the answer rather than before it: a folder's stack and the
    /// cell's menu run a menu-tracking loop until they close, and the assistive app that asked would
    /// wait for its reply the whole time.
    override func accessibilityPerformPress() -> Bool {
        guard !item.isSeparator else { return false }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.itemView(self, clicked: .activate)
        }
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard !item.isSeparator else { return false }
        DispatchQueue.main.async { [weak self] in self?.showMenu() }
        return true
    }

    /// The modifier-clicks, which a screen reader cannot perform: it presses, but holds nothing
    /// down while it does. See `ClickAction.alternatives`.
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let actions = ClickAction.alternatives(for: item)
        guard !actions.isEmpty else { return nil }
        return actions.map { action in
            NSAccessibilityCustomAction(name: action.title(for: item)) { [weak self] in
                guard let self else { return false }
                DispatchQueue.main.async { self.delegate?.itemView(self, clicked: action) }
                return true
            }
        }
    }

    // MARK: - Dragging

    private func beginDrag(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.id, forType: .eskeleItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let frame = iconRect
        draggingItem.setDraggingFrame(frame, contents: icon)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

extension ItemView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        guard context == .withinApplication else { return isMoveGesture ? [] : .delete }
        return .move
    }

    /// The modern replacement for the old "poof": while the drag is away from the bar, the cursor
    /// itself tells the user that letting go will remove the item.
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard let window, item.isPinned else { return }
        guard !isMoveGesture else {
            NSCursor.arrow.set()
            return
        }
        if window.frame.contains(screenPoint) {
            NSCursor.arrow.set()
        } else {
            NSCursor.disappearingItem.set()
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        NSCursor.arrow.set()
        isDragging = false
        mouseDownPoint = nil
        let moveOnly = isMoveGesture
        isMoveOnly = false
        delegate?.itemViewEndInteraction(self)
        // Dropped nowhere: if the drag ended away from the bar, that means "take this off the bar"
        // — unless ⌘ was held, which says the user was only rearranging.
        guard !moveOnly else { return }
        guard operation == [] || operation == .delete else { return }
        guard let window, !window.frame.contains(screenPoint) else { return }
        delegate?.itemViewDraggedOutOfBar(self, at: screenPoint)
    }
}
