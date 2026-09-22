import AppKit

/// Every derived measurement the bar draws with, computed once per layout pass.
///
/// This exists because `barSize` scales roughly eight different constants at once — padding, the
/// indicator, label type, button widths. Scattering `* multiplier` through the drawing code is how
/// one of them silently gets missed and the big bar ends up looking like the small one with gaps.
struct BarMetrics: Equatable {
    /// Thickness of a single row. Everything a cell is drawn from derives from this rather than from
    /// the bar's own thickness, so a two-row bar draws two rows of ordinary cells instead of one row
    /// of enormous ones.
    var thickness: CGFloat
    var rows: Int
    var iconSize: CGFloat
    var iconPadding: CGFloat
    /// Gap on the screen-facing side, which the running indicator sits inside.
    var outerInset: CGFloat
    var indicatorWeight: CGFloat
    var itemSpacing: CGFloat
    var endPadding: CGFloat
    var separatorLength: CGFloat
    var horizontalPadding: CGFloat
    var labelGap: CGFloat
    var labelFontSize: CGFloat
    var buttonWidth: CGFloat
    var cornerRadius: CGFloat
    /// Inset of a cell's drawn background from its frame, along the bar's long axis. Cells sit
    /// flush against each other, so the visible gap between two buttons is twice this.
    var backgroundInset: CGFloat
    /// The same, across the bar — the space between a button and the bar's own edges. A point more
    /// than the along-axis inset in labelled mode: a slab that comes within a hair of the top and
    /// bottom reads as filling the bar rather than sitting in it.
    var crossInset: CGFloat

    var labelFont: NSFont { .systemFont(ofSize: labelFontSize) }

    /// The bar's own thickness, across every row.
    var totalThickness: CGFloat { thickness * CGFloat(rows) }

    init(thickness: CGFloat, settings: Settings) {
        let scale = settings.barSize.multiplier
        self.thickness = thickness
        rows = settings.rowCount

        iconPadding = (settings.iconPadding * scale).rounded()
        // A labelled bar shows running state as a button fill, so it needs no indicator margin.
        let indicatorMargin = (BarLayout.indicatorAllowance * scale).rounded()
        outerInset = settings.drawsLabels ? iconPadding : max(iconPadding, indicatorMargin)
        iconSize = max(12, thickness - iconPadding - outerInset)

        indicatorWeight = max(2, (BarLayout.indicatorThickness * scale).rounded())
        itemSpacing = (settings.itemSpacing * scale).rounded()
        endPadding = (BarLayout.endPadding * scale).rounded()
        separatorLength = (BarLayout.separatorLength * scale).rounded()
        horizontalPadding = (BarLayout.horizontalPadding * scale).rounded()
        labelGap = (BarLayout.labelGap * scale).rounded()
        // Type scales less than the furniture around it; past ~14pt a taskbar label starts to shout.
        labelFontSize = min(14, (NSFont.smallSystemFontSize * scale).rounded())
        // Scaled like everything else: a Big bar has larger icons and larger type, so its buttons
        // want to be proportionally wider — 140 becomes 210.
        buttonWidth = (CGFloat(settings.expandedItemWidth) * scale).rounded()
        cornerRadius = (settings.effectiveCornerRadius * scale).rounded()
        // Labelled buttons are persistent slabs and need air on every side — between each other,
        // and away from the top and bottom of the bar, which they would otherwise sit flush
        // against. Icon cells only ever show a fleeting hover highlight and can be tighter. Not
        // scaled by bar size: a couple of points of separation reads the same at either scale.
        backgroundInset = settings.drawsLabels ? 2 : 1
        crossInset = settings.drawsLabels ? 3 : 1
    }
}
