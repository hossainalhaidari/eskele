import AppKit
import Testing
@testable import Eskele

private let screen = NSRect(x: 0, y: 0, width: 1470, height: 908)
private let label = NSRect(x: 0, y: 0, width: 200, height: 20)

// MARK: - Placement

@MainActor
@Test func theLabelSitsAboveABottomBarAndCentredOnTheCell() {
    let cell = NSRect(x: 600, y: 0, width: 140, height: 48)
    let placed = HoverTooltip.place(label, beside: cell, edge: .bottom, within: screen)
    #expect(placed.midX == cell.midX)
    #expect(placed.minY > cell.maxY)
}

@MainActor
@Test func theLabelSitsBesideASideBar() {
    let cell = NSRect(x: 0, y: 400, width: 48, height: 48)
    let left = HoverTooltip.place(label, beside: cell, edge: .left, within: screen)
    #expect(left.minX > cell.maxX)
    #expect(left.midY == cell.midY)

    let rightCell = NSRect(x: 1422, y: 400, width: 48, height: 48)
    let right = HoverTooltip.place(label, beside: rightCell, edge: .right, within: screen)
    #expect(right.maxX < rightCell.minX)
}

/// A cell at the end of a full-width bar would otherwise push the label off the display — which is
/// exactly where the longest window titles live.
@MainActor
@Test func theLabelIsKeptOnTheDisplay() {
    let atTheEnd = NSRect(x: 1430, y: 0, width: 40, height: 48)
    let placed = HoverTooltip.place(label, beside: atTheEnd, edge: .bottom, within: screen)
    #expect(placed.maxX <= screen.maxX)
    #expect(placed.minX >= screen.minX)

    let atTheStart = NSRect(x: 0, y: 0, width: 40, height: 48)
    #expect(HoverTooltip.place(label, beside: atTheStart, edge: .bottom, within: screen).minX >= screen.minX)
}

@MainActor
@Test func aLabelWiderThanTheDisplayStillStartsOnIt() {
    let huge = NSRect(x: 0, y: 0, width: 3000, height: 20)
    let placed = HoverTooltip.place(huge, beside: NSRect(x: 700, y: 0, width: 40, height: 48),
                                    edge: .bottom, within: screen)
    #expect(placed.minX == screen.minX)
}

// MARK: - Sizing

/// The regression: the label was framed from `intrinsicContentSize`, which is the width of the
/// glyphs alone. `NSTextFieldCell` insets the text it draws by 2pt on each side, so the frame was
/// 4pt short — and truncation does not cost 4pt, it costs an ellipsis and the characters it eats.
/// Asserting against the raw glyph width keeps this honest: the old code sized to exactly that.
@MainActor
@Test func theLabelIsWiderThanTheGlyphsItDraws() {
    let label = HoverTooltip.makeLabel()
    let font = try! #require(label.font)

    for text in ["Terminal", "Xcode", "Safari", "Notes", "System Settings"] {
        let glyphs = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let size = HoverTooltip.contentSize(of: label, showing: text, maximumWidth: 600)
        #expect(size.width > glyphs, "\(text) has no room for the cell's own text inset")
    }
}

/// A window title can be arbitrarily long; the tooltip may not follow it across the display.
@MainActor
@Test func aLongTitleIsClampedToTheOfferedWidth() {
    let label = HoverTooltip.makeLabel()
    let long = String(repeating: "a very long window title ", count: 20)
    #expect(HoverTooltip.contentSize(of: label, showing: long, maximumWidth: 300).width == 300)
}

/// One label serves every hover, so a short name after a long one must not be measured inside the
/// long one's frame.
@MainActor
@Test func measuringIsNotAffectedByThePreviousHover() {
    let label = HoverTooltip.makeLabel()
    let alone = HoverTooltip.contentSize(of: label, showing: "Terminal", maximumWidth: 600)

    _ = HoverTooltip.contentSize(of: label, showing: String(repeating: "wide ", count: 40), maximumWidth: 600)
    let afterLong = HoverTooltip.contentSize(of: label, showing: "Terminal", maximumWidth: 600)

    _ = HoverTooltip.contentSize(of: label, showing: "Hi", maximumWidth: 600)
    let afterShort = HoverTooltip.contentSize(of: label, showing: "Terminal", maximumWidth: 600)

    #expect(afterLong == alone)
    #expect(afterShort == alone)
}

// MARK: - What it says

private let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
private let ref = AppRef(bundleID: "test.safari", url: url, name: "Safari")

/// The ask, exactly: the page you are looking at, not the app's name a second time.
@Test func aRunningAppShowsThePageItIsOn() {
    var item = DockItem(kind: .app(ref), isPinned: true, isRunning: true)
    item.windowTitle = "Apple — Newsroom"
    #expect(item.hoverTitle == "Apple — Newsroom")
}

@Test func anAppThatIsNotRunningShowsItsName() {
    let item = DockItem(kind: .app(ref), isPinned: true, isRunning: false)
    #expect(item.hoverTitle == "Safari")
}

/// An app can be running with nothing open, and a window can be untitled. Neither may produce a
/// blank label, which would show as an empty box.
@Test func anEmptyTitleFallsBackToTheAppName() {
    var running = DockItem(kind: .app(ref), isPinned: true, isRunning: true)
    running.windowTitle = ""
    #expect(running.hoverTitle == "Safari")

    let window = WindowRef(pid: 1, title: "", isMinimized: false)
    #expect(DockItem(kind: .window(ref, window)).hoverTitle == "Safari")
}

@Test func aWindowButtonShowsItsOwnTitle() {
    let window = WindowRef(pid: 1, title: "Two — draft.md", isMinimized: false)
    #expect(DockItem(kind: .window(ref, window)).hoverTitle == "Two — draft.md")
}

@Test func aSeparatorHasNothingToSay() {
    #expect(DockItem(kind: .separator("x")).hoverTitle.isEmpty)
}

// MARK: - Preview layout

private func image(_ width: CGFloat, _ height: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: width, height: height))
}

/// Without a preview the panel must be exactly what it was before previews existed.
@MainActor
@Test func noPreviewLeavesTheLabelAlone() {
    let text = NSSize(width: 120, height: 16)
    let layout = HoverTooltip.layout(textSize: text, previewSize: .zero)
    #expect(layout.preview == .zero)
    #expect(layout.frame.width == text.width + 18)
    #expect(layout.frame.height == text.height + 10)
    #expect(layout.label.width == text.width)
}

/// A wide thumbnail sets the panel's width and the title centres under it.
@MainActor
@Test func aPreviewWiderThanItsTitleSetsTheWidth() {
    let text = NSSize(width: 60, height: 16)
    let preview = NSSize(width: 280, height: 175)
    let layout = HoverTooltip.layout(textSize: text, previewSize: preview)

    #expect(layout.frame.width == preview.width + 18)
    #expect(layout.frame.height == preview.height + text.height + HoverTooltip.previewGap + 10)
    #expect(layout.preview.width == preview.width)
    #expect(abs(layout.label.midX - layout.frame.midX) <= 1)
    // The panel is not flipped, so the title sits below the picture.
    #expect(layout.label.maxY <= layout.preview.minY)
}

/// The case that truncates a title if the arithmetic is wrong: a long window name over a narrow
/// window. The panel has to grow to the title, not to the thumbnail.
@MainActor
@Test func aTitleWiderThanItsPreviewIsNotSqueezed() {
    let text = NSSize(width: 260, height: 16)
    let preview = NSSize(width: 90, height: 160)
    let layout = HoverTooltip.layout(textSize: text, previewSize: preview)

    #expect(layout.frame.width == text.width + 18)
    #expect(layout.label.width == text.width)
    #expect(layout.preview.width == preview.width)
    #expect(abs(layout.preview.midX - layout.frame.midX) <= 1)
}

/// Everything has to fit inside the panel, in every combination.
@MainActor
@Test func theContentAlwaysFitsInsideThePanel() {
    for text in [NSSize(width: 30, height: 14), NSSize(width: 400, height: 32)] {
        for preview in [NSSize.zero, NSSize(width: 280, height: 60), NSSize(width: 40, height: 190)] {
            let layout = HoverTooltip.layout(textSize: text, previewSize: preview)
            #expect(layout.frame.contains(layout.label))
            if preview != .zero { #expect(layout.frame.contains(layout.preview)) }
        }
    }
}

// MARK: - Thumbnail scaling

@MainActor
@Test func aLargeWindowIsScaledDownKeepingItsShape() {
    let size = HoverTooltip.fitted(image(1600, 1000))
    #expect(size.width <= HoverTooltip.maximumPreview.width)
    #expect(size.height <= HoverTooltip.maximumPreview.height)
    // 1.6:1 in, 1.6:1 out.
    #expect(abs(size.width / size.height - 1.6) < 0.02)
}

/// A tall window is bounded by the height, not the width — the bug that makes a portrait window
/// taller than the screen it is describing.
@MainActor
@Test func aTallWindowIsBoundedByHeight() {
    let size = HoverTooltip.fitted(image(400, 1200))
    #expect(size.height == HoverTooltip.maximumPreview.height)
    #expect(size.width < HoverTooltip.maximumPreview.width)
}

/// Never scaled up: a small palette stays small rather than becoming a blurry slab.
@MainActor
@Test func asmallWindowIsNotEnlarged() {
    #expect(HoverTooltip.fitted(image(120, 80)) == NSSize(width: 120, height: 80))
}

@MainActor
@Test func anEmptyImageHasNoPreviewSize() {
    #expect(HoverTooltip.fitted(image(0, 0)) == .zero)
}
