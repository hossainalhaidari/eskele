import AppKit

/// The status item's icon: the app icon's pier, over one line of water.
///
/// Drawn rather than bundled, for the reason `Scripts/make-icon.sh` derives the .icns from the
/// layer art instead of drawing it a second time — one set of coordinates to edit when the pier
/// changes. These are `Resources/AppIcon.icon/Assets/bar.svg`'s proportions on a 180-unit grid,
/// which is the 18pt icon at ten units to the point, the scale that keeps every feature whole.
///
/// The water is the app icon's two layers reduced to one line: a reflection at menu-bar size is
/// half a point of grey and reads as a smudge, where a single wave still reads as water.
enum StatusItemIcon {
    /// 18pt inside the menu bar's 22. Larger crowds its neighbours, smaller reads as an afterthought.
    static let side: CGFloat = 18

    /// The grid the geometry below is written on. Ten units to the point.
    private static let grid: CGFloat = 180

    /// A template image: only the alpha channel reaches the screen and the system supplies the
    /// colour, which is what lets one drawing serve a light menu bar, a dark one, and the
    /// increased-contrast and tinted appearances.
    static func make() -> NSImage {
        // Flipped, so the numbers below read the same way round as the SVG they came from.
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let scale = side / grid
            pier(scale: scale).fill()
            water(scale: scale).stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Eskele"
        return image
    }

    /// The bar, with its three ports punched through rather than painted over. A template image has
    /// no colour to paint them in: anything drawn on top of the bar would be drawn in the bar's own
    /// tint and vanish. The app icon punches them for the same reason.
    private static func pier(scale: CGFloat) -> NSBezierPath {
        let x0 = 6 * scale, x1 = 174 * scale
        let height = 50 * scale
        let centre = 66 * scale

        let path = NSBezierPath(
            roundedRect: NSRect(x: x0, y: centre - height / 2, width: x1 - x0, height: height),
            xRadius: height / 2, yRadius: height / 2)

        // The first port a quarter of the way in, the last a quarter from the end, as on the icon.
        let span = x1 - x0
        let inset = span * 0.25
        let step = (span - inset * 2) / 2
        let radius = 10 * scale
        for i in 0..<3 {
            let x = x0 + inset + CGFloat(i) * step
            path.appendOval(in: NSRect(
                x: x - radius, y: centre - radius, width: radius * 2, height: radius * 2))
        }
        // Even-odd is what makes the three ovals holes instead of a second pass of fill.
        path.windingRule = .evenOdd
        return path
    }

    /// One run of the app icon's water line: four half-waves across the pier, stroked a little under
    /// a third of a half-wave thick. That ratio is the icon's own, and it is the whole design —
    /// tighter or heavier and the curve stops reading as water and starts reading as a scribble.
    private static func water(scale: CGFloat) -> NSBezierPath {
        // Inset past the pier's ends by half a stroke, so the round caps land inside the canvas.
        let x0 = 14 * scale, x1 = 166 * scale
        let baseline = 128 * scale
        let half = (x1 - x0) / 4
        let amplitude = 19 * scale

        let path = NSBezierPath()
        path.move(to: NSPoint(x: x0, y: baseline))
        for i in 0..<4 {
            let start = x0 + CGFloat(i) * half
            // Crest, trough, crest, trough: the control point changes side each half-wave, which is
            // what the SVG says with one Q and a run of Ts.
            let lift = i.isMultiple(of: 2) ? -amplitude : amplitude
            path.curve(
                to: NSPoint(x: start + half, y: baseline),
                controlPoint: NSPoint(x: start + half / 2, y: baseline + lift))
        }
        path.lineWidth = 14 * scale
        path.lineCapStyle = .round
        return path
    }
}
