import AppKit
import Testing
@testable import Eskele

private func buttons(of row: DesignMenuRow) -> [NSButton] {
    row.subviews.compactMap { $0 as? NSButton }
}

/// Each tile has to report the design it is drawn as. The buttons carry their design as a tag into
/// a shared action, which is exactly the kind of wiring that survives a refactor by pointing at the
/// wrong tile.
@MainActor @Test func everyTileReportsItsOwnDesign() {
    var picked: [DesignPreset] = []
    var settings = Settings()
    settings.edge = .right
    settings.captureCustomDesign()          // so all four tiles are pickable

    let row = DesignMenuRow(settings: settings) { picked.append($0) }
    let tiles = buttons(of: row)
    #expect(tiles.count == DesignPreset.allCases.count)

    for button in tiles { button.performClick(nil) }
    #expect(picked == DesignPreset.allCases)
}

/// The tile for a Custom design nobody has made is shown, so the row keeps its shape, but it cannot
/// be clicked into applying nothing.
@MainActor @Test func theUnmadeCustomTileCannotBePicked() {
    var picked: [DesignPreset] = []
    let row = DesignMenuRow(settings: Settings()) { picked.append($0) }
    let tiles = buttons(of: row)

    #expect(tiles.map(\.isEnabled) == [true, true, true, false])
    tiles[3].performClick(nil)
    #expect(picked.isEmpty)
}

/// The row is laid out from the tiles it drew. A row shorter than its tiles would clip the names
/// off the bottom, which is how the menu ends up showing four unlabelled pictures.
@MainActor @Test func theRowIsTallEnoughForTheTilesItDrew() throws {
    let row = DesignMenuRow(settings: Settings()) { _ in }
    let artwork = row.subviews.compactMap { $0 as? NSImageView }

    #expect(artwork.count == DesignPreset.allCases.count)
    for view in artwork {
        // Drawn at its own size rather than scaled to fit, so the frame has to be the image's.
        #expect(try #require(view.image).size == view.frame.size)
        #expect(view.frame.maxY <= row.frame.height)
        #expect(view.frame.maxX <= row.frame.width)
    }
}
