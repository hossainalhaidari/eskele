import Foundation
import Testing
@testable import Eskele

private func read(_ json: String) throws(SettingsFile.ReadError) -> Settings {
    try SettingsFile.read(Data(json.utf8))
}

private func refusal(_ json: String) -> SettingsFile.ReadError? {
    do {
        _ = try read(json)
        return nil
    } catch {
        return error
    }
}

// MARK: - Export and import

@Test func anExportImportsAsTheSameSettings() throws {
    var original = Settings()
    original.edge = .left
    original.barRows = 2
    original.material = .custom
    original.tint = BarTint(red: 0.5, green: 0.25, blue: 0.75, opacity: 0.6)
    original.appsMenuHotKey = .rightCommand
    original.captureCustomDesign()
    #expect(try SettingsFile.read(Persistence.encode(original)) == original)
}

/// What makes an export and a copy of `settings.json` interchangeable.
@MainActor
@Test func anExportIsTheSameBytesAsSettingsJSON() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SettingsFileTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var settings = Settings()
    settings.spanMode = .fullSpan
    settings.showClock = true
    Persistence(directory: directory).save(settings)

    let written = try Data(contentsOf: directory.appendingPathComponent("settings.json"))
    #expect(written == (try Persistence.encode(settings)))
}

/// The leniency launch applies: a file from an older version, or one written by hand, is missing
/// keys and may have a bad value, and that costs only those keys.
@Test func aPartialFileImportsWithDefaultsForTheRest() throws {
    let settings = try read(#"{"edge": "right", "showTrash": false, "barRows": "two"}"#)
    var expected = Settings()
    expected.edge = .right
    expected.showTrash = false
    #expect(settings == expected)
}

/// A file exported by a later version carries settings this one has never heard of.
@Test func settingsFromALaterVersionDoNotStopAnImport() throws {
    let settings = try read(#"{"edge": "left", "spanMode": "fullSpan", "somethingFromV2": 7}"#)
    #expect(settings.edge == .left)
    #expect(settings.spanMode == .fullSpan)
}

// MARK: - Refusing what is not settings

/// Without the check, each of these would import as a flawless set of defaults — a reset reported
/// as a successful import.
@Test func ourOtherFilesAreRefused() {
    let layout = #"{"version": 1, "items": [{"bundleID": "com.apple.Safari", "name": "Safari"}]}"#
    let badges = #"{"sources": [], "_readme": ["…"], "_examples": []}"#
    let recents = #"["com.apple.Safari", "com.apple.mail"]"#
    // Shares `autohide` with settings.json, which is why the rule is a majority, not one key.
    let dockBackup = """
        {"autohide": false, "capturedAt": 811372376.6, "cleanlyRestored": false,
         "noBouncing": false, "orientation": "left", "schema": 2, "tilesize": 31}
        """
    #expect(refusal(layout) == .notSettings)
    #expect(refusal(badges) == .notSettings)
    #expect(refusal(dockBackup) == .notSettings)
    #expect(refusal(recents) == .unreadable)
}

@Test func anythingButAJSONObjectIsRefused() {
    #expect(refusal("{}") == .notSettings)
    #expect(refusal("") == .unreadable)
    #expect(refusal("edge: left") == .unreadable)
    #expect(refusal(#""edge""#) == .unreadable)
    #expect(refusal(#"{"edge": "left""#) == .unreadable)
}

// MARK: - What a replacement may not touch

/// The consent given on first launch belongs to this Mac. A reset must not bring the Dock back
/// mid-session, and a first launch must not be asked for again.
@Test func aResetKeepsTheSystemDockAndFirstRun() {
    var current = Settings()
    current.hasCompletedOnboarding = true
    current.suppressSystemDock = true
    current.reserveScreenSpace = true
    current.edge = .right
    current.showClock = true

    let reset = current.adopting(Settings())
    #expect(reset.hasCompletedOnboarding)
    #expect(reset.suppressSystemDock)
    #expect(reset.reserveScreenSpace)
    #expect(reset.edge == Settings().edge)
    #expect(reset.showClock == Settings().showClock)
}

/// The other direction: a file cannot hide the Dock on a Mac whose owner said no to that.
@Test func anImportCannotHideTheSystemDock() throws {
    var current = Settings()
    current.hasCompletedOnboarding = true
    let imported = try read(#"{"suppressSystemDock": true, "reserveScreenSpace": true, "edge": "left"}"#)

    let result = current.adopting(imported)
    #expect(!result.suppressSystemDock)
    #expect(!result.reserveScreenSpace)
    #expect(result.hasCompletedOnboarding)
    #expect(result.edge == .left)
}

/// Resetting a tuned bar lands on the Dock design with the tuned one still under Custom, so the
/// layout half of a reset is one click from undone.
@Test func aResetLeavesTheCustomDesignToComeBackTo() {
    var tuned = Settings()
    tuned.edge = .left
    tuned.barSize = .small
    tuned.showTrash = false
    tuned.captureCustomDesign()

    let reset = tuned.adopting(Settings())
    #expect(DesignPreset.matching(reset) == .dock)
    #expect(reset.customDesign == DesignFields(tuned))
    #expect(DesignFields(DesignPreset.custom.applied(to: reset)) == DesignFields(tuned))
}

@Test func anImportedCustomDesignReplacesOurs() {
    var current = Settings()
    current.edge = .left
    current.captureCustomDesign()

    var incoming = Settings()
    incoming.edge = .right
    incoming.captureCustomDesign()

    #expect(current.adopting(incoming).customDesign == DesignFields(incoming))
    #expect(current.adopting(Settings()).customDesign == DesignFields(current))
}

/// A file with both routes to Settings turned off gets the menu-bar icon back, as it would at launch.
@Test func anImportCannotLockTheUserOutOfSettings() throws {
    let imported = try read(#"{"showStatusItem": false, "showAppsMenu": false}"#)
    let result = Settings().adopting(imported)
    #expect(result.hasSettingsRoute)
    #expect(result.showStatusItem)
    #expect(!result.showAppsMenu)
}
