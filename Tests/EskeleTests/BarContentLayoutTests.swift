import AppKit
import Testing
@testable import Eskele

/// A Small bar, which is what every measurement in this file is written against — the thicknesses
/// passed below are the menu bar's own 32pt, not a scaled one.
///
/// `Settings()` used to mean this. It now defaults to Big, because the defaults are the Dock design
/// (`DesignPreset.dock`), so the unscaled baseline has to be asked for by name.
private func smallSettings() -> Settings {
    var settings = Settings()
    settings.barSize = .small
    return settings
}

@MainActor
private func makeStrip(
    runningApps: Int,
    named name: String,
    width: CGFloat,
    style: BarItemStyle = .expanded,
    maxButton: Double = 320,
    span: SpanMode = .hugContents
) -> (BarContentView, [ItemView]) {
    var settings = smallSettings()
    settings.itemStyle = style
    settings.edge = .bottom
    settings.expandedItemWidth = maxButton
    settings.spanMode = span
    settings.showAppsMenu = false
    settings.showTrash = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let items = (0..<runningApps).map { index in
        DockItem(
            kind: .app(AppRef(bundleID: "test.app.\(index)", url: url, name: name)),
            isPinned: true,
            isRunning: true
        )
    }

    let view = BarContentView()
    view.configure(items: items, settings: settings, thickness: 32, scale: 2)
    view.frame = NSRect(x: 0, y: 0, width: width, height: 32)
    view.layoutSubtreeIfNeeded()

    return (view, view.subviews.compactMap { $0 as? ItemView })
}

@MainActor
@Test func labelledButtonsGrowBeyondIconWidth() {
    let (view, cells) = makeStrip(runningApps: 3, named: "Some Application", width: 900)
    #expect(cells.count == 3)
    // Comfortably more room than needed: every button gets its full width and its label.
    #expect(cells.allSatisfy({ $0.frame.width > 100 }))
    #expect(cells.allSatisfy({ $0.showsLabel }))
    #expect(view.preferredLength < 900)
}

@MainActor
@Test func buttonsShareTheSpaceWhenTheBarIsTight() {
    let (_, cells) = makeStrip(runningApps: 12, named: "A Rather Long Application Name", width: 700)
    let widths = cells.map(\.frame.width)

    // Nothing may spill past the end of the bar.
    #expect(widths.reduce(0, +) <= 700)
    // Identical items must end up identical widths, not first-come-first-served.
    #expect((widths.max() ?? 0) - (widths.min() ?? 0) < 0.5)
}

/// The whole point of the mode: it degrades to the icon-only bar rather than breaking.
@MainActor
@Test func buttonsCollapseToIconsWhenSpaceRunsOut() {
    let (_, cells) = makeStrip(runningApps: 20, named: "A Rather Long Application Name", width: 620)
    #expect(cells.allSatisfy({ !$0.showsLabel }))
    // 32pt bar, 2pt padding, no indicator lane in labelled mode → 28pt icons, 4pt spacing.
    #expect(cells.allSatisfy({ $0.frame.width <= 34 }))
}

@MainActor
@Test func compactModeIgnoresLabelsEntirely() {
    let (_, cells) = makeStrip(runningApps: 3, named: "Some Application", width: 900, style: .compact)
    #expect(cells.allSatisfy({ !$0.showsLabel }))
    #expect(cells.allSatisfy({ $0.frame.width < 40 }))
}

/// A pinned app that is not running is a shortcut, not a task; it stays an icon like on Windows.
@MainActor
@Test func onlyRunningAppsBecomeButtons() {
    var settings = smallSettings()
    settings.itemStyle = .expanded
    settings.edge = .bottom
    settings.showTrash = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let items = [
        DockItem(kind: .app(AppRef(bundleID: "a", url: url, name: "Running App")), isPinned: true, isRunning: true),
        DockItem(kind: .app(AppRef(bundleID: "b", url: url, name: "Idle App")), isPinned: true, isRunning: false),
    ]

    let view = BarContentView()
    view.configure(items: items, settings: settings, thickness: 32, scale: 2)
    view.frame = NSRect(x: 0, y: 0, width: 800, height: 32)
    view.layoutSubtreeIfNeeded()

    let cells = view.subviews.compactMap { $0 as? ItemView }
    #expect(cells[0].showsLabel)
    #expect(!cells[1].showsLabel)
    #expect(cells[0].frame.width > cells[1].frame.width)
}

/// A vertical bar is one icon wide, so labels are refused there whatever the setting.
@MainActor
@Test func verticalBarsStayCompact() {
    var settings = smallSettings()
    settings.itemStyle = .expanded
    settings.edge = .left
    #expect(!settings.drawsLabels)

    settings.edge = .bottom
    #expect(settings.drawsLabels)
}

// MARK: - Rows

@MainActor
private func makeRows(
    runningApps: Int,
    rows: Int,
    width: CGFloat,
    edge: BarEdge = .bottom,
    rowThickness: CGFloat = 32
) -> [ItemView] {
    var settings = smallSettings()
    settings.edge = edge
    settings.barRows = rows
    settings.itemStyle = .compact
    settings.showAppsMenu = false
    settings.showTrash = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let items = (0..<runningApps).map { index in
        DockItem(
            kind: .app(AppRef(bundleID: "test.app.\(index)", url: url, name: "App")),
            isPinned: true,
            isRunning: true)
    }

    let view = BarContentView()
    view.configure(items: items, settings: settings, thickness: rowThickness, scale: 2)
    let across = rowThickness * CGFloat(rows)
    view.frame = edge.isVertical
        ? NSRect(x: 0, y: 0, width: across, height: width)
        : NSRect(x: 0, y: 0, width: width, height: across)
    view.layoutSubtreeIfNeeded()
    return view.subviews.compactMap { $0 as? ItemView }
}

/// Each row is one row's thickness, whatever the bar's own; the cells are not stretched to fill it.
@MainActor
@Test func rowsSplitTheBarAcrossItsThickness() {
    let cells = makeRows(runningApps: 8, rows: 2, width: 600)
    #expect(cells.count == 8)
    #expect(cells.allSatisfy { $0.frame.height == 32 })

    let bands = Set(cells.map(\.frame.minY))
    #expect(bands == [0, 32])
    // Evenly, and in order: the first four on the upper row, the rest below.
    #expect(cells.prefix(4).allSatisfy { $0.frame.minY == 32 })
    #expect(cells.suffix(4).allSatisfy { $0.frame.minY == 0 })
}

/// Cells within a row still follow one another, and no two cells ever overlap.
@MainActor
@Test func rowedCellsNeverOverlap() {
    for rows in 1...4 {
        let cells = makeRows(runningApps: 11, rows: rows, width: 500)
        for (a, b) in cells.enumerated().flatMap({ i, cell in
            cells.dropFirst(i + 1).map { (cell, $0) }
        }) {
            #expect(!a.frame.intersects(b.frame))
        }
    }
}

/// On a side bar the rows are columns, running outwards from the display edge.
@MainActor
@Test func verticalBarsWrapIntoColumns() {
    let cells = makeRows(runningApps: 6, rows: 2, width: 400, edge: .left)
    #expect(cells.allSatisfy { $0.frame.width == 32 })
    #expect(Set(cells.map(\.frame.minX)) == [0, 32])
    #expect(cells.prefix(3).allSatisfy { $0.frame.minX == 0 })
}

/// A one-row bar has to lay out exactly as it did before rows existed.
@MainActor
@Test func oneRowIsUnchanged() {
    let single = makeRows(runningApps: 6, rows: 1, width: 600)
    #expect(single.allSatisfy { $0.frame.height == 32 && $0.frame.minY == 0 })
}

/// A hand-edited settings file cannot ask for a bar of eleven rows, or of none.
@Test func rowCountIsClamped() {
    var settings = Settings()
    settings.barRows = 40
    #expect(settings.rowCount == BarLayout.maximumRows)
    settings.barRows = 0
    #expect(settings.rowCount == 1)
    settings.barRows = 3
    #expect(BarMetrics(thickness: 32, settings: settings).totalThickness == 96)
}

/// Small and Big are fixed sizes, the same on every display: nothing about the screen is measured.
@Test func theTwoSizesAreFixed() {
    var settings = Settings()
    settings.barSize = .small
    #expect(settings.rowThickness == 32)
    settings.barSize = .big
    #expect(settings.rowThickness == 48)
    settings.barRows = 2
    #expect(settings.totalThickness == 96)
}

/// The nudge moves either size, but a hand-edited file cannot make a bar too thin for an icon.
@Test func theThicknessNudgeIsClamped() {
    var settings = Settings()
    settings.barSize = .small
    settings.thicknessNudge = 4
    #expect(settings.rowThickness == 36)
    settings.thicknessNudge = -100
    #expect(settings.rowThickness == 18)
    settings.thicknessNudge = 100
    #expect(settings.rowThickness == 96)
}

// MARK: - Icon size vs the running indicator

/// The indicator used to take a 5pt lane out of a 32pt bar, leaving 23pt icons. It now overlays a
/// 3pt margin, so the icon keeps almost the whole thickness.
@Test func compactIconsUseNearlyTheWholeThickness() {
    var settings = smallSettings()
    settings.iconPadding = 2
    let metrics = BarMetrics(thickness: 32, settings: settings)
    #expect(metrics.iconSize == 27)
    #expect(metrics.outerInset == 3)
}

/// Labelled bars need no margin at all, since running state is a button fill there.
@Test func labelledIconsGetTheFullThickness() {
    var settings = smallSettings()
    settings.iconPadding = 2
    settings.itemStyle = .expanded
    settings.edge = .bottom
    let metrics = BarMetrics(thickness: 32, settings: settings)
    #expect(metrics.iconSize == 28)
    #expect(metrics.outerInset == 2)
}

/// Generous padding must win over the indicator margin rather than being clamped down to it.
@Test func paddingLargerThanTheIndicatorMarginIsRespected() {
    var settings = smallSettings()
    settings.iconPadding = 6
    let metrics = BarMetrics(thickness: 32, settings: settings)
    #expect(metrics.outerInset == 6)
    #expect(metrics.iconSize == 20)
}

@Test func iconSizeNeverCollapses() {
    var settings = smallSettings()
    settings.iconPadding = 8
    #expect(BarMetrics(thickness: 18, settings: settings).iconSize >= 12)
}

// MARK: - Bar size

/// Big is 1.5x the menu bar. On this machine's 32pt menu bar that is a 48pt bar with 40pt icons —
/// close to the macOS Dock's own 42pt default.
@MainActor
@Test func bigScalesTheWholeBarNotJustTheThickness() {
    var settings = smallSettings()
    settings.barSize = .big
    let metrics = BarMetrics(thickness: 48, settings: settings)

    #expect(metrics.iconSize == 40)
    #expect(metrics.iconPadding == 3)
    #expect(metrics.outerInset == 5)
    #expect(metrics.indicatorWeight == 3)
    #expect(metrics.labelFontSize > BarMetrics(thickness: 32, settings: smallSettings()).labelFontSize)
}

/// The icon should occupy the same fraction of the bar at either scale — otherwise Big just looks
/// like Small with padding bolted on.
@MainActor
@Test func iconToBarRatioHoldsAcrossScales() {
    let small = BarMetrics(thickness: 32, settings: smallSettings())
    var bigSettings = smallSettings()
    bigSettings.barSize = .big
    let big = BarMetrics(thickness: 48, settings: bigSettings)

    let smallRatio = small.iconSize / small.thickness
    let bigRatio = big.iconSize / big.thickness
    #expect(abs(smallRatio - bigRatio) < 0.03)
}

/// Label type must not scale linearly with the furniture or a big bar starts shouting.
@Test func labelTypeIsCapped() {
    var settings = smallSettings()
    settings.barSize = .big
    #expect(BarMetrics(thickness: 48, settings: settings).labelFontSize <= 14)
}

// MARK: - Trailing group in full-width mode

@MainActor
private func makeBarWithTrash(
    span: SpanMode,
    edge: BarEdge = .bottom,
    alignment: ItemAlignment = .center,
    length: CGFloat = 1200,
    clock: Bool = false
) -> (BarContentView, [ItemView]) {
    var settings = smallSettings()
    settings.spanMode = span
    settings.edge = edge
    settings.itemAlignment = alignment
    settings.showTrash = true
    settings.showAppsMenu = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    var items = (0..<4).map { index in
        DockItem(kind: .app(AppRef(bundleID: "t.\(index)", url: url, name: "App \(index)")), isPinned: true)
    }
    items.append(DockItem(kind: .trash(isEmpty: true)))
    if clock {
        settings.showClock = true
        items.append(DockItem(kind: .clock))
    }

    let view = BarContentView()
    view.configure(items: items, settings: settings, thickness: 32, scale: 2)
    view.frame = edge.isVertical
        ? NSRect(x: 0, y: 0, width: 32, height: length)
        : NSRect(x: 0, y: 0, width: length, height: 32)
    view.layoutSubtreeIfNeeded()
    return (view, view.subviews.compactMap { $0 as? ItemView })
}

@MainActor
@Test func fullWidthPushesTheTrashToTheFarRight() {
    let (view, cells) = makeBarWithTrash(span: .fullSpan)
    let trash = cells.last!
    #expect(trash.item.isTrash)
    #expect(trash.frame.maxX > view.bounds.maxX - 12)
    // And it is nowhere near the apps, which stay in the middle.
    #expect(trash.frame.minX - cells[3].frame.maxX > 200)
}

/// On a vertical bar the far end is the bottom.
@MainActor
@Test func fullHeightPushesTheTrashToTheBottom() {
    let (view, cells) = makeBarWithTrash(span: .fullSpan, edge: .left)
    let trash = cells.last!
    #expect(trash.item.isTrash)
    #expect(trash.frame.minY < view.bounds.minY + 12)
    #expect(cells[3].frame.minY - trash.frame.maxY > 200)
}

/// A hugging bar has no gap to spread across, so nothing moves.
@MainActor
@Test func huggingBarKeepsTheTrashBesideTheApps() {
    let (_, cells) = makeBarWithTrash(span: .hugContents)
    let trash = cells.last!
    #expect(abs(trash.frame.minX - cells[3].frame.maxX) < 1)
}

/// With everything pushed right, the apps must stop before the Trash rather than collide with it.
@MainActor
@Test func trailingAlignedAppsDoNotCollideWithTheTrash() {
    let (_, cells) = makeBarWithTrash(span: .fullSpan, alignment: .trailing)
    let trash = cells.last!
    #expect(cells[3].frame.maxX <= trash.frame.minX + 0.5)
}

@MainActor
@Test func leadingAlignedAppsStartAtTheEdgeWithTrashStillFarRight() {
    let (view, cells) = makeBarWithTrash(span: .fullSpan, alignment: .leading)
    #expect(cells[0].frame.minX < 12)
    #expect(cells.last!.frame.maxX > view.bounds.maxX - 12)
}

/// Cells must never overlap, whatever the alignment or span.
@MainActor
@Test func cellsNeverOverlap() {
    for span in [SpanMode.fullSpan, .hugContents] {
        for alignment in ItemAlignment.allCases {
            let (_, cells) = makeBarWithTrash(span: span, alignment: alignment)
            let sorted = cells.map(\.frame).sorted { $0.minX < $1.minX }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                #expect(a.maxX <= b.minX + 0.5)
            }
        }
    }
}

// MARK: - Multiple windows

/// However many windows an app has, the hover label names the one it is showing — the count is
/// already said by the dashes, and saying it twice costs the label the only line it has.
@Test func theHoverLabelNamesTheWindowNotTheCount() {
    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    var item = DockItem(kind: .app(AppRef(bundleID: "a", url: url, name: "Safari")), isRunning: true)

    item.windowCount = 3
    #expect(item.hoverTitle == "Safari")
    item.windowTitle = "GitHub"
    #expect(item.hoverTitle == "GitHub")
}

@Test func nonAppItemsNeverClaimWindows() {
    var trash = DockItem(kind: .trash(isEmpty: true))
    trash.windowCount = 5
    #expect(trash.hoverTitle == "Trash")
    #expect(trash.displayName == "Trash")
}

// MARK: - Fixed-width buttons in full-width mode

/// A taskbar reads as a taskbar because the buttons are uniform, not ragged.
@MainActor
@Test func fullWidthButtonsTakeTheConfiguredWidthRegardlessOfName() {
    var settings = smallSettings()
    settings.itemStyle = .expanded
    settings.spanMode = .fullSpan
    settings.edge = .bottom
    settings.expandedItemWidth = 140
    settings.showTrash = false
    settings.showAppsMenu = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let names = ["X", "Mail", "A Very Long Application Name Indeed"]
    let items = names.enumerated().map { index, name in
        DockItem(kind: .app(AppRef(bundleID: "w.\(index)", url: url, name: name)),
                 isPinned: true, isRunning: true)
    }

    let view = BarContentView()
    view.configure(items: items, settings: settings, thickness: 32, scale: 2)
    view.frame = NSRect(x: 0, y: 0, width: 1400, height: 32)
    view.layoutSubtreeIfNeeded()

    let widths = view.subviews.compactMap { ($0 as? ItemView)?.frame.width }
    #expect(widths.count == 3)
    // A one-character name and a very long one get the same button.
    #expect(widths.allSatisfy({ abs($0 - 140) < 0.5 }))
}

/// Hugging bars still size to their text, so a short list stays compact.
@MainActor
@Test func huggingButtonsStillSizeToTheirText() {
    let (_, short) = makeStrip(runningApps: 1, named: "X", width: 1400, maxButton: 140)
    let (_, long) = makeStrip(runningApps: 1, named: "A Very Long Application Name", width: 1400, maxButton: 140)
    #expect(short[0].frame.width < long[0].frame.width)
    #expect(long[0].frame.width <= 140.5)
}

/// Too many buttons for the bar: they give up width together, not first-come-first-served.
@MainActor
@Test func fullWidthButtonsShrinkEquallyWhenCrowded() {
    let (_, cells) = makeStrip(
        runningApps: 14, named: "Some Application", width: 1000, maxButton: 140, span: .fullSpan)
    let widths = cells.map(\.frame.width)

    #expect(widths.reduce(0, +) <= 1000)
    #expect((widths.max() ?? 0) - (widths.min() ?? 0) < 0.5)
    // Genuinely shrunk below the configured width, but not collapsed.
    #expect((widths.first ?? 0) < 140)
    #expect((widths.first ?? 0) > 30)
}

/// And when even that is not enough, they fall back to plain icons rather than slivers.
@MainActor
@Test func fullWidthButtonsCollapseToIconsUnderExtremePressure() {
    let (_, cells) = makeStrip(
        runningApps: 30, named: "Some Application", width: 700, maxButton: 140, span: .fullSpan)
    #expect(cells.allSatisfy({ !$0.showsLabel }))
    #expect(cells.allSatisfy({ $0.frame.width <= 34 }))
}

// MARK: - Per-window tasks

/// Splitting needs both room for a title and the space of a full-width bar.
@Test func windowsSplitOnlyWhereThereIsRoomForTitles() {
    var settings = smallSettings()
    settings.separateWindows = true

    settings.itemStyle = .expanded
    settings.spanMode = .fullSpan
    settings.edge = .bottom
    #expect(settings.splitsWindows)

    settings.spanMode = .hugContents
    #expect(!settings.splitsWindows)          // no room to spread out

    settings.spanMode = .fullSpan
    settings.itemStyle = .compact
    #expect(!settings.splitsWindows)          // identical icons would say nothing

    settings.itemStyle = .expanded
    settings.edge = .left
    #expect(!settings.splitsWindows)          // a vertical bar has no room for a title

    settings.edge = .bottom
    settings.separateWindows = false
    #expect(!settings.splitsWindows)
}

@Test func windowItemsAreIdentifiedIndependently() {
    let a = WindowRef(pid: 42, title: "Inbox", isMinimized: false)
    let b = WindowRef(pid: 42, title: "Drafts", isMinimized: false)
    // Two windows of one app that happen to share a title still get distinct identities.
    let c = WindowRef(pid: 42, title: "Inbox", isMinimized: false, duplicateIndex: 1)
    #expect(a.id != b.id)
    #expect(a.id != c.id)
}

@Test func aWindowItemShowsItsTitleAndNamesItsApp() {
    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let app = AppRef(bundleID: "com.apple.Safari", url: url, name: "Safari")
    let window = WindowRef(pid: 9, title: "GitHub", isMinimized: false)
    let item = DockItem(kind: .window(app, window), isRunning: true)

    #expect(item.displayName == "GitHub")
    #expect(item.hoverTitle == "GitHub")
    #expect(item.isWindow)
    #expect(item.isTask)
    #expect(!item.isApp)
    // The icon still comes from the application.
    #expect(item.url == url)
}

/// Window buttons are laid out exactly like app buttons — fixed width, ellipsis, no dragging.
@MainActor
@Test func windowButtonsGetTheSameFixedWidth() {
    var settings = smallSettings()
    settings.itemStyle = .expanded
    settings.spanMode = .fullSpan
    settings.edge = .bottom
    settings.expandedItemWidth = 140
    settings.showTrash = false
    settings.showAppsMenu = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let app = AppRef(bundleID: "com.apple.Safari", url: url, name: "Safari")
    let titles = ["A", "An Extremely Long Web Page Title That Will Not Fit"]
    let items = titles.enumerated().map { index, title in
        DockItem(
            kind: .window(app, WindowRef(pid: 9, title: title, isMinimized: false, duplicateIndex: index)),
            isRunning: true, windowCount: 1)
    }

    let view = BarContentView()
    view.configure(items: items, settings: settings, thickness: 32, scale: 2)
    view.frame = NSRect(x: 0, y: 0, width: 1400, height: 32)
    view.layoutSubtreeIfNeeded()

    let cells = view.subviews.compactMap { $0 as? ItemView }
    #expect(cells.count == 2)
    #expect(cells.allSatisfy({ abs($0.frame.width - 140) < 0.5 }))
    #expect(cells.allSatisfy({ $0.showsLabel }))
}

// MARK: - Cells that share an identity

/// The bug this guards: views were reused through a dictionary keyed by item id, so when two cells
/// shared an id — two copies of one app, as Godot's editor and the game it runs are — one view fell
/// out of the table without being removed. It stayed on the bar for good, drawn with whatever it
/// last showed, and no later rebuild, layout or settings change ever reached it again.
@MainActor
@Test func cellsSharingAnIdentityLeaveNoViewBehind() {
    var settings = smallSettings()
    settings.showAppsMenu = false
    settings.showTrash = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let godot = DockItem(
        kind: .app(AppRef(bundleID: "org.godotengine.godot", url: url, name: "Godot")), isRunning: true)
    let finder = DockItem(
        kind: .app(AppRef(bundleID: "com.apple.finder", url: url, name: "Finder")), isRunning: true)

    let view = BarContentView()
    func cellCount(after items: [DockItem]) -> Int {
        view.configure(items: items, settings: settings, thickness: 32, scale: 2)
        return view.subviews.count { $0 is ItemView }
    }
    #expect(cellCount(after: [finder, godot, godot]) == 3)
    #expect(cellCount(after: [finder, godot]) == 2)
    #expect(cellCount(after: [finder]) == 1)
    #expect(cellCount(after: []) == 0)
}

/// A second copy of an app is a cell of its own, not a second claim on the first copy's identity —
/// which is where the shared ids above came from.
@Test func aSecondCopyOfAnAppHasItsOwnIdentity() {
    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let ref = AppRef(bundleID: "org.godotengine.godot", url: url, name: "Godot")
    let first = DockItem(kind: .app(ref), isRunning: true, pid: 100)
    let second = DockItem(kind: .app(ref), isRunning: true, pid: 200, instance: 200)

    // The first copy keeps the id that pins and stored arrangements are matched against.
    #expect(first.id == "app:org.godotengine.godot")
    #expect(second.id != first.id)
    // And their windows cannot collide either, since a window's id carries its own process.
    #expect(WindowRef(pid: 100, title: "Main.tscn", isMinimized: false).id
        != WindowRef(pid: 200, title: "Main.tscn", isMinimized: false).id)
}

// MARK: - Spacing between buttons

@MainActor
private func drawnGap(style: BarItemStyle) -> CGFloat {
    let (view, cells) = makeStrip(
        runningApps: 3, named: "Some App", width: 1400, style: style, maxButton: 140, span: .fullSpan)
    _ = view
    let first = cells[0]
    let second = cells[1]
    // Cells sit flush, so the visible gap is the space between the drawn backgrounds.
    let firstRight = first.frame.minX + first.backgroundRect.maxX
    let secondLeft = second.frame.minX + second.backgroundRect.minX
    return secondLeft - firstRight
}

@MainActor
@Test func labelledButtonsHaveMoreAirBetweenThemThanIcons() {
    #expect(drawnGap(style: .expanded) == 4)
    #expect(drawnGap(style: .compact) == 2)
}

/// The vertical inset is the one that changed; widening the gap between buttons at the same time
/// would have quietly reflowed every labelled bar.
@MainActor
@Test func theExtraVerticalInsetDoesNotWidenTheGapBetweenButtons() {
    #expect(drawnGap(style: .expanded) == 4)
    let metrics = BarMetrics(thickness: 32, settings: {
        var settings = smallSettings(); settings.itemStyle = .expanded; return settings
    }())
    #expect(metrics.crossInset == metrics.backgroundInset + 1)
}

/// The extra gap comes out of the drawn slab, not the cell — button pitch stays exactly as set.
@MainActor
@Test func theWiderGapDoesNotChangeButtonPitch() {
    let (_, cells) = makeStrip(
        runningApps: 3, named: "Some App", width: 1400, maxButton: 140, span: .fullSpan)
    #expect(cells.allSatisfy({ abs($0.frame.width - 140) < 0.5 }))
    #expect(abs((cells[1].frame.minX - cells[0].frame.minX) - 140) < 0.5)
}

/// Labelled buttons must not sit flush against the top and bottom of the bar.
@MainActor
@Test func labelledButtonsAreInsetFromTheBarEdges() {
    let (_, labelled) = makeStrip(
        runningApps: 2, named: "Some App", width: 1400, style: .expanded, span: .fullSpan)
    let button = labelled[0]
    // A point more across the bar than along it, so the slab sits in the bar rather than filling it.
    #expect(button.backgroundRect.minY == 3)
    #expect(button.backgroundRect.maxY == button.bounds.maxY - 3)

    // Icon cells stay tighter: their highlight is fleeting rather than a permanent slab.
    let (_, icons) = makeStrip(
        runningApps: 2, named: "Some App", width: 1400, style: .compact, span: .fullSpan)
    #expect(icons[0].backgroundRect.minY == 1)
}

// MARK: - Pins and badges

@MainActor
private func strip(_ items: [DockItem], settings: Settings, width: CGFloat) -> (BarContentView, [ItemView]) {
    let view = BarContentView()
    view.configure(items: items, settings: settings, thickness: 32, scale: 2)
    view.frame = NSRect(x: 0, y: 0, width: width, height: 32)
    view.layoutSubtreeIfNeeded()
    return (view, view.subviews.compactMap { $0 as? ItemView })
}

/// Request in full: with labels on, the pinned apps sit at the leading end as compact icons and the
/// running apps get the buttons — not a row of half-buttons with the labels missing.
@MainActor
@Test func pinnedLaunchersStayIconSizedAtTheLeadingEndInLabelledMode() {
    var settings = smallSettings()
    settings.itemStyle = .expanded
    settings.edge = .bottom
    settings.spanMode = .fullSpan
    settings.showAppsMenu = false
    settings.showTrash = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    func app(_ name: String, running: Bool) -> DockItem {
        DockItem(kind: .app(AppRef(bundleID: "test.\(name)", url: url, name: name)),
                 isPinned: true, isRunning: running)
    }

    let groups = BarComposition.groups(
        for: [app("Safari", running: false), app("Mail", running: true), app("Notes", running: false)],
        groupsPins: settings.groupsPins)
    let (_, cells) = strip(
        BarComposition.strip(leading: [], groups: groups, trailing: []), settings: settings, width: 900)

    #expect(cells.map(\.item.displayName) == ["Safari", "Notes", "", "Mail"])
    // The two pins and the divider are compact; only the running app becomes a button.
    #expect(cells[0].frame.width < 40)
    #expect(cells[1].frame.width < 40)
    #expect(cells[3].frame.width > 100)
    #expect(cells[3].showsLabel)
    #expect(!cells[0].showsLabel && !cells[1].showsLabel)
}

/// A badge is drawn over the icon, so it must not push anything around — a number appearing should
/// never make the bar reflow.
@MainActor
@Test func aBadgeDoesNotChangeTheLayout() {
    var settings = smallSettings()
    settings.showAppsMenu = false
    settings.showTrash = false

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    var plain = DockItem(kind: .app(AppRef(bundleID: "test.mail", url: url, name: "Mail")),
                         isPinned: true, isRunning: true)
    var badged = plain
    badged.badge = 128

    let (bare, without) = strip([plain], settings: settings, width: 400)
    let (_, with) = strip([badged], settings: settings, width: 400)
    #expect(without[0].frame == with[0].frame)
    #expect(bare.preferredLength > 0)
}

/// Attention is said by the glow, which is visible without hovering; the label stays the title.
@MainActor
@Test func attentionDoesNotHijackTheHoverLabel() {
    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    var item = DockItem(kind: .app(AppRef(bundleID: "test.mail", url: url, name: "Mail")),
                        isPinned: true, isRunning: true)
    item.needsAttention = true
    item.windowTitle = "Inbox — iCloud"
    #expect(item.hoverTitle == "Inbox — iCloud")
}

// MARK: - The Trash and the clock both hold the far end

/// The bug this guards: the anchor used to be "is the last cell the Trash?", so putting a clock
/// after the Trash meant the last cell was no longer the Trash, nothing was held at the end, and
/// the whole strip — Trash included — closed up beside the apps.
@MainActor
@Test func theClockAndTheTrashBothStayAtTheFarEnd() {
    let (view, cells) = makeBarWithTrash(span: .fullSpan, alignment: .leading, clock: true)
    let clock = try! #require(cells.last)
    let trash = try! #require(cells.dropLast().last)

    #expect(clock.item.isClock)
    #expect(trash.item.isTrash)
    // The clock ends at the far edge, and the Trash is immediately before it — not back with
    // the apps.
    #expect(clock.frame.maxX > view.bounds.maxX - 12)
    #expect(trash.frame.maxX <= clock.frame.minX + 0.5)
    #expect(trash.frame.minX > view.bounds.midX)
    // The apps are still at the leading edge.
    #expect(cells[0].frame.minX < 12)
}

/// A clock with the Trash switched off has to hold the end on its own.
@MainActor
@Test func theClockHoldsTheEndWithoutTheTrash() {
    var settings = smallSettings()
    settings.spanMode = .fullSpan
    settings.itemAlignment = .leading
    settings.showTrash = false
    settings.showAppsMenu = false
    settings.showClock = true

    let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    var items = (0..<3).map { index in
        DockItem(kind: .app(AppRef(bundleID: "c.\(index)", url: url, name: "App \(index)")), isPinned: true)
    }
    items.append(DockItem(kind: .clock))

    let view = BarContentView()
    view.configure(items: items, settings: settings, thickness: 32, scale: 2)
    view.frame = NSRect(x: 0, y: 0, width: 1200, height: 32)
    view.layoutSubtreeIfNeeded()

    let cells = view.subviews.compactMap { $0 as? ItemView }
    let clock = try! #require(cells.last)
    #expect(clock.item.isClock)
    #expect(clock.frame.maxX > view.bounds.maxX - 12)
    #expect(cells[0].frame.minX < 12)
}

/// A bar that hugs its icons has no gap to push into, so both stay beside the apps — the same
/// bargain the Trash has always struck.
@MainActor
@Test func aHuggingBarKeepsTheClockBesideTheApps() {
    let (_, cells) = makeBarWithTrash(span: .hugContents, clock: true)
    let clock = try! #require(cells.last)
    let trash = try! #require(cells.dropLast().last)
    #expect(clock.frame.minX - trash.frame.maxX < 12)
}

/// Whatever is at the end, nothing may overlap.
@MainActor
@Test func cellsNeverOverlapWithAClock() {
    for span in [SpanMode.fullSpan, .hugContents] {
        for alignment in ItemAlignment.allCases {
            let (_, cells) = makeBarWithTrash(span: span, alignment: alignment, clock: true)
            let sorted = cells.map(\.frame).sorted { $0.minX < $1.minX }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                #expect(a.maxX <= b.minX + 0.5, "\(span) \(alignment) overlaps")
            }
        }
    }
}

/// On a side bar the same run has to hold the *bottom*, which is that bar's far end.
@MainActor
@Test func onASideBarTheClockAndTrashHoldTheBottom() {
    let (view, cells) = makeBarWithTrash(
        span: .fullSpan, edge: .left, alignment: .leading, clock: true)
    let clock = try! #require(cells.last)
    let trash = try! #require(cells.dropLast().last)
    #expect(clock.frame.minY < 12)
    #expect(trash.frame.minY >= clock.frame.maxY - 0.5)
    #expect(trash.frame.maxY < view.bounds.midY)
}
