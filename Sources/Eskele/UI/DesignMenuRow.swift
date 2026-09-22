import AppKit
import SwiftUI

/// The design picker at menu size: the same miniatures the settings window draws, small enough that
/// all four fit across one row of a menu.
///
/// AppKit rather than a hosted SwiftUI picker. A menu item's view has to take its own clicks and
/// then dismiss the menu around it, which is plain target/action work. What SwiftUI is good for
/// here is the drawing, so each tile — miniature, ring and name together — is rendered from
/// `BarSilhouette`, the one description of what a design looks like, and AppKit only shows the
/// image and reports the click.
@MainActor
final class DesignMenuRow: NSView {
    /// Smaller than the settings window's tiles: four of these plus their names have to fit across a
    /// menu without making it wider than the screen corner it drops out of.
    ///
    /// The miniature is *scaled* to this rather than drawn into it. Its contents are fixed sizes
    /// that a smaller frame does not shrink, so squeezing the frame would only make a full-height
    /// bar spill out of the bottom of its tile and over the name underneath.
    fileprivate static let tileWidth: CGFloat = 72
    fileprivate static let tileScale = tileWidth / BarSilhouette.naturalSize.width
    fileprivate static let tileHeight = (BarSilhouette.naturalSize.height * tileScale).rounded()
    fileprivate static let cornerRadius = (BarSilhouette.naturalCornerRadius * tileScale).rounded()
    /// Room for the selection ring to sit outside the tile without touching it.
    fileprivate static let ringInset: CGFloat = 3

    private static let spacing: CGFloat = 8
    /// Lined up with the menu's own text column, so the tiles start where the section header above
    /// them and the item titles below them do rather than floating in from the edge. Measured to
    /// the tile itself, which is why the ring's inset comes off it.
    private static let insetX: CGFloat = 21 - ringInset
    private static let insetY: CGFloat = 6
    private static let presets = DesignPreset.allCases

    private let select: (DesignPreset) -> Void

    init(settings: Settings, select: @escaping (DesignPreset) -> Void) {
        self.select = select

        let selection = DesignPreset.matching(settings)
        let tiles = Self.presets.map { preset -> (preset: DesignPreset, preview: Settings?, image: NSImage?) in
            let preview = preset.preview(in: settings)
            return (preset, preview, Self.tileImage(
                title: preset.title, preview: preview, isSelected: selection == preset))
        }

        // Laid out from what was actually drawn, so the row cannot end up shorter than its tiles
        // and clip the names off the bottom — which is what an assumed label height would risk.
        let tileSize = tiles.compactMap { $0.image?.size }.max { $0.height < $1.height }
            ?? NSSize(width: Self.tileWidth + 2 * Self.ringInset, height: Self.tileHeight)
        let columns = CGFloat(tiles.count)
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: 2 * Self.insetX + columns * tileSize.width + (columns - 1) * Self.spacing,
            height: tileSize.height + 2 * Self.insetY))

        for (index, tile) in tiles.enumerated() {
            let frame = NSRect(
                x: Self.insetX + CGFloat(index) * (tileSize.width + Self.spacing),
                y: Self.insetY,
                width: tileSize.width,
                height: tileSize.height)
            let isAvailable = tile.preview != nil

            // The tile is drawn by an image view and clicked through a transparent button over it.
            // A button asked to draw the image itself insets it by its cell's margins, which at
            // this size is the difference between a name under the tile and no name at all.
            let artwork = NSImageView(frame: frame)
            artwork.image = tile.image
            artwork.imageScaling = .scaleNone
            // A Custom nobody has made yet has nothing to go back to, so there is nothing to pick.
            artwork.alphaValue = isAvailable ? 1 : 0.4
            addSubview(artwork)

            let button = NSButton(frame: frame)
            button.isTransparent = true
            button.title = ""
            button.target = self
            button.tag = index
            button.action = #selector(pick(_:))
            button.isEnabled = isAvailable
            button.toolTip = isAvailable ? tile.preset.detail : Self.unmadeCustomHelp
            button.setAccessibilityLabel(tile.preset.title)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func pick(_ sender: NSButton) {
        guard Self.presets.indices.contains(sender.tag) else { return }
        select(Self.presets[sender.tag])
    }

    /// The tile as a bitmap.
    ///
    /// Rendered per menu opening rather than cached: the menu is rebuilt each time it drops down
    /// anyway, and the tiles have to follow the accent colour, the appearance and — for Custom —
    /// whatever the user last arranged.
    private static func tileImage(title: String, preview: Settings?, isSelected: Bool) -> NSImage? {
        // `shared` rather than `NSApp`, which is nil until something has asked for `shared` — true in
        // the app long before a menu opens, and in a test only if another test happened to run first.
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let renderer = ImageRenderer(
            content: DesignMenuTile(title: title, preview: preview, isSelected: isSelected)
                .environment(\.colorScheme, isDark ? .dark : .light))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    static let unmadeCustomHelp = """
        Change any setting and the result is kept here, ready to come back to.
        """
}

/// One tile of the menu row: the miniature, a hairline around it, the accent ring outside that when
/// it is the design in use, and the name underneath — drawn the way the settings window draws its
/// own, only smaller.
///
/// The name is part of the image rather than the button's title. A button that is mostly a picture
/// gives its title whatever room the picture leaves, which at this size is none; drawing the two
/// together also means the whole column is one target to click.
private struct DesignMenuTile: View {
    let title: String
    let preview: Settings?
    let isSelected: Bool

    private var cornerRadius: CGFloat { DesignMenuRow.cornerRadius }
    private var ringInset: CGFloat { DesignMenuRow.ringInset }

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let preview {
                    BarSilhouette(settings: preview)
                } else {
                    unmadeCustom
                }
            }
            .frame(
                width: BarSilhouette.naturalSize.width,
                height: BarSilhouette.naturalSize.height)
            .scaleEffect(DesignMenuRow.tileScale)
            // `scaleEffect` draws smaller without laying out smaller, so the tile is told what it
            // now occupies. The hairline and the ring below are drawn at that size, unscaled, and
            // so keep their weight instead of thinning away with the miniature.
            .frame(width: DesignMenuRow.tileWidth, height: DesignMenuRow.tileHeight)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.black.opacity(0.25), lineWidth: 0.5)
            }
            .padding(ringInset)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius + ringInset, style: .continuous)
                    // Asked for by name rather than as `.accentColor`: a rendered image has no
                    // window behind it to inherit the system's accent from.
                    .strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }

            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .padding(.bottom, 2)
    }

    /// The Custom tile before there is a custom design: a blank of the same shape, so the row keeps
    /// its rhythm and the slot reads as one waiting to be filled rather than one that is missing.
    ///
    /// Drawn heavier than the settings window's version of it: the row dims the whole tile to say
    /// it cannot be picked, and a placeholder that started faint would dim away to nothing.
    private var unmadeCustom: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BarSilhouette.naturalCornerRadius, style: .continuous)
                .fill(Color(nsColor: .tertiaryLabelColor))
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
        }
    }
}
