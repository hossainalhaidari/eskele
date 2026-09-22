import Foundation
import Testing
@testable import Eskele

private func decodeSettings(_ json: String) -> Settings? {
    try? JSONDecoder().decode(Settings.self, from: Data(json.utf8))
}

@Test func defaultsSurviveAnEmptyObject() throws {
    let settings = try #require(decodeSettings("{}"))
    #expect(settings == Settings())
}

/// The README tells people to hand-edit `settings.json`, so one typo must cost one setting — not
/// the whole file. Plain `decodeIfPresent` throws on a present-but-invalid value.
@Test func oneMalformedValueDoesNotDiscardTheRest() throws {
    let settings = try #require(decodeSettings("""
        {"edge": "diagonal", "spanMode": "fullSpan", "showTrash": false, "itemAlignment": ""}
        """))
    #expect(settings.edge == Settings().edge)              // fell back
    #expect(settings.itemAlignment == Settings().itemAlignment)
    #expect(settings.spanMode == .fullSpan)                // kept
    #expect(settings.showTrash == false)                   // kept
}

@Test func wrongTypeFallsBackPerKey() throws {
    let settings = try #require(decodeSettings("""
        {"thicknessNudge": "big", "cornerRadius": 4}
        """))
    #expect(settings.thicknessNudge == Settings().thicknessNudge)
    #expect(settings.cornerRadius == 4)
}

/// Ten global combinations are far more likely to collide with something the user already has
/// bound than one is, so they have to be asked for rather than acquired on upgrade — which means a
/// settings file written before they existed must decode with them off.
@Test func slotHotKeysAreOffUntilAskedFor() throws {
    #expect(Settings().slotHotKeysEnabled == false)
    let existing = try #require(decodeSettings(#"{"edge": "left", "revealHotKeyEnabled": true}"#))
    #expect(existing.slotHotKeysEnabled == false)
    let asked = try #require(decodeSettings(#"{"slotHotKeysEnabled": true}"#))
    #expect(asked.slotHotKeysEnabled)
}

/// A settings file written before rows existed must decode as the one-row bar it was.
@Test func rowsDefaultToOneAndClampWhateverTheFileSays() throws {
    #expect(try #require(decodeSettings(#"{"edge": "left"}"#)).rowCount == 1)
    #expect(try #require(decodeSettings(#"{"barRows": 3}"#)).rowCount == 3)
    #expect(try #require(decodeSettings(#"{"barRows": 40}"#)).rowCount == BarLayout.maximumRows)
    #expect(try #require(decodeSettings(#"{"barRows": 0}"#)).rowCount == 1)
    #expect(try #require(decodeSettings(#"{"barRows": "two"}"#)).rowCount == 1)
}

/// The third screen mode has to arrive switched off for everyone who already had a settings file.
@Test func screenModeDefaultsToMirroring() throws {
    #expect(try #require(decodeSettings("{}")).screenMode == .allScreens)
    #expect(try #require(decodeSettings(#"{"screenMode": "perDisplay"}"#)).screenMode == .perDisplay)
    #expect(try #require(decodeSettings(#"{"screenMode": "eachOne"}"#)).screenMode == .allScreens)
}

@Test func unknownKeysAreIgnored() throws {
    let settings = try #require(decodeSettings(#"{"edge": "left", "somethingFromV2": 7}"#))
    #expect(settings.edge == .left)
}

@Test func settingsRoundTrip() throws {
    var original = Settings()
    original.edge = .right
    original.spanMode = .fullSpan
    original.itemAlignment = .trailing
    original.reserveScreenSpace = true
    original.slotHotKeysEnabled = true
    original.barRows = 3
    original.screenMode = .perDisplay
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(Settings.self, from: data) == original)
}

/// A full-span bar should meet the screen corners squarely, like the menu bar.
@Test func fullSpanSquaresOffTheCorners() {
    var settings = Settings()
    settings.cornerRadius = 9
    settings.spanMode = .hugContents
    #expect(settings.effectiveCornerRadius == 9)
    settings.spanMode = .fullSpan
    #expect(settings.effectiveCornerRadius == 0)
}

// MARK: - Layout

@Test func layoutDropsOnlyTheUnreadableEntries() throws {
    let json = """
        {"version": 1, "items": [
            {"kind": "app", "bundleID": "com.apple.Safari", "name": "Safari"},
            {"kind": "not-a-kind"},
            {"kind": "separator", "token": "abc"},
            17,
            {"kind": "folder", "path": "/Users", "name": "Users"}
        ]}
        """
    let layout = try JSONDecoder().decode(Layout.self, from: Data(json.utf8))
    #expect(layout.items.count == 3)
    #expect(layout.items.map(\.kind) == [.app, .separator, .folder])
}

@Test func layoutSurvivesAMissingItemsKey() throws {
    let layout = try JSONDecoder().decode(Layout.self, from: Data(#"{"version": 1}"#.utf8))
    #expect(layout.items.isEmpty)
    #expect(layout.version == 1)
}

// MARK: - Span and alignment

/// "Leading" has to mean the top on a vertical bar, or the menu is lying to the user.
@Test func alignmentLabelsFollowTheBarAxis() {
    #expect(ItemAlignment.leading.title(for: .bottom) == "Left")
    #expect(ItemAlignment.trailing.title(for: .bottom) == "Right")
    #expect(ItemAlignment.leading.title(for: .left) == "Top")
    #expect(ItemAlignment.trailing.title(for: .right) == "Bottom")
    #expect(ItemAlignment.center.title(for: .left) == "Centre")
}

@Test func edgesMapToDockOrientations() {
    #expect(BarEdge.left.dockOrientation == "left")
    #expect(BarEdge.bottom.dockOrientation == "bottom")
    #expect(BarEdge.right.dockOrientation == "right")
}

@Test func verticalEdgesAreVertical() {
    #expect(BarEdge.left.isVertical)
    #expect(BarEdge.right.isVertical)
    #expect(!BarEdge.bottom.isVertical)
}

@Test func autohideSettingsDecode() throws {
    let settings = try #require(decodeSettings("""
        {"autohide": true, "revealDelay": 0.3, "hideDelay": 1.0, "revealHotKeyEnabled": true}
        """))
    #expect(settings.autohide)
    #expect(settings.revealDelay == 0.3)
    #expect(settings.hideDelay == 1.0)
    #expect(settings.revealHotKeyEnabled)
}

// MARK: - Full screen

@Test func fullScreenBehaviourDecodesAndDefaults() throws {
    #expect(try #require(decodeSettings("{}")).fullScreenBehavior == .show)
    #expect(try #require(decodeSettings(#"{"fullScreenBehavior": "hide"}"#)).fullScreenBehavior == .hide)
    #expect(try #require(decodeSettings(#"{"fullScreenBehavior": "revealOnHover"}"#))
        .fullScreenBehavior == .revealOnHover)
    // Unknown value must not take the rest of the file down with it.
    let broken = try #require(decodeSettings(#"{"fullScreenBehavior": "shrink", "showTrash": false}"#))
    #expect(broken.fullScreenBehavior == .show)
    #expect(broken.showTrash == false)
}

// MARK: - Menu bar icon

@Test func theMenuBarIconIsOnByDefaultAndDecodesOff() throws {
    #expect(try #require(decodeSettings("{}")).showStatusItem)
    #expect(try #require(decodeSettings(#"{"showStatusItem": false}"#)).showStatusItem == false)
    // A file written before this setting existed must keep its icon.
    #expect(try #require(decodeSettings(#"{"showAppsMenu": false}"#)).showStatusItem)
}

/// The status menu and the launcher's settings button are the only two ways into the settings
/// window, so a settings file that has neither is one the app has to repair on launch.
@Test func aSettingsRouteNeedsTheIconOrTheAppsMenu() {
    var settings = Settings()
    #expect(settings.hasSettingsRoute)

    settings.showStatusItem = false
    #expect(settings.hasSettingsRoute)   // the Apps Menu carries the gear

    settings.showAppsMenu = false
    #expect(!settings.hasSettingsRoute)

    settings.showStatusItem = true
    #expect(settings.hasSettingsRoute)
}
