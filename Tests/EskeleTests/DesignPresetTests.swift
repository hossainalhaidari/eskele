import Foundation
import Testing
@testable import Eskele

/// Every change the app makes goes through `AppDelegate.apply`, which captures the custom design
/// before saving. The tests drive settings the same way, or they would be testing a path the app
/// never takes.
private func change(_ settings: Settings, _ edit: (inout Settings) -> Void) -> Settings {
    var result = settings
    edit(&result)
    result.captureCustomDesign()
    return result
}

private func pick(_ preset: DesignPreset, from settings: Settings) -> Settings {
    change(settings) { $0 = preset.applied(to: $0) }
}

/// A fresh install must land on a design rather than between them, or the picker opens with nothing
/// selected and the user cannot tell what they have.
@Test func freshSettingsAreTheDockDesign() {
    #expect(DesignPreset.matching(Settings()) == .dock)
}

/// Custom is the one you arrive at rather than start from, so it goes at the end of the row.
@Test func customIsTheLastDesignOffered() {
    #expect(DesignPreset.allCases.last == .custom)
    #expect(DesignPreset.shippedCases == [.dock, .classic, .unity])
}

@Test func everyShippedDesignMatchesItselfOnceApplied() {
    for preset in DesignPreset.shippedCases {
        #expect(DesignPreset.matching(preset.applied(to: Settings())) == preset, "\(preset)")
    }
}

/// `matching` returns the first hit, so two designs that agreed on every field they own would make
/// one of them unreachable.
@Test func noTwoShippedDesignsDescribeTheSameBar() {
    let previews = DesignPreset.shippedCases.map { $0.applied(to: Settings()) }
    for (index, settings) in previews.enumerated() {
        let others = DesignPreset.shippedCases.filter { $0 != DesignPreset.shippedCases[index] }
        #expect(!others.contains { $0.matches(settings) })
    }
}

/// The point of the picker is a starting point, not a reset: a design owns five layout settings plus
/// the Trash and Apps Menu, and must leave the rest of the user's tuning alone.
@Test func applyingADesignKeepsUnrelatedSettings() {
    var tuned = Settings()
    tuned.iconPadding = 7
    tuned.itemSpacing = 11
    tuned.cornerRadius = 2
    tuned.material = .hudWindow
    tuned.autohide = true
    tuned.hideDelay = 1.5
    tuned.showBadges = false
    tuned.expandedItemWidth = 200

    let applied = DesignPreset.unity.applied(to: tuned)
    #expect(applied.iconPadding == 7)
    #expect(applied.itemSpacing == 11)
    #expect(applied.cornerRadius == 2)
    #expect(applied.material == .hudWindow)
    #expect(applied.autohide)
    #expect(applied.hideDelay == 1.5)
    #expect(applied.showBadges == false)
    #expect(applied.expandedItemWidth == 200)
}

@Test func everyShippedDesignTurnsOnTheTrashAndTheAppsMenu() {
    var stripped = Settings()
    stripped.showTrash = false
    stripped.showAppsMenu = false
    stripped.appsMenuSource = .recentApps

    for preset in DesignPreset.shippedCases {
        let applied = preset.applied(to: stripped)
        #expect(applied.showTrash, "\(preset)")
        #expect(applied.showAppsMenu, "\(preset)")
        #expect(applied.appsMenuSource == .allApps, "\(preset)")
    }
}

/// The three shapes the picker promises.
@Test func eachDesignHasTheLayoutItAdvertises() throws {
    let dock = try #require(DesignPreset.dock.preview(in: Settings()))
    #expect(dock.edge == .bottom)
    #expect(dock.spanMode == .hugContents)
    #expect(dock.itemStyle == .compact)
    #expect(dock.itemAlignment == .center)
    #expect(dock.barSize == .big)

    let classic = try #require(DesignPreset.classic.preview(in: Settings()))
    #expect(classic.edge == .bottom)
    #expect(classic.spanMode == .fullSpan)
    #expect(classic.itemStyle == .expanded)
    #expect(classic.itemAlignment == .leading)
    #expect(classic.barSize == .small)
    #expect(classic.drawsLabels)          // a bottom bar has room for them

    let unity = try #require(DesignPreset.unity.preview(in: Settings()))
    #expect(unity.edge == .left)
    #expect(unity.spanMode == .fullSpan)
    #expect(unity.itemStyle == .compact)
    #expect(unity.itemAlignment == .leading)
    #expect(unity.barSize == .big)
}

/// Tuning a setting a design owns has to move the selection to Custom; tuning anything else must
/// leave the design it was tuning selected.
@Test func selectionFollowsOnlyTheSettingsADesignOwns() {
    var settings = pick(.classic, from: Settings())
    #expect(DesignPreset.matching(settings) == .classic)

    settings = change(settings) { $0.iconPadding += 3 }
    #expect(DesignPreset.matching(settings) == .classic)

    settings = change(settings) { $0.itemAlignment = .trailing }
    #expect(DesignPreset.matching(settings) == .custom)
}

// MARK: - The custom design

/// Nothing to go back to until the user has made something, so the tile has nothing to offer.
@Test func customIsUnavailableUntilItIsMade() {
    let fresh = Settings()
    #expect(fresh.customDesign == nil)
    #expect(!DesignPreset.custom.isAvailable(in: fresh))
    #expect(DesignPreset.custom.preview(in: fresh) == nil)
    // And picking it anyway changes nothing.
    #expect(DesignPreset.custom.applied(to: fresh) == fresh)
}

@Test func tuningADesignedBarMakesItTheCustomOne() throws {
    let tuned = change(pick(.dock, from: Settings())) { $0.edge = .right }

    #expect(DesignPreset.matching(tuned) == .custom)
    #expect(DesignPreset.custom.isAvailable(in: tuned))
    #expect(try #require(tuned.customDesign).edge == .right)
}

/// The headline promise: make a design of your own, try one of the shipped three, and one click
/// brings yours back exactly as you left it.
@Test func theCustomDesignSurvivesATripThroughAShippedOne() {
    var settings = pick(.dock, from: Settings())
    settings = change(settings) {
        $0.edge = .right
        $0.spanMode = .fullSpan
        $0.itemAlignment = .trailing
        $0.barSize = .small
        $0.showTrash = false
    }
    let mine = settings
    #expect(DesignPreset.matching(mine) == .custom)

    let detour = pick(.unity, from: mine)
    #expect(DesignPreset.matching(detour) == .unity)
    #expect(detour.customDesign == mine.customDesign)     // kept, not overwritten

    let back = pick(.custom, from: detour)
    #expect(DesignPreset.matching(back) == .custom)
    #expect(back.edge == .right)
    #expect(back.spanMode == .fullSpan)
    #expect(back.itemAlignment == .trailing)
    #expect(back.barSize == .small)
    #expect(back.showTrash == false)
    #expect(back == mine)
}

/// Coming back to a custom design restores its shape, not the whole of the settings it was made in:
/// a padding tuned during the detour is tuning, not design, and stays where it was put.
@Test func comingBackToACustomDesignOnlyRestoresTheDesign() {
    var settings = change(Settings()) { $0.edge = .right }
    settings = pick(.classic, from: settings)
    settings = change(settings) { $0.iconPadding = 12 }

    let back = pick(.custom, from: settings)
    #expect(back.edge == .right)
    #expect(back.iconPadding == 12)
}

/// The escape hatch the user keeps: a shipped design, then one manual change, replaces whatever was
/// under Custom before. Otherwise Custom would be a design you could never get rid of.
@Test func tuningAfterAShippedDesignReplacesTheCustomOne() throws {
    var settings = change(Settings()) { $0.edge = .right }
    let first = try #require(settings.customDesign)

    settings = pick(.classic, from: settings)
    #expect(settings.customDesign == first)               // untouched by the trip

    settings = change(settings) { $0.barSize = .big }
    let second = try #require(settings.customDesign)
    #expect(second != first)
    #expect(second.edge == .bottom)                       // Classic's edge, not the old custom one
    #expect(second.barSize == .big)
}

/// Capture runs on every change, so it has to be quiet when there is nothing to record.
@Test func captureLeavesAShippedDesignAlone() {
    let dock = pick(.dock, from: Settings())
    #expect(dock.customDesign == nil)

    let tuned = change(dock) { $0.itemSpacing = 9 }        // not a design setting
    #expect(tuned.customDesign == nil)
    #expect(DesignPreset.matching(tuned) == .dock)
}

/// A settings file written before the Custom design existed can still describe a custom bar. It has
/// to show up under the Custom tile rather than as nothing at all.
@Test func anUnrecordedCustomBarIsStillTheCustomDesign() throws {
    var legacy = Settings()
    legacy.edge = .right
    legacy.customDesign = nil

    #expect(DesignPreset.matching(legacy) == .custom)
    #expect(DesignPreset.custom.isAvailable(in: legacy))
    #expect(try #require(DesignPreset.custom.preview(in: legacy)).edge == .right)
}

@Test func theCustomDesignSurvivesASaveAndReload() throws {
    let settings = change(Settings()) {
        $0.edge = .right
        $0.barSize = .small
    }
    let data = try JSONEncoder().encode(settings)
    let reloaded = try JSONDecoder().decode(Settings.self, from: data)

    #expect(reloaded == settings)
    #expect(try #require(reloaded.customDesign).edge == .right)
    #expect(DesignPreset.matching(reloaded) == .custom)
}

/// One typo in a hand-edited custom design must cost that field, the way it does everywhere else in
/// the file.
@Test func aMalformedFieldInTheCustomDesignCostsOnlyThatField() throws {
    let settings = try #require(try? JSONDecoder().decode(Settings.self, from: Data("""
        {"customDesign": {"edge": "diagonal", "spanMode": "fullSpan", "itemStyle": "compact",
         "itemAlignment": "leading", "barSize": "small", "showTrash": true,
         "showAppsMenu": true, "appsMenuSource": "allApps"}}
        """.utf8)))

    let design = try #require(settings.customDesign)
    #expect(design.edge == Settings().edge)               // fell back
    #expect(design.spanMode == .fullSpan)                 // kept
    #expect(design.barSize == .small)                     // kept
}
