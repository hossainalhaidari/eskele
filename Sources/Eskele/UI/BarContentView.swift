import AppKit

@MainActor
protocol BarContentViewDelegate: AnyObject {
    func barContent(_ view: BarContentView, perform action: ClickAction, on item: DockItem)
    func barContent(_ view: BarContentView, stackMenuFor item: DockItem) -> NSMenu?
    /// - Returns: `true` if the launcher opened; `false` if this click dismissed an open one.
    func barContent(_ view: BarContentView, showLauncherAt anchor: NSRect, onDismiss: @escaping () -> Void) -> Bool
    func barContent(_ view: BarContentView, menuFor item: DockItem) -> NSMenu
    func barContent(_ view: BarContentView, menuForBackgroundAt index: Int) -> NSMenu
    func barContent(_ view: BarContentView, didMove item: DockItem, toVisualIndex index: Int)
    func barContent(_ view: BarContentView, didDropFiles urls: [URL], on item: DockItem)
    func barContent(_ view: BarContentView, didDropFiles urls: [URL], atVisualIndex index: Int)
    func barContent(_ view: BarContentView, didDragOutOfBar item: DockItem, at screenPoint: NSPoint)
    /// A thumbnail of the window this cell stands for, or `nil` when there is none to be had —
    /// previews switched off, the permission missing, or the cell is not a window at all.
    func barContent(_ view: BarContentView, previewFor item: DockItem) async -> NSImage?
}

/// The strip itself: background material, laid-out cells, insertion caret, drop handling.
final class BarContentView: NSView {
    weak var delegate: BarContentViewDelegate?

    private(set) var items: [DockItem] = []
    private var settings = Settings()
    private var metrics = BarMetrics(thickness: 32, settings: Settings())
    private var scale: CGFloat = 2

    private let effectView = NSVisualEffectView()
    private let separatorLine = NSView()
    private let caret = NSView()
    /// A slab behind each run of pinned launchers, so the group reads as one tray of shortcuts
    /// rather than as buttons that have lost their labels.
    private let pinTray = PinTrayView()
    private var itemViews: [ItemView] = []
    private var cellLengths: [CGFloat] = []
    /// Position of each cell along the bar's long axis. Computed once per layout because the caret
    /// and the drop index both need it, and a full-width bar's trailing group breaks the assumption
    /// that cells simply follow one another.
    private var cellOrigins: [CGFloat] = []
    /// Which row each cell landed in, and the cells each row holds. Both are wanted often enough —
    /// by the caret, the drop index and the pin tray — to be worth keeping rather than re-deriving.
    private var cellRows: [Int] = []
    private var rowRanges: [Range<Int>] = []
    private var caretIndex: Int?
    private var dropTargetView: ItemView?
    private var pulseTimer: Poll?
    private var clockTimer: Timer?
    private let calendar = CalendarPopover()
    /// What the cells are annotated with, driven by `ModifierWatcher` — so it is set only while the
    /// chord is actually down.
    var overlay: BarOverlay? {
        didSet {
            guard overlay != oldValue else { return }
            applyOverlay()
        }
    }
    /// Processor and memory figures by process, refreshed while the activity overlay is up.
    var activity: [pid_t: ActivitySample] = [:] {
        didSet {
            guard overlay == .activity, activity != oldValue else { return }
            applyOverlay()
        }
    }
    /// What each cell is part-way through, keyed by `DockItem.progressKey`. Pushed to the cells
    /// directly rather than through a rebuild: a playing track moves the bar every second, and
    /// reassembling the whole strip at that rate to change one number would be absurd.
    var progress: [String: ProgressReport] = [:] {
        didSet {
            guard progress != oldValue else { return }
            applyProgress()
        }
    }
    private var pulseStart = Date()
    private let tooltip = HoverTooltip()

    /// Non-zero while a menu is open or a drag is running. Auto-hide waits it out; nothing is worse
    /// than the bar sliding away underneath an open context menu.
    private var interactionDepth = 0
    /// Also while the bar has the keyboard, which is the same thing done without the pointer — and
    /// the pointer is then likely nowhere near the bar, which is exactly what auto-hide looks for.
    var isInteracting: Bool { interactionDepth > 0 || keyboardFocus != nil }

    /// The cell the keyboard is on, as an index into `items`, while the bar has the keyboard; nil the
    /// rest of the time. See §5.27.
    private(set) var keyboardFocus: Int?
    /// Asked to give the keyboard back — Escape. Which app it goes back to, and the panel's key
    /// status, are the window controller's business.
    var onLeaveKeyboard: (() -> Void)?
    /// What has been typed towards a name, and when the last of it was.
    private var typed = ""
    private var typedAt = Date.distantPast
    /// A pause longer than this starts a new name rather than continuing the last one.
    static let typingTimeout: TimeInterval = 1

    func beginInteraction() {
        // A menu or a drag is the user's attention; the label has served its purpose.
        tooltip.hide()
        interactionDepth += 1
    }
    func endInteraction() { interactionDepth = max(0, interactionDepth - 1) }

    override var isFlipped: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.material = .menu
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(separatorLine)

        pinTray.isHidden = true
        addSubview(pinTray)

        caret.wantsLayer = true
        caret.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        caret.layer?.cornerRadius = 1
        caret.isHidden = true
        addSubview(caret)

        registerForDraggedTypes([.eskeleItem, .fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Configuration

    func configure(items: [DockItem], settings: Settings, thickness: CGFloat, scale: CGFloat) {
        self.items = items
        self.settings = settings
        self.scale = scale
        self.metrics = BarMetrics(thickness: thickness, settings: settings)

        applyBackground()
        tooltip.appearance = settings.appearance.nsAppearance
        layer?.cornerRadius = metrics.cornerRadius
        layer?.maskedCorners = maskedCorners(for: settings.edge)

        rebuildItemViews()
        syncPulse()
        syncClock()
        needsLayout = true
    }

    /// Length along the bar's long axis if nothing constrained it. The window controller clamps this
    /// to the screen, and `layout()` then reflows the cells into whatever room they really got.
    ///
    /// With rows this is the longest of them rather than the sum of every cell: the bar only has to
    /// be as long as its longest row. `BarLayoutSolver.rows` needs no length to divide the cells up,
    /// which is what lets this be asked before there is one.
    var preferredLength: CGFloat {
        let desired = items.map(desiredLength)
        let longest = BarLayoutSolver.rows(
            minimums: items.map(minimumLength), desired: desired, rows: metrics.rows
        ).reduce(CGFloat.zero) { longest, row in
            max(longest, desired[row].reduce(0, +))
        }
        return max(metrics.totalThickness, longest + 2 * metrics.endPadding)
    }

    /// Icon-only width: the floor every cell is entitled to.
    private func minimumLength(for item: DockItem) -> CGFloat {
        if item.isSeparator { return metrics.separatorLength }
        // The clock is text, and text that has been truncated tells you the wrong time. Its floor
        // is what it actually needs, so it is never the cell that gives way.
        if item.isClock { return clockLength() }
        return metrics.iconSize + metrics.itemSpacing
    }

    /// The room the clock needs, measured rather than guessed.
    ///
    /// Measured with monospaced digits, which is also what draws it: a proportional 1 is narrower
    /// than a 0, so a clock sized to "11:11" reflows the whole bar when it reaches "10:00".
    private func clockLength() -> CGFloat {
        guard settings.clockStyle == .digital else {
            return metrics.iconSize + metrics.itemSpacing
        }
        let lines = ClockContent.lines(
            at: Date(), format: settings.clockFormat, isVertical: settings.edge.isVertical)
        guard settings.edge.isVertical == false else {
            return metrics.iconSize + metrics.itemSpacing
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: metrics.labelFontSize, weight: .medium)
        let widest = lines.reduce(CGFloat.zero) { widest, line in
            max(widest, ceil((line as NSString).size(withAttributes: [.font: font]).width))
        }
        return widest + metrics.horizontalPadding * 2 + metrics.itemSpacing
    }

    /// Only running apps become buttons — they are the "tasks" in a taskbar. A pinned app that is
    /// not running stays a plain icon, as it does on Windows.
    ///
    /// Full-width bars give every button the same width, which is what makes a row of them read as
    /// a taskbar rather than a ragged list; long names are then truncated with an ellipsis. A bar
    /// that hugs its icons sizes each button to its text instead, so a short list stays compact,
    /// treating the same number as a ceiling.
    private func desiredLength(for item: DockItem) -> CGFloat {
        let minimum = minimumLength(for: item)
        guard settings.drawsLabels, item.isTask, item.isRunning else { return minimum }
        guard settings.spanMode != .fullSpan else { return max(minimum, metrics.buttonWidth) }

        let text = item.displayName as NSString
        let textWidth = ceil(text.size(withAttributes: [.font: metrics.labelFont]).width)
        let wanted = metrics.horizontalPadding * 2 + metrics.iconSize + metrics.labelGap + textWidth
        return max(minimum, min(metrics.buttonWidth, wanted))
    }

    /// A cell narrowed to nearly its floor has no room for text; below this it reverts to an icon.
    private func hasRoomForLabel(_ item: DockItem, length: CGFloat) -> Bool {
        guard settings.drawsLabels, item.isTask, item.isRunning else { return false }
        return length >= minimumLength(for: item) + 30 * settings.barSize.multiplier
    }

    private func recomputeGeometry(available: CGFloat) {
        let minimums = items.map(minimumLength)
        let desired = items.map(desiredLength)
        let room = max(0, available - 2 * metrics.endPadding)
        rowRanges = BarLayoutSolver.rows(minimums: minimums, desired: desired, rows: metrics.rows)

        cellLengths = Array(repeating: 0, count: items.count)
        cellOrigins = Array(repeating: 0, count: items.count)
        cellRows = Array(repeating: 0, count: items.count)

        // Each row is solved on its own, against the whole length of the bar: a row is a bar's worth
        // of cells, and the row above it neither lends nor borrows width.
        for (row, range) in rowRanges.enumerated() {
            let lengths = BarLayoutSolver.lengths(
                minimums: Array(minimums[range]), desired: Array(desired[range]), available: room)

            let anchored = anchoredCount(in: range)
            let leadingCount = range.count - anchored
            let anchoredLength = lengths.suffix(anchored).reduce(0, +)
            let leadingLength = lengths.prefix(leadingCount).reduce(0, +)

            // The leading group gets everything except the strip the trailing group occupies, so a
            // trailing alignment or an over-long run cannot run into the Trash.
            var offset = contentStart(
                contentLength: leadingLength, available: available - anchoredLength)
            for position in 0..<leadingCount {
                place(range.lowerBound + position, in: row, at: offset, length: lengths[position])
                offset += lengths[position]
            }

            offset = available - metrics.endPadding - anchoredLength
            for position in leadingCount..<range.count {
                place(range.lowerBound + position, in: row, at: offset, length: lengths[position])
                offset += lengths[position]
            }
        }
    }

    private func place(_ index: Int, in row: Int, at offset: CGFloat, length: CGFloat) {
        cellLengths[index] = length
        cellOrigins[index] = offset
        cellRows[index] = row
    }

    /// Where one row sits across the bar, and how thick it is.
    ///
    /// Rows stack in reading order: downwards on a horizontal bar, rightwards on a vertical one. The
    /// band is measured off the view's own bounds rather than off `metrics.thickness`, so the rows
    /// still add up exactly after the window frame has been rounded to whole points.
    private func rowBand(_ row: Int) -> (origin: CGFloat, thickness: CGFloat) {
        let across = settings.edge.isVertical ? bounds.width : bounds.height
        let thickness = across / CGFloat(max(1, metrics.rows))
        return settings.edge.isVertical
            ? (CGFloat(row) * thickness, thickness)
            : (bounds.height - CGFloat(row + 1) * thickness, thickness)
    }

    /// Where the first cell starts. In `.fullSpan` the bar is far longer than its contents, so the
    /// icons need an anchor; when it hugs its contents every alignment collapses to the same result.
    private func contentStart(contentLength: CGFloat, available: CGFloat) -> CGFloat {
        switch settings.itemAlignment {
        case .leading: metrics.endPadding
        case .center: max(metrics.endPadding, (available - contentLength) / 2)
        case .trailing: max(metrics.endPadding, available - contentLength - metrics.endPadding)
        }
    }

    /// Cells at the end of this row anchored to the far end of the bar rather than following the
    /// others.
    ///
    /// Only in full-width mode, where there is a gap to push into. A bar that hugs its icons has
    /// nothing to spread across.
    ///
    /// The Trash and the clock both belong at that end, and either can be absent — so this counts
    /// the *run* of them rather than testing whether one particular cell is last. Testing for the
    /// Trash alone was what made adding a clock after it un-anchor both: the last cell was no longer
    /// the Trash, so nothing was held at the end and the whole strip closed up beside the apps.
    ///
    /// Counted per row because that run is at the very end of the strip, so only the row it fell
    /// into has any of it.
    private func anchoredCount(in range: Range<Int>) -> Int {
        guard settings.spanMode == .fullSpan else { return 0 }
        var count = 0
        for index in range.reversed() {
            guard items[index].isTrash || items[index].isClock else { break }
            count += 1
        }
        return count
    }

    private func maskedCorners(for edge: BarEdge) -> CACornerMask {
        switch edge {
        case .bottom: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .left: [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case .right: [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
    }

    // MARK: - Item views

    private func rebuildItemViews() {
        // Read before the pool is reshuffled: which cell the keyboard was on, and where it stood.
        let focused = keyboardFocus.flatMap { index in
            itemViews.indices.contains(index) ? (id: itemViews[index].item.id, index: index) : nil
        }

        // Pooled per id rather than keyed by it. Two cells can share an id, and a table holding one
        // view per id silently dropped the other: never reused and never removed, it stayed on the
        // bar for good, frozen as it last drew — through every later rebuild, relayout and change of
        // style. Every view now either goes back into the strip or out of the hierarchy.
        var reusable: [String: [ItemView]] = [:]
        for view in itemViews { reusable[view.item.id, default: []].append(view) }

        var next: [ItemView] = []
        for item in items {
            let view: ItemView
            if let existing = reusable[item.id]?.first {
                reusable[item.id]?.removeFirst()
                existing.item = item
                existing.edge = settings.edge
                existing.metrics = metrics
                view = existing
            } else {
                view = ItemView(item: item, edge: settings.edge, metrics: metrics)
                view.delegate = self
                addSubview(view)
            }
            view.usesIndicatorLane = !settings.drawsLabels
            view.icon = icon(for: item)
            if item.isClock {
                view.clockStyle = settings.clockStyle
                view.clockLines = ClockContent.lines(
                    at: Date(), format: settings.clockFormat, isVertical: settings.edge.isVertical)
            }
            next.append(view)
        }
        for orphan in reusable.values.joined() { orphan.removeFromSuperview() }
        itemViews = next
        // The bar can change while the modifiers are held — an app launching is enough — and the
        // annotations have to follow the cells rather than the other way round.
        applyOverlay()
        applyProgress()

        // The tray sits under the cells, the caret over them.
        pinTray.removeFromSuperview()
        addSubview(pinTray, positioned: .above, relativeTo: effectView)
        caret.removeFromSuperview()
        addSubview(caret)

        if let focused { followKeyboardFocus(from: focused) }
    }

    /// Keeps the keyboard on its cell through a rebuild, which happens whenever anything on the bar
    /// changes — an app launching, a badge, a window opening.
    ///
    /// The same cell if it is still there, found by id since it may have moved; otherwise whatever
    /// now stands where it stood, which is what quitting an app from the keyboard should leave you
    /// on. Only a move is announced. The bar rebuilds every few seconds while anything is changing,
    /// and VoiceOver repeating the cell you are already on each time would be unusable.
    private func followKeyboardFocus(from previous: (id: String, index: Int)) {
        let same = items.firstIndex { $0.id == previous.id }
        guard let index = same ?? BarNavigation.stop(near: previous.index, in: items) else {
            // Nothing left on the bar to be on.
            keyboardFocus = nil
            onLeaveKeyboard?()
            return
        }
        setKeyboardFocus(index, announce: same == nil)
    }

    /// Re-reads every cell's icon, for when the icons themselves changed rather than the items.
    func reloadIcons() {
        for view in itemViews { view.icon = icon(for: view.item) }
    }

    private func applyProgress() {
        for view in itemViews {
            view.progress = view.item.progressKey.flatMap { progress[$0] }
        }
    }

    private func applyOverlay() {
        for view in itemViews {
            view.slotNumber = overlay == .slotNumbers ? view.item.slotNumber : nil
            view.activity = overlay == .activity ? view.item.pid.flatMap { activity[$0] } : nil
        }
    }

    /// The bar's own ground: a vibrancy material, or the flat colour the user picked.
    ///
    /// The two are exclusive. A colour drawn *over* a material is neither one nor the other — pick
    /// 80% black and you would get 80% black over a blur of the desktop, which is darker than
    /// asked for and moves when the wallpaper does.
    private func applyBackground() {
        effectView.isHidden = !settings.material.usesVibrancy
        effectView.material = settings.material.nsMaterial
        layer?.backgroundColor = settings.material.usesVibrancy
            ? NSColor.clear.cgColor
            : settings.tint.color.cgColor
    }

    private func icon(for item: DockItem) -> NSImage? {
        switch item.kind {
        case .trash(let isEmpty):
            IconService.shared.trashIcon(isEmpty: isEmpty, pointSize: metrics.iconSize, scale: scale)
        case .appsMenu:
            IconService.shared.appsMenuIcon(
                pointSize: metrics.iconSize, scale: scale, appearance: effectiveAppearance)
        case .separator:
            nil
        default:
            item.url.map {
                IconService.shared.icon(
                    for: $0, key: item.iconOverrideKey, pointSize: metrics.iconSize, scale: scale)
            }
        }
    }

    /// The launcher glyph is tinted to the current appearance, so it has to be redrawn when that
    /// changes — app icons do not care, but this one does.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackground()
        rebuildItemViews()
        syncPulse()
        needsLayout = true
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        effectView.frame = bounds
        layoutSeparatorLine()
        recomputeGeometry(available: settings.edge.isVertical ? bounds.height : bounds.width)

        for (index, view) in itemViews.enumerated() {
            let length = cellLengths.indices.contains(index) ? cellLengths[index] : metrics.iconSize
            let offset = cellOrigins.indices.contains(index) ? cellOrigins[index] : 0
            let band = rowBand(cellRows.indices.contains(index) ? cellRows[index] : 0)
            view.showsLabel = hasRoomForLabel(items[index], length: length)
            // On a vertical bar the axis runs downward from the top, so a larger offset is lower —
            // which is what puts the trailing group at the bottom.
            view.frame = settings.edge.isVertical
                ? NSRect(x: band.origin, y: bounds.height - offset - length,
                         width: band.thickness, height: length)
                : NSRect(x: offset, y: band.origin, width: length, height: band.thickness)
        }
        layoutPinTray()
        layoutCaret()
    }

    /// Spans every cell of the pin group, including any separators the user put between them.
    ///
    /// One slab per row: a pin group long enough to wrap would otherwise be given a single union
    /// rectangle covering both rows end to end, including everything that is not a pin between them.
    private func layoutPinTray() {
        let pins = itemViews.indices.filter { items.indices.contains($0) && items[$0].isPinLauncher }
        let slabs: [NSRect] = rowRanges.compactMap { range in
            let inRow = pins.filter(range.contains)
            guard let first = inRow.first, let last = inRow.last else { return nil }
            let union = (first...last).reduce(itemViews[first].frame) { $0.union(itemViews[$1].frame) }
            return (settings.edge.isVertical
                ? union.insetBy(dx: metrics.crossInset, dy: metrics.backgroundInset)
                : union.insetBy(dx: metrics.backgroundInset, dy: metrics.crossInset)).integral
        }
        pinTray.isHidden = slabs.isEmpty
        pinTray.frame = bounds
        pinTray.cornerRadius = max(4, metrics.iconSize * 0.2)
        pinTray.slabs = slabs
    }

    // MARK: - Attention pulse

    /// A slow glow under the cells that are asking to be looked at.
    ///
    /// Timed rather than animated because the cells draw themselves: a `CABasicAnimation` would have
    /// nothing to animate. It runs only while something actually needs attention, and only the cells
    /// that do are redrawn.
    private func syncPulse() {
        let wanted = items.contains(where: \.needsAttention)
        if wanted, pulseTimer == nil {
            pulseStart = Date()
            // An app can ask for attention all night, so this too stops while the displays sleep.
            // Not stretched in Low Power Mode: it is an animation.
            pulseTimer = Poll(every: 0.1, tolerance: 0.03, stretchesInLowPowerMode: false) {
                [weak self] in self?.pulse()
            }
        } else if !wanted, pulseTimer != nil {
            stopPulse()
        }
    }

    private func pulse() {
        let period = 1.6
        let phase = (sin(Date().timeIntervalSince(pulseStart) * 2 * .pi / period) + 1) / 2
        for view in itemViews where view.item.needsAttention {
            view.attentionPhase = phase
        }
    }

    func hideTooltip() {
        tooltip.hide()
        calendar.hide()
    }

    // MARK: - Clock

    /// Wakes at the top of each minute, and only while there is a clock to update.
    ///
    /// Scheduled to the boundary rather than on a 60-second repeat: a repeating timer started at
    /// :30 would change the reading half a minute after everyone else's clock did.
    private func syncClock() {
        clockTimer?.invalidate()
        clockTimer = nil
        guard settings.showClock, window != nil else { return }

        let fire = ClockContent.nextMinute(after: Date())
        let timer = Timer(fire: fire, interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickClock() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func tickClock() {
        let lines = ClockContent.lines(
            at: Date(), format: settings.clockFormat, isVertical: settings.edge.isVertical)
        for view in itemViews where view.item.isClock {
            view.clockLines = lines
            view.needsDisplay = true
        }
        // A dial has no text and never changes width; digits can, when the hour gains a digit.
        if settings.clockStyle == .digital { needsLayout = true }
    }

    func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        for view in itemViews { view.attentionPhase = 0 }
    }

    func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopPulse()
            stopClock()
            tooltip.hide()
            calendar.hide()
        } else {
            syncPulse()
            syncClock()
        }
    }

    /// A hairline on the screen-facing side keeps colour icons legible against a bright wallpaper.
    private func layoutSeparatorLine() {
        let hairline = 1.0 / max(scale, 1)
        separatorLine.frame = switch settings.edge {
        case .bottom: NSRect(x: 0, y: bounds.maxY - hairline, width: bounds.width, height: hairline)
        case .left: NSRect(x: bounds.maxX - hairline, y: 0, width: hairline, height: bounds.height)
        case .right: NSRect(x: 0, y: 0, width: hairline, height: bounds.height)
        }
    }

    private func layoutCaret() {
        guard let index = caretIndex else {
            caret.isHidden = true
            return
        }
        caret.isHidden = false
        let position = caretPosition(for: index)
        // A caret past the last cell belongs to the last row, which is where that drop would land.
        let band = rowBand(cellRows.indices.contains(index) ? cellRows[index] : (cellRows.last ?? 0))
        caret.frame = settings.edge.isVertical
            ? NSRect(x: band.origin + 3, y: position - 1, width: band.thickness - 6, height: 2)
            : NSRect(x: position - 1, y: band.origin + 3, width: 2, height: band.thickness - 6)
    }

    private func caretPosition(for index: Int) -> CGFloat {
        let offset: CGFloat = if cellOrigins.indices.contains(index) {
            cellOrigins[index]
        } else if let last = cellOrigins.indices.last {
            cellOrigins[last] + cellLengths[last]
        } else {
            metrics.endPadding
        }
        return settings.edge.isVertical ? bounds.height - offset : offset
    }

    // MARK: - Hit testing

    private func itemView(at point: NSPoint) -> ItemView? {
        itemViews.first { $0.frame.contains(point) }
    }

    /// Keeps the background clickable.
    ///
    /// The pin tray and the vibrancy layer are both sized to the whole bar, so left to itself
    /// `hitTest` hands a click on the empty run to one of them rather than to us. They are
    /// decoration and answer no events; only the cells are real targets, and they sit above both.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is ItemView { return hit }
            view = current.superview
        }
        return view === self ? self : hit
    }

    /// The bar's own menu, for the empty run a full-width bar leaves beside its cells.
    ///
    /// Cells answer for themselves — `ItemView` consumes its own right-click — so anything arriving
    /// here landed on the background, and the menu is about the bar rather than about a task.
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let menu = delegate?.barContent(self, menuForBackgroundAt: insertionIndex(at: point))
        else { return }

        beginInteraction()
        defer { endInteraction() }
        // Anchored to the bar's inward edge the way a cell's menu is, so it opens over the screen
        // rather than off it.
        let location: NSPoint = switch settings.edge {
        case .bottom: NSPoint(x: point.x, y: bounds.maxY + 4)
        case .left: NSPoint(x: bounds.maxX + 4, y: point.y)
        case .right: NSPoint(x: -4, y: point.y)
        }
        menu.popUp(positioning: nil, at: location, in: self)
    }

    /// Insertion index for a drop, measured along the bar's long axis within the row it landed in.
    private func insertionIndex(at point: NSPoint) -> Int {
        let row = rowIndex(at: point)
        guard let range = rowRanges.indices.contains(row) ? rowRanges[row] : rowRanges.last
        else { return items.count }

        let position = settings.edge.isVertical ? bounds.height - point.y : point.x
        // Walk the real origins: in full-width mode there is a gap before the trailing group, and a
        // drop into that gap means "at the end of the main run", not "past the Trash".
        for index in range where position < cellOrigins[index] + cellLengths[index] / 2 {
            return index
        }
        return range.upperBound
    }

    /// Which row a point is over, measured the same way `rowBand` places them.
    private func rowIndex(at point: NSPoint) -> Int {
        guard metrics.rows > 1, !rowRanges.isEmpty else { return 0 }
        let across = settings.edge.isVertical ? point.x : bounds.height - point.y
        let thickness = (settings.edge.isVertical ? bounds.width : bounds.height) / CGFloat(metrics.rows)
        guard thickness > 0 else { return 0 }
        return min(rowRanges.count - 1, max(0, Int(across / thickness)))
    }

    // MARK: - Keyboard

    /// Puts the keyboard on the bar, on the cell of the app in front.
    ///
    /// Called before Eskele activates, while the cells still say which app is in front: activating
    /// is what stops them saying it, since from then on the app in front is Eskele.
    func beginKeyboardNavigation() {
        guard keyboardFocus == nil, let start = BarNavigation.entry(in: items) else { return }
        typed = ""
        setKeyboardFocus(start, announce: true)
    }

    func endKeyboardNavigation() {
        guard keyboardFocus != nil else { return }
        keyboardFocus = nil
        typed = ""
        for view in itemViews { view.hasKeyboardFocus = false }
        // The clock's calendar too, which arriving on it by keyboard brings up just as hovering does.
        hideTooltip()
        if window?.firstResponder is ItemView { window?.makeFirstResponder(nil) }
    }

    /// - Parameter announce: whether this is a move the user should hear about. A rebuild that
    ///   leaves the keyboard where it was is not, and saying so would repeat the cell every time.
    private func setKeyboardFocus(_ index: Int, announce: Bool) {
        guard itemViews.indices.contains(index) else { return }
        keyboardFocus = index
        for (position, view) in itemViews.enumerated() { view.hasKeyboardFocus = position == index }
        let view = itemViews[index]
        if window?.firstResponder !== view { window?.makeFirstResponder(view) }
        guard announce else { return }
        NSAccessibility.post(element: view, notification: .focusedUIElementChanged)
        // The name, for anyone who can see the bar but not tell its icons apart: the same label the
        // pointer would have brought up, on the same delay.
        showLabel(for: view)
    }

    /// Keys arrive at the focused cell and come up the responder chain to here. Anything this does
    /// not recognise goes on up, to the window, which beeps.
    override func keyDown(with event: NSEvent) {
        guard let current = keyboardFocus, itemViews.indices.contains(current) else {
            super.keyDown(with: event)
            return
        }
        let isTyping = !typed.isEmpty && Date().timeIntervalSince(typedAt) < Self.typingTimeout
        guard let command = BarKeyCommand.resolve(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            characters: event.characters,
            edge: settings.edge,
            isTyping: isTyping)
        else {
            super.keyDown(with: event)
            return
        }
        perform(command, from: current, isTyping: isTyping)
    }

    private func perform(_ command: BarKeyCommand, from current: Int, isTyping: Bool) {
        if case .type(let characters) = command {
            typeSelect(characters, from: current, continuing: isTyping)
            return
        }
        typed = ""
        let view = itemViews[current]

        switch command {
        case .previous, .next, .first, .last:
            // Nowhere to go at the ends is not an error, and a beep for it would be one.
            guard let target = BarNavigation.target(of: command, from: current, in: items) else { return }
            setKeyboardFocus(target, announce: true)

        case .press(let modifiers):
            // A click, with the same reading of the modifiers a click gets — so a key that means
            // nothing on this cell does nothing, as the click would, except say so.
            guard let action = ClickAction.resolve(modifiers: modifiers, for: view.item) else {
                NSSound.beep()
                return
            }
            itemView(view, clicked: action)

        case .showMenu:
            view.showMenu()

        case .leave:
            onLeaveKeyboard?()

        case .type:
            break
        }
    }

    /// Jumps to the cell whose name starts with what has been typed. Matched against the name
    /// VoiceOver reads, which is the translated one: the Trash is found by what it is called in the
    /// language in use.
    private func typeSelect(_ characters: String, from current: Int, continuing: Bool) {
        typed = continuing ? typed + characters : characters
        typedAt = Date()
        let labels = items.map { CellDescription(item: $0)?.label }
        guard let target = BarNavigation.match(typed, labels: labels, from: current) else {
            NSSound.beep()
            return
        }
        if target != current { setKeyboardFocus(target, announce: true) }
    }

    // MARK: - Accessibility

    /// A list, as the system Dock's own is, so VoiceOver can say how long the bar is and where along
    /// it a cell stands.
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .list }

    override func accessibilityLabel() -> String? { "Eskele" }

    override func accessibilityOrientation() -> NSAccessibilityOrientation {
        settings.edge.isVertical ? .vertical : .horizontal
    }

    /// The cells, in bar order. Left to itself AppKit lists subviews in the order they were added,
    /// and a cell made for an app that launched mid-session is added last wherever it sits — so
    /// VoiceOver would have read the bar in the order its apps were opened.
    override func accessibilityChildren() -> [Any]? {
        itemViews.filter { $0.isAccessibilityElement() }
    }

    // MARK: - Dragging destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)

        if sender.draggingPasteboard.availableType(from: [.eskeleItem]) != nil {
            setDropTarget(nil)
            setCaret(insertionIndex(at: point))
            return .move
        }

        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return [] }

        if let target = itemView(at: point), dropAction(for: urls, on: target.item) != nil {
            setCaret(nil)
            setDropTarget(target)
            return target.item.isTrash ? .delete : .generic
        }

        setDropTarget(nil)
        setCaret(insertionIndex(at: point))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setCaret(nil)
        setDropTarget(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        defer {
            setCaret(nil)
            setDropTarget(nil)
        }

        if let id = sender.draggingPasteboard.string(forType: .eskeleItem),
           let item = items.first(where: { $0.id == id }) {
            delegate?.barContent(self, didMove: item, toVisualIndex: insertionIndex(at: point))
            return true
        }

        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }

        if let target = itemView(at: point), dropAction(for: urls, on: target.item) != nil {
            delegate?.barContent(self, didDropFiles: urls, on: target.item)
            return true
        }

        delegate?.barContent(self, didDropFiles: urls, atVisualIndex: insertionIndex(at: point))
        return true
    }

    private enum DropAction { case openWith, trash }

    /// Dropping on the Trash always trashes. Dropping on an app opens the files with it — except
    /// when the payload is itself an application, where "open an app with an app" is meaningless
    /// and the user plainly meant to pin it.
    private func dropAction(for urls: [URL], on item: DockItem) -> DropAction? {
        if item.isTrash { return .trash }
        guard item.isApp else { return nil }
        let allApplications = urls.allSatisfy { $0.pathExtension == "app" }
        return allApplications ? nil : .openWith
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (objects as? [URL]) ?? []
    }

    private func setCaret(_ index: Int?) {
        guard caretIndex != index else { return }
        caretIndex = index
        layoutCaret()
    }

    private func setDropTarget(_ view: ItemView?) {
        guard dropTargetView !== view else { return }
        dropTargetView?.isDropTarget = false
        dropTargetView = view
        view?.isDropTarget = true
    }
}

/// The slabs behind the pinned launchers.
///
/// Drawn rather than a layer per run: how many runs there are depends on how the pins wrapped, and a
/// pool of views that grows and shrinks with the layout is more machinery than two rounded rects
/// deserve.
private final class PinTrayView: NSView {
    var slabs: [NSRect] = [] { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 4 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        for slab in slabs {
            NSBezierPath(roundedRect: slab, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
    }
}

// MARK: - ItemViewDelegate

extension BarContentView {
    /// Where the Apps Menu launcher should hang from, for a caller that has no click to take it
    /// from — the hot key. In this view's own coordinates, so a bar part-way through sliding out
    /// still reports where the cell is going to be rather than where it currently is.
    ///
    /// The cell itself when the bar has one, so the panel opens exactly where clicking would put it.
    /// When the Apps Menu cell is switched off there is no button to point at, and the launcher
    /// falls back to the bar's leading end.
    var appsMenuAnchorInBar: NSRect {
        guard let view = itemViews.first(where: { $0.item.isAppsMenu }) else {
            return NSRect(x: bounds.minX, y: bounds.minY, width: 1, height: bounds.height)
        }
        return view.frame
    }
}

extension BarContentView: ItemViewDelegate {
    func itemViewBeginInteraction(_ view: ItemView) { beginInteraction() }
    func itemViewEndInteraction(_ view: ItemView) { endInteraction() }

    func itemView(_ view: ItemView, clicked action: ClickAction) {
        // Only the plain click opens something here. ⌘-clicking a folder means "show me where this
        // is", which is a thing to do *instead of* opening its stack, not before it.
        if action == .activate {
            // The launcher owns a window rather than a menu, so it outlives this call and reports
            // back when it goes away; everything else here is synchronous.
            if view.item.isAppsMenu {
                let opened = delegate?.barContent(
                    self, showLauncherAt: view.screenFrame, onDismiss: { [weak self] in self?.endInteraction() })
                if opened == true { beginInteraction() }
                return
            }
            // A pinned folder is a stack: it opens a list on a plain click rather than launching.
            if view.item.opensMenuOnClick,
               let menu = delegate?.barContent(self, stackMenuFor: view.item) {
                view.present(menu)
                return
            }
        }
        delegate?.barContent(self, perform: action, on: view.item)
    }

    func itemViewMenu(for view: ItemView) -> NSMenu? {
        delegate?.barContent(self, menuFor: view.item)
    }

    func itemViewShouldBeginDrag(_ view: ItemView) -> Bool {
        // Window buttons reorder within their own app (and move the app when dragged clear of it),
        // so they are draggable too — they just have nothing to pin.
        !view.item.isTrash && !view.item.isAppsMenu
    }

    func itemViewDraggedOutOfBar(_ view: ItemView, at screenPoint: NSPoint) {
        delegate?.barContent(self, didDragOutOfBar: view.item, at: screenPoint)
    }

    func itemView(_ view: ItemView, hoverChanged isHovered: Bool) {
        guard isHovered, !isInteracting else {
            tooltip.hide()
            calendar.hide()
            return
        }
        showLabel(for: view)
    }

    /// What resting on a cell brings up: the pointer's hover, or the keyboard arriving on it.
    fileprivate func showLabel(for view: ItemView) {
        guard let window else { return }

        // The clock answers with a month rather than a line of text: "Thursday 3 September" is
        // already on the bar, and what you actually want from a clock you are pointing at is the
        // rest of the month around it.
        if view.item.isClock {
            tooltip.hide()
            calendar.appearance = settings.appearance.nsAppearance
            calendar.schedule(
                beside: window.convertToScreen(convert(view.frame, to: nil)),
                edge: settings.edge,
                on: window.screen)
            return
        }
        calendar.hide()
        // The closure is only called once the hover delay is up, so sweeping the bar captures
        // nothing; see `HoverTooltip.schedule`.
        let item = view.item
        // The bar shows how far along; the label is the only place that can say how far along
        // *what*, and it is where somebody who has not worked out what the bar means finds out.
        let title = view.progress?.detail.map { "\(item.hoverTitle) — \($0)" } ?? item.hoverTitle
        tooltip.schedule(
            title,
            beside: window.convertToScreen(convert(view.frame, to: nil)),
            edge: settings.edge,
            on: window.screen,
            preview: settings.windowPreviews
                ? { [weak self] in
                    guard let self else { return nil }
                    return await self.delegate?.barContent(self, previewFor: item)
                }
                : nil)
    }
}
