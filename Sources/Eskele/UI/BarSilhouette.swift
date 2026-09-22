import SwiftUI

/// A miniature of the bar a given `Settings` produces: a scrap of desktop with the bar on the right
/// edge of it, in the right proportion, holding the right shapes.
///
/// It is drawn from the settings rather than hand-drawn per design, so the three tiles in the picker
/// cannot quietly stop describing the designs they apply.
///
/// **Not to scale, deliberately.** A real bar is about 3% of the screen's height; at tile size that
/// is under a point and reads as a hairline. The thicknesses below are exaggerated but keep the one
/// ratio that carries meaning — Big is exactly 1.5x Small, as it is on screen.
struct BarSilhouette: View {
    let settings: Settings

    /// The size the miniature is drawn at.
    ///
    /// Not a suggestion: a full-height vertical bar is five cells, the gaps between them and the
    /// menu bar above, all of them fixed, so anything shorter than this overflows its frame and
    /// spills over whatever is drawn under it. Callers that want a smaller tile scale the whole
    /// miniature down rather than handing it a smaller frame — see `DesignMenuRow`.
    static let naturalSize = CGSize(width: 98, height: 64)
    /// The corner the tile is cut to, at `naturalSize`. Scales with it.
    static let naturalCornerRadius: CGFloat = 7

    /// How many app cells to imply. Enough to show a group, few enough to fit the narrowest tile.
    private static let appCount = 3

    private var vertical: Bool { settings.edge.isVertical }
    private var thickness: CGFloat { settings.barSize == .big ? 12 : 8 }
    private var menuBarHeight: CGFloat { 6 }
    private var cellInset: CGFloat { 2 }
    private var cell: CGFloat { thickness - 2 * cellInset }
    private var gap: CGFloat { settings.barSize == .big ? 3 : 2 }
    /// A label is worth drawing only where the real bar would draw one.
    private var labelWidth: CGFloat { 20 }

    var body: some View {
        ZStack(alignment: barAlignment) {
            wallpaper
            menuBar
            bar
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.naturalCornerRadius, style: .continuous))
    }

    // MARK: - Desktop

    private var wallpaper: some View {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.31, blue: 0.72),
                Color(red: 0.33, green: 0.31, blue: 0.78),
                Color(red: 0.52, green: 0.32, blue: 0.70),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// The one edge Eskele never takes. Drawing it gives the bar's own edge something to be *not*.
    private var menuBar: some View {
        Color.white.opacity(0.22)
            .frame(height: menuBarHeight)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private var barAlignment: Alignment {
        switch settings.edge {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    // MARK: - Bar

    private var bar: some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: gap))
            : AnyLayout(HStackLayout(spacing: gap))

        return layout {
            // In full span the strip is pushed around by the alignment; hugging, it has nowhere to go.
            if settings.spanMode == .fullSpan && settings.itemAlignment != .leading {
                Spacer(minLength: 0)
            }
            appsMenuCell
            ForEach(0..<Self.appCount, id: \.self) { _ in appCell }
            if settings.spanMode == .fullSpan && settings.itemAlignment != .trailing {
                Spacer(minLength: 0)
            }
            // The Trash sits beside the apps on a hugging bar and at the far end on a full one.
            trashCell
        }
        .padding(vertical ? .vertical : .horizontal, cellInset)
        .frame(
            width: vertical ? thickness : nil,
            height: vertical ? nil : thickness
        )
        .frame(
            maxWidth: !vertical && settings.spanMode == .fullSpan ? .infinity : nil,
            maxHeight: vertical && settings.spanMode == .fullSpan ? .infinity : nil
        )
        .background {
            RoundedRectangle(cornerRadius: settings.effectiveCornerRadius > 0 ? 3 : 0, style: .continuous)
                .fill(.white.opacity(0.34))
        }
        // A vertical bar starts below the menu bar, which is not its to occupy. This has to come
        // after the background, or the background fills the very gap it is leaving.
        .padding(.top, vertical ? menuBarHeight : 0)
    }

    // MARK: - Cells

    private var appsMenuCell: some View {
        square.opacity(1)
    }

    /// With labels on, a running app is a button wide enough for a name, with its icon at the leading
    /// end of it. Two tones rather than an icon plus a hairline: at this size a name drawn as a rule
    /// reads as a dash floating in the bar, not as a button.
    @ViewBuilder private var appCell: some View {
        if settings.drawsLabels {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.white.opacity(0.42))
                    .frame(height: cell)
                square
            }
            .frame(width: labelWidth)
        } else {
            square
        }
    }

    private var trashCell: some View {
        square.opacity(0.6)
    }

    private var square: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(.white.opacity(0.92))
            .frame(width: cell, height: cell)
    }
}
