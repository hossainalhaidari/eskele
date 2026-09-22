import AppKit
import Testing
@testable import Eskele

/// Rasterises the icon one pixel per unit of the design grid, so the coordinates the assertions use
/// are the coordinates `StatusItemIcon` is written in. Ten times menu-bar size, which costs nothing
/// here and makes every sample land unambiguously inside or outside a feature.
@MainActor private func rendered() -> NSBitmapImageRep {
    let side = 180
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    StatusItemIcon.make().draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    return rep
}

/// Coverage at a point on the design grid. A template image is its alpha channel and nothing else,
/// so this is the only thing about a pixel worth asserting on.
@MainActor private func ink(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
    rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
}

@MainActor @Test func theIconIsATemplateAtMenuBarSize() {
    let image = StatusItemIcon.make()
    #expect(image.isTemplate)
    #expect(image.size == NSSize(width: StatusItemIcon.side, height: StatusItemIcon.side))
}

/// The three ports are holes, not dots. A template image is painted in one colour by the system, so
/// a port drawn on top of the pier would be drawn in the pier's own tint and vanish — the app icon
/// punches them for the same reason. Even-odd winding is the whole of the difference, and dropping
/// it leaves a pier that still renders, just as a plain capsule.
@MainActor @Test func thePortsArePunchedThroughThePier() {
    let rep = rendered()
    for port in [48, 90, 132] {
        #expect(ink(rep, port, 66) < 0.05, "port at \(port) is filled in")
    }
    // The pier itself: between two ports, and inside the left end past the first one.
    for solid in [20, 69, 111] {
        #expect(ink(rep, solid, 66) > 0.95, "pier is missing at \(solid)")
    }
}

/// Pier above, water below, clear sky between them. This is the design: a bar on its own reads as a
/// stray minus sign, and the water is what makes it Eskele's harbour rather than anyone's capsule.
@MainActor @Test func theWaterLineSitsClearBelowThePier() {
    let rep = rendered()
    #expect(ink(rep, 90, 20) < 0.05, "something is drawn above the pier")
    #expect(ink(rep, 90, 105) < 0.05, "the pier and the water have run together")
    // Where the wave crosses its own baseline, which is the one point on it the geometry pins down.
    #expect(ink(rep, 90, 128) > 0.95, "the water line is missing")
}
