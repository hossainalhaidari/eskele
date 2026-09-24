import CoreGraphics
import Testing
@testable import Eskele

private func approx(_ values: [CGFloat], _ expected: [CGFloat], tolerance: CGFloat = 0.01) -> Bool {
    values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < tolerance }
}

@Test func everyoneGetsTheirCeilingWhenThereIsRoom() {
    let lengths = BarLayoutSolver.lengths(
        minimums: [28, 28, 28], desired: [168, 100, 28], available: 500)
    #expect(approx(lengths, [168, 100, 28]))
}

@Test func exactFitIsNotTreatedAsOverflow() {
    let lengths = BarLayoutSolver.lengths(minimums: [28, 28], desired: [100, 100], available: 200)
    #expect(approx(lengths, [100, 100]))
}

/// The surplus is shared in proportion to how much each cell wanted, so buttons narrow together.
@Test func overflowSharesTheSurplusProportionally() {
    // Floors 28+28 = 56; ceilings 128+78 = 206; growth wanted 100 and 50.
    // 116 available → 60 of slack → 40 and 20.
    let lengths = BarLayoutSolver.lengths(
        minimums: [28, 28], desired: [128, 78], available: 116)
    #expect(approx(lengths, [68, 48]))
}

@Test func cellsCollapseToIconsWhenSpaceRunsOut() {
    let lengths = BarLayoutSolver.lengths(
        minimums: [28, 28, 28], desired: [168, 168, 168], available: 84)
    #expect(approx(lengths, [28, 28, 28]))
}

/// Below the sum of the floors we stop shrinking: sub-icon slivers help nobody, and the strip clips.
@Test func floorsAreNeverViolated() {
    let lengths = BarLayoutSolver.lengths(
        minimums: [28, 28, 28], desired: [168, 168, 168], available: 10)
    #expect(approx(lengths, [28, 28, 28]))
    #expect(lengths.allSatisfy { $0 >= 28 })
}

/// A cell that never wanted to grow keeps its exact width while its neighbours shrink around it.
@Test func nonGrowingCellsAreLeftAlone() {
    let lengths = BarLayoutSolver.lengths(
        minimums: [28, 28], desired: [28, 128], available: 78)
    #expect(approx(lengths, [28, 50]))
}

@Test func allFixedCellsOverflowRatherThanShrink() {
    let lengths = BarLayoutSolver.lengths(minimums: [28, 28], desired: [28, 28], available: 20)
    #expect(approx(lengths, [28, 28]))
}

@Test func emptyBarIsHandled() {
    #expect(BarLayoutSolver.lengths(minimums: [], desired: [], available: 100).isEmpty)
}

/// Whatever the pressure, the total never exceeds what was available unless the floors already did.
@Test func totalNeverExceedsAvailableWhileFloorsFit() {
    for available in stride(from: CGFloat(90), through: 600, by: 30) {
        let lengths = BarLayoutSolver.lengths(
            minimums: [28, 28, 28], desired: [168, 120, 90], available: available)
        #expect(lengths.reduce(0, +) <= max(available, 84) + 0.01)
    }
}

// MARK: - Window placement

/// This display: 1470x956 with a 33pt menu bar reservation at the top.
private let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
private let menuBar: CGFloat = 33

private func solve(
    _ edge: BarEdge,
    _ span: SpanMode,
    thickness: CGFloat = 32,
    preferred: CGFloat = 300,
    inset: CGFloat = menuBar
) -> CGRect {
    BarFrameSolver.frame(
        screen: display, menuBarInset: inset, edge: edge, spanMode: span,
        thickness: thickness, preferredLength: preferred, endMargin: 12)
}

/// The bug this was extracted to fix: a full-height bar ran the whole display and sat underneath
/// the menu bar.
@Test func fullHeightBarStopsBelowTheMenuBar() {
    for edge in [BarEdge.left, .right] {
        let frame = solve(edge, .fullSpan)
        #expect(frame.maxY == display.maxY - menuBar)
        #expect(frame.minY == display.minY)
        #expect(frame.height == display.height - menuBar)
    }
}

/// A hugging vertical bar is centred in the space below the menu bar, not on the display, or it
/// creeps upward as it grows.
@Test func huggingVerticalBarIsCentredBelowTheMenuBar() {
    let frame = solve(.left, .hugContents, preferred: 300)
    #expect(frame.height == 300)
    #expect(frame.maxY <= display.maxY - menuBar)
    let above = (display.maxY - menuBar) - frame.maxY
    let below = frame.minY - display.minY
    #expect(abs(above - below) < 1)
}

/// However many items pile up, a vertical bar may not grow into the menu bar.
@Test func aVeryLongVerticalBarIsStillClamped() {
    let frame = solve(.left, .hugContents, preferred: 5000)
    #expect(frame.maxY <= display.maxY - menuBar)
    #expect(frame.height == display.height - menuBar - 24)
}

/// A bottom bar never meets the menu bar, so the inset must not shorten it.
@Test func horizontalBarsAreUnaffectedByTheMenuBar() {
    let full = solve(.bottom, .fullSpan)
    #expect(full.width == display.width)
    #expect(full.minX == 0)
    #expect(full.minY == display.minY)

    let hugging = solve(.bottom, .hugContents, preferred: 300)
    #expect(hugging.width == 300)
    #expect(abs(hugging.midX - display.midX) < 1)
}

@Test func barsSitFlushAgainstTheirOwnEdge() {
    #expect(solve(.left, .fullSpan).minX == display.minX)
    #expect(solve(.right, .fullSpan).maxX == display.maxX)
    #expect(solve(.bottom, .fullSpan).minY == display.minY)
    #expect(solve(.right, .fullSpan, thickness: 48).width == 48)
    #expect(solve(.right, .fullSpan, thickness: 48).minX == display.maxX - 48)
}

/// A secondary display without its own menu bar reports no inset and should use its whole height.
@Test func aScreenWithoutAMenuBarUsesItsFullHeight() {
    let frame = solve(.left, .fullSpan, inset: 0)
    #expect(frame.height == display.height)
    #expect(frame.maxY == display.maxY)
}

/// Big bars must clamp against the same boundary.
@Test func theBigScaleRespectsTheMenuBarToo() {
    let frame = solve(.right, .fullSpan, thickness: 48)
    #expect(frame.maxY == display.maxY - menuBar)
    #expect(frame.width == 48)
}

// MARK: - Rows

private func rows(_ ceilings: [CGFloat], rows count: Int) -> [Range<Int>] {
    BarLayoutSolver.rows(minimums: ceilings.map { _ in 28 }, desired: ceilings, rows: count)
}

/// One row is the behaviour every other test in this file assumes; it must stay exactly that.
@Test func oneRowKeepsEveryCellTogether() {
    #expect(rows([100, 100, 100], rows: 1) == [0..<3])
    #expect(rows([], rows: 1).isEmpty)
    #expect(rows([], rows: 4).isEmpty)
}

/// The rows were asked for, so they are used even when everything would fit on one line.
@Test func cellsSpreadAcrossTheRowsEvenWithRoomToSpare() {
    #expect(rows([100, 100, 100, 100], rows: 2) == [0..<2, 2..<4])
}

/// An odd cell out goes wherever it leaves the rows closest to even.
@Test func anOddCellDoesNotAllLandOnTheLastRow() {
    #expect(rows([100, 100, 100], rows: 2) == [0..<2, 2..<3])
}

/// The case the feature exists for: thirty buttons that will not fit however they are arranged.
/// Both rows have to be squeezed alike, not one comfortable row and one crammed one.
@Test func anOverfullBarSqueezesItsRowsEqually() {
    let split = rows(Array(repeating: 140, count: 30), rows: 2)
    #expect(split.map(\.count) == [15, 15])
}

@Test func thirdsAreThirds() {
    #expect(rows(Array(repeating: 100, count: 9), rows: 3).map(\.count) == [3, 3, 3])
}

/// A cell wider than an entire share still has to go somewhere.
@Test func anOversizedCellDoesNotWrapForever() {
    let split = rows([900, 100, 100], rows: 3)
    #expect(split.first == 0..<1)
    #expect(split.flatMap { Array($0) } == [0, 1, 2])
}

/// Never more rows than were asked for, and never a gap in the middle.
@Test func rowsCoverEveryCellInOrder() {
    for count in 1...5 {
        for cells in 0...12 {
            let split = rows(Array(repeating: 100, count: cells), rows: count)
            #expect(split.count <= count)
            #expect(split.flatMap { Array($0) } == Array(0..<cells))
        }
    }
}

/// Cells of wildly different widths balance by *length*, not by count — the rows are strips of bar,
/// and two of them holding the same number of very different cells would not look balanced at all.
@Test func unevenCellsBalanceByLength() {
    let split = rows([300, 100, 100, 100], rows: 2)
    #expect(split == [0..<1, 1..<4])
}

// MARK: - Window indicator

/// An app with no reported windows is still running; it must not look like it has none.
@Test func unknownWindowCountStillShowsOneDash() {
    #expect(WindowIndicator.dashCount(forWindows: 0) == 1)
    #expect(WindowIndicator.dashCount(forWindows: 1) == 1)
}

@Test func dashCountIsCapped() {
    #expect(WindowIndicator.dashCount(forWindows: 3) == 3)
    #expect(WindowIndicator.dashCount(forWindows: 4) == 4)
    #expect(WindowIndicator.dashCount(forWindows: 25) == WindowIndicator.maximumDashes)
}

/// The single-window case must look exactly as it did before dashes existed.
@Test func oneDashKeepsTheOriginalLength() {
    let active = WindowIndicator.layout(dashes: 1, iconSize: 40, weight: 3, isFrontmost: true)
    let idle = WindowIndicator.layout(dashes: 1, iconSize: 40, weight: 3, isFrontmost: false)
    #expect(active.dash == 20)   // 0.5 x icon
    #expect(idle.dash == 12)     // 0.3 x icon
    #expect(active.total == active.dash)
}

/// More dashes must not widen the group past the icon; they shrink instead.
@Test func dashesShrinkRatherThanOverflow() {
    let ceiling = 40 * 0.85
    for count in 1...WindowIndicator.maximumDashes {
        let layout = WindowIndicator.layout(dashes: count, iconSize: 40, weight: 3, isFrontmost: true)
        #expect(layout.total <= ceiling + 0.5)
        #expect(layout.dash >= 3)
    }
}

/// The focused window's dash is the one lit, in the order the dashes are drawn.
@Test func focusedWindowLightsItsOwnDash() {
    #expect(WindowIndicator.highlightedDash(focusedWindow: 1, dashes: 3) == 1)
    #expect(WindowIndicator.highlightedDash(focusedWindow: 0, dashes: 4) == 0)
}

/// Anything that cannot name one dash lights them all, so the frontmost app never goes dim.
@Test func unplaceableFocusLightsEveryDash() {
    #expect(WindowIndicator.highlightedDash(focusedWindow: nil, dashes: 3) == nil)
    // Past the cap: the last dash would claim a window it does not stand for.
    #expect(WindowIndicator.highlightedDash(focusedWindow: 5, dashes: 4) == nil)
    // A lone dash is the whole app; there is nothing to single out.
    #expect(WindowIndicator.highlightedDash(focusedWindow: 0, dashes: 1) == nil)
}

/// The focused window's dash is the one a single-window frontmost app would draw; the rest are dots.
@Test func focusedDashExpandsAndTheRestAreDots() {
    let layout = WindowIndicator.layout(
        dashes: 3, iconSize: 40, weight: 3, isFrontmost: true, focused: 1)
    #expect(layout.length(ofDash: 1) == 20)   // 0.5 x icon, as a lone frontmost dash
    #expect(layout.length(ofDash: 0) == 3)    // a dot: as long as it is thick
    #expect(layout.length(ofDash: 2) == 3)
    #expect(layout.total == 20 + 2 * 3 + 2 * layout.gap)
}

/// Which dash is expanded must not change the group's length, or cycling would make it jump.
@Test func expandingADashKeepsTheGroupInPlace() {
    let totals = (0..<4).map {
        WindowIndicator.layout(dashes: 4, iconSize: 40, weight: 3, isFrontmost: true, focused: $0).total
    }
    #expect(Set(totals).count == 1)
}

/// With four windows on the smallest bar the expanded dash shrinks to fit, but stays a dash.
@Test func expandedDashFitsAtTheSmallestScale() {
    for (icon, weight) in [(CGFloat(27), CGFloat(2)), (40, 3)] {
        let layout = WindowIndicator.layout(
            dashes: 4, iconSize: icon, weight: weight, isFrontmost: true, focused: 3)
        #expect(layout.total <= icon * 0.85 + 0.5)
        #expect(layout.length(ofDash: 3) >= weight * 2)
    }
}

/// A focus that names no dash leaves the even row alone.
@Test func unplaceableFocusKeepsEvenDashes() {
    let plain = WindowIndicator.layout(dashes: 3, iconSize: 40, weight: 3, isFrontmost: true)
    #expect(WindowIndicator.layout(
        dashes: 3, iconSize: 40, weight: 3, isFrontmost: true, focused: 7) == plain)
    #expect(WindowIndicator.layout(dashes: 1, iconSize: 40, weight: 3, isFrontmost: true, focused: 0)
        == WindowIndicator.layout(dashes: 1, iconSize: 40, weight: 3, isFrontmost: true))
}

/// Every dash is the same size — an uneven group would read as meaning something.
@Test func dashesStayLegibleAtTheSmallestScale() {
    let layout = WindowIndicator.layout(dashes: 4, iconSize: 27, weight: 2, isFrontmost: false)
    #expect(layout.dash >= 3)
    #expect(layout.total <= 27 * 0.85 + 0.5)
}
