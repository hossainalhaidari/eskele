import Foundation
import Testing
@testable import Eskele

@Test func badgeCommandOutputIsReadAsANumber() {
    #expect(BadgeService.firstNumber(in: "12\n") == 12)
    #expect(BadgeService.firstNumber(in: "  7  ") == 7)
    #expect(BadgeService.firstNumber(in: "12 unread") == 12)
    #expect(BadgeService.firstNumber(in: "unread: 12") == 12)
    #expect(BadgeService.firstNumber(in: "0") == 0)
}

@Test func outputWithoutANumberMeansNoBadge() {
    #expect(BadgeService.firstNumber(in: "") == nil)
    #expect(BadgeService.firstNumber(in: "\n\n") == nil)
    #expect(BadgeService.firstNumber(in: "execution error") == nil)
}

/// The first run of digits, so a chatty script that happens to print a version string first does
/// not silently badge the wrong number... which is exactly why the recipe should print one thing.
@Test func onlyTheFirstRunOfDigitsIsTaken() {
    #expect(BadgeService.firstNumber(in: "3 of 40") == 3)
}

@Test func badgeSourcesClampTheirInterval() {
    #expect(BadgeSource(bundleID: "x", command: "true", interval: 0, enabled: nil).period == 5)
    #expect(BadgeSource(bundleID: "x", command: "true", interval: 99_999, enabled: nil).period == 3600)
    #expect(BadgeSource(bundleID: "x", command: "true", interval: nil, enabled: nil).period == 30)
}

@Test func aSourceIsEnabledUnlessItSaysOtherwise() {
    #expect(BadgeSource(bundleID: "x", command: "true", interval: nil, enabled: nil).isEnabled)
    #expect(!BadgeSource(bundleID: "x", command: "true", interval: nil, enabled: false).isEnabled)
}

/// The file ships with worked examples under keys the model does not know. Decoding has to ignore
/// them rather than throw the user's real sources away.
@Test func unknownKeysInTheBadgeFileAreIgnored() throws {
    let json = """
        { "sources": [ { "bundleID": "com.apple.mail", "command": "echo 4" } ],
          "_readme": ["anything"], "_examples": [{ "bundleID": "x", "command": "y" }] }
        """
    let configuration = try JSONDecoder().decode(BadgeConfiguration.self, from: Data(json.utf8))
    #expect(configuration.sources.count == 1)
    #expect(configuration.sources[0].bundleID == "com.apple.mail")
}

/// The seeded file is the documentation for this feature, so it has to be valid JSON that decodes
/// to "no sources yet" rather than something the user has to repair before they can use it.
@MainActor
@Test func theSeededBadgeFileIsValidAndEmpty() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-badges-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let persistence = Persistence(directory: directory)
    persistence.seedBadgeConfigurationIfMissing()

    let data = try Data(contentsOf: persistence.badgesURL)
    let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(raw?["_examples"] != nil)
    #expect(persistence.loadBadgeConfiguration().sources.isEmpty)

    // The examples must themselves be usable sources — a broken recipe is worse than none.
    let examples = try #require(raw?["_examples"] as? [[String: Any]])
    let encoded = try JSONSerialization.data(withJSONObject: ["sources": examples])
    let decoded = try JSONDecoder().decode(BadgeConfiguration.self, from: encoded)
    #expect(decoded.sources.count == examples.count)
    #expect(decoded.sources.allSatisfy { !$0.command.isEmpty && !$0.bundleID.isEmpty })
}

/// An existing file is never overwritten: it holds the user's own commands.
@MainActor
@Test func seedingLeavesAnExistingBadgeFileAlone() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-badges-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let persistence = Persistence(directory: directory)
    let mine = #"{"sources":[{"bundleID":"com.apple.mail","command":"echo 3"}]}"#
    try mine.write(to: persistence.badgesURL, atomically: true, encoding: .utf8)

    persistence.seedBadgeConfigurationIfMissing()
    #expect(persistence.loadBadgeConfiguration().sources.map(\.command) == ["echo 3"])
}

// MARK: - The Dock's own badges

/// The Dock draws a string. Only the ones with a number in them have anything to draw.
@Test func aDockTilesLabelIsReadAsACount() {
    #expect(DockBadgeReader.count(fromStatusLabel: "3") == 3)
    #expect(DockBadgeReader.count(fromStatusLabel: "99+") == 99)
    #expect(DockBadgeReader.count(fromStatusLabel: "1,024") == 1)
}

/// Zero is the Dock saying "nothing", and a bare dot is a badge with no number in it. Neither is a
/// number to draw, and drawing a `0` would be worse than drawing nothing.
@Test func aLabelWithNoNumberInItIsNoBadge() {
    #expect(DockBadgeReader.count(fromStatusLabel: "0") == nil)
    #expect(DockBadgeReader.count(fromStatusLabel: "•") == nil)
    #expect(DockBadgeReader.count(fromStatusLabel: "") == nil)
}

/// The Dock supplies the default; nothing has to be configured for a real badge to appear.
@Test func dockBadgesAreDrawnWithoutAnyConfiguration() {
    let merged = BadgeService.merged(dock: ["com.apple.mail": 2], commands: [:])
    #expect(merged == ["com.apple.mail": 2])
}

/// A command is the explicit instruction, so it wins the cell it names — and leaves every other
/// cell to the Dock.
@Test func aCommandOverridesTheDockBadgeForItsOwnApp() {
    let merged = BadgeService.merged(
        dock: ["com.apple.mail": 2, "com.apple.MobileSMS": 7],
        commands: ["com.apple.mail": 40])
    #expect(merged == ["com.apple.mail": 40, "com.apple.MobileSMS": 7])
}

/// A recipe that has stopped answering — or that reports zero when the badge says otherwise —
/// leaves no entry behind, so the cell falls back to the number macOS is really drawing rather
/// than going blank.
@Test func aCommandThatYieldsNothingLeavesTheRealBadgeAlone() {
    let merged = BadgeService.merged(dock: ["com.apple.mail": 2], commands: [:])
    #expect(merged["com.apple.mail"] == 2)
}

/// A command for something the Dock cannot badge — the Trash, or an app with no tile — still puts
/// its number on the bar.
@Test func aCommandStillSuppliesBadgesTheDockHasNoneFor() {
    let merged = BadgeService.merged(dock: [:], commands: ["trash": 12])
    #expect(merged == ["trash": 12])
}
