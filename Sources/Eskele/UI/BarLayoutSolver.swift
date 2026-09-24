import CoreGraphics

/// Distributes the bar's length across its cells.
///
/// Every cell has a floor (its icon-only width) and a ceiling (icon plus label, capped). When there
/// is room, everyone gets their ceiling. When there is not, the surplus above the floors is shared
/// out in proportion to how much each cell wanted to grow — so labelled buttons give up width evenly
/// and collapse back to plain icons together, rather than the last few vanishing while the first
/// stay full width.
///
/// Pure and separately testable: this is the part of expanded mode most likely to be wrong.
enum BarLayoutSolver {
    /// - Parameters:
    ///   - minimums: the icon-only width of each cell. Never violated.
    ///   - desired: what each cell would take if the bar were unbounded. Must be >= its minimum.
    ///   - available: length the cells have to share, excluding the bar's end padding.
    static func lengths(minimums: [CGFloat], desired: [CGFloat], available: CGFloat) -> [CGFloat] {
        precondition(minimums.count == desired.count)
        guard !minimums.isEmpty else { return [] }

        let ceilings = zip(minimums, desired).map { Swift.max($0, $1) }
        let desiredTotal = ceilings.reduce(0, +)
        if desiredTotal <= available { return ceilings }

        let floorTotal = minimums.reduce(0, +)
        // Even the floors do not fit. Overflow is the caller's problem (the strip clips); shrinking
        // below the icon size would just produce unreadable slivers.
        guard available > floorTotal else { return minimums }

        let growthWanted = zip(ceilings, minimums).map { $0 - $1 }
        let totalGrowth = growthWanted.reduce(0, +)
        guard totalGrowth > 0 else { return minimums }

        let slack = available - floorTotal
        return zip(minimums, growthWanted).map { minimum, growth in
            minimum + slack * (growth / totalGrowth)
        }
    }

    /// Splits the cells into rows, in order, one contiguous run per row.
    ///
    /// Every row aims at an equal share of the total, and nothing else. The bar is as many rows
    /// thick as the user asked for whether or not the cells need them all (see `Settings.barRows`),
    /// so filling each row before starting the next would leave a three-row bar showing one row of
    /// icons and two empty strips.
    ///
    /// Deliberately blind to how long the bar actually is. Wrapping at the bar's length instead
    /// would give thirty buttons on a two-row bar ten comfortable ones and twenty crammed into what
    /// was left; an equal share gives fifteen and fifteen, squeezed alike. A row that comes out
    /// longer than the bar is `lengths`'s problem, which is what `lengths` is for.
    ///
    /// - Returns: one range per row, covering the cells in order. Never more than `rowCount` ranges,
    ///   and fewer when there are not enough cells to go round.
    static func rows(minimums: [CGFloat], desired: [CGFloat], rows rowCount: Int) -> [Range<Int>] {
        precondition(minimums.count == desired.count)
        let count = minimums.count
        guard count > 0 else { return [] }
        guard rowCount > 1 else { return [0..<count] }

        let ceilings = zip(minimums, desired).map { Swift.max($0, $1) }
        let target = ceilings.reduce(0, +) / CGFloat(rowCount)

        var result: [Range<Int>] = []
        var start = 0
        var length: CGFloat = 0
        for index in 0..<count {
            let ceiling = ceilings[index]
            // Rounding rather than truncation: a cell is taken when it leaves the row closer to the
            // target than leaving it out would. Truncating alone packs the early rows and leaves the
            // last one carrying everything that did not fit.
            let overshoots = (length + ceiling - target) > (target - length)
            let isLastRow = result.count == rowCount - 1
            // A row that already holds something can wrap; an empty one takes the cell whatever its
            // size, because it has to go somewhere. The last row keeps the remainder for the same
            // reason: there is nowhere else to put it.
            if !isLastRow, index > start, overshoots {
                result.append(start..<index)
                start = index
                length = 0
            }
            length += ceiling
        }
        result.append(start..<count)
        return result
    }
}

/// Works out where the bar's window sits on a screen.
///
/// Pulled out of the window controller and made pure because it is fiddly in exactly the way that
/// hides bugs: three edges, two span modes, bottom-left screen coordinates, and one region at the
/// top of the display that is not ours to use.
enum BarFrameSolver {
    /// - Parameters:
    ///   - screen: the display's full frame, not its visible frame — the bar sits at the physical edge.
    ///   - menuBarInset: space the menu bar reserves at the top of this screen, or 0 if it has none.
    ///     Only a vertical bar runs into it; a bottom bar never does.
    ///   - preferredLength: what the contents would like, used only when hugging.
    ///   - endMargin: breathing room left at each end of a hugging bar.
    static func frame(
        screen: CGRect,
        menuBarInset: CGFloat,
        edge: BarEdge,
        spanMode: SpanMode,
        thickness: CGFloat,
        preferredLength: CGFloat,
        endMargin: CGFloat
    ) -> CGRect {
        let vertical = edge.isVertical
        // The stretch of edge the bar is allowed to occupy, in screen coordinates.
        let regionStart = vertical ? screen.minY : screen.minX
        let regionLength = (vertical ? screen.height : screen.width) - (vertical ? menuBarInset : 0)

        let length: CGFloat = switch spanMode {
        case .fullSpan:
            regionLength
        case .hugContents:
            min(preferredLength, max(thickness, regionLength - 2 * endMargin))
        }

        // Centred in the region — which for a full span is simply the region itself.
        let origin = regionStart + (regionLength - length) / 2

        return switch edge {
        case .bottom:
            CGRect(x: origin, y: screen.minY, width: length, height: thickness)
        case .left:
            CGRect(x: screen.minX, y: origin, width: thickness, height: length)
        case .right:
            CGRect(x: screen.maxX - thickness, y: origin, width: thickness, height: length)
        }
    }
}

/// Sizes the running indicator: one dash per window, up to a limit.
///
/// Pure so the awkward part — what happens as dashes multiply inside a fixed icon width — can be
/// tested rather than eyeballed.
enum WindowIndicator {
    /// Past this many, more dashes stop meaning anything and only make each one unreadable.
    static let maximumDashes = 4

    static func dashCount(forWindows windows: Int) -> Int {
        // Zero windows still gets one dash: the app is running, and an unknown window count (no
        // Accessibility) must not read as "no windows".
        max(1, min(maximumDashes, windows))
    }

    /// The one dash to draw bright on the frontmost app, or nil to light them all.
    ///
    /// All of them is the fallback, and the look this had before: the group still has to read as
    /// the frontmost app when the focused window is unknown — an untitled or duplicate-titled
    /// window — or is past the cap, where lighting the last dash would name the wrong window.
    static func highlightedDash(focusedWindow: Int?, dashes: Int) -> Int? {
        guard dashes > 1, let focusedWindow, (0..<dashes).contains(focusedWindow) else { return nil }
        return focusedWindow
    }

    struct Layout: Equatable {
        var dash: CGFloat
        var gap: CGFloat
        var total: CGFloat
        /// The focused window's dash, drawn `focusedDash` long while every other dash is a dot.
        var focused: Int? = nil
        var focusedDash: CGFloat = 0

        func length(ofDash index: Int) -> CGFloat {
            index == focused ? focusedDash : dash
        }
    }

    /// A single dash keeps exactly the length it had before this feature existed, so the common case
    /// looks unchanged. Additional dashes shrink to fit rather than widening the group indefinitely.
    ///
    /// - Parameter focused: the dash to expand, from `highlightedDash`. The others shrink to dots
    ///   and it takes the length a single-window frontmost app's dash has, so the long dash means
    ///   "the window you are on" whether the app has one window or four.
    static func layout(
        dashes: Int,
        iconSize: CGFloat,
        weight: CGFloat,
        isFrontmost: Bool,
        focused: Int? = nil
    ) -> Layout {
        let count = max(1, dashes)
        let gap = max(2, weight)
        let ceiling = iconSize * 0.85

        if let focused, count > 1, (0..<count).contains(focused) {
            let others = CGFloat(count - 1) * (weight + gap)
            // Round *down* for the same reason as below. The floor keeps it longer than a dot even
            // on the smallest bar, where the fitted length would otherwise run into the dots' size.
            let expanded = max(weight * 2, min((iconSize * 0.5).rounded(), (ceiling - others).rounded(.down)))
            return Layout(
                dash: weight, gap: gap, total: others + expanded,
                focused: focused, focusedDash: expanded)
        }

        let single = (iconSize * (isFrontmost ? 0.5 : 0.3)).rounded()

        var dash = single
        var total = CGFloat(count) * dash + CGFloat(count - 1) * gap
        if total > ceiling {
            // Round *down*: rounding up can push the recomputed total back past the ceiling.
            dash = max(3, ((ceiling - CGFloat(count - 1) * gap) / CGFloat(count)).rounded(.down))
            total = CGFloat(count) * dash + CGFloat(count - 1) * gap
        }
        return Layout(dash: dash, gap: gap, total: total)
    }
}
