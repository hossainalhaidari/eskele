import AppKit

/// What the bar needs to know about a display: which one it is, and where its menu bar is.
///
/// Not how thick to be. The bar's thickness is a setting, the same on every display
/// (`Settings.rowThickness`); the menu bar is measured only to keep out of its way.
@MainActor
enum ScreenMetrics {
    /// The screen that owns the menu bar.
    static var menuBarScreen: NSScreen? { NSScreen.screens.first }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }

    /// Space the menu bar reserves at the top of *this* screen, or 0 if it has none.
    ///
    /// A secondary screen without "Displays have separate Spaces" has no menu bar, and insetting for
    /// one would leave a gap for nothing.
    static func menuBarInset(for screen: NSScreen) -> CGFloat {
        // Only the menu bar shrinks visibleFrame at the top; the Dock can never live there.
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        if reserved > 1 { return reserved }
        return max(0, screen.safeAreaInsets.top)
    }
}

/// Unscaled base values. `BarMetrics` multiplies these by the chosen bar size.
enum BarLayout {
    /// How far the icon is pushed off the screen-facing edge so the indicator has somewhere to sit.
    /// Small on purpose: this used to be a 5pt exclusive lane, which cost the icons more than the
    /// indicator was worth.
    static let indicatorAllowance: CGFloat = 3
    /// A pill rather than a dot — the same visual weight in half the thickness.
    static let indicatorThickness: CGFloat = 2
    static let endPadding: CGFloat = 6
    /// As many rows as uBar offers. Past five a bar is a grid, and five rows of a Big bar already
    /// come to most of a laptop display.
    static let maximumRows = 5
    static let separatorLength: CGFloat = 9
    static let horizontalPadding: CGFloat = 5
    static let labelGap: CGFloat = 6
}
