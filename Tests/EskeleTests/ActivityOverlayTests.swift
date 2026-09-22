import AppKit
import Testing
@testable import Eskele

private let both: Set<BarOverlay> = [.slotNumbers, .activity]

/// Both overlays at their default chords, less any that are switched off.
private func match(_ flags: NSEvent.ModifierFlags, enabled: Set<BarOverlay> = both) -> BarOverlay? {
    var settings = Settings()
    settings.slotHotKeysEnabled = enabled.contains(.slotNumbers)
    settings.activityOverlayEnabled = enabled.contains(.activity)
    return BarOverlay.matching(flags, chords: BarOverlay.chords(for: settings))
}

// MARK: - Chords

@Test func eachChordSelectsItsOwnOverlay() {
    #expect(match([.control, .option]) == .slotNumbers)
    #expect(match([.shift, .option]) == .activity)
}

@Test func noModifiersShowsNothing() {
    #expect(match([]) == nil)
}

/// An overlay that is switched off must not answer to its chord, and must not let the *other*
/// overlay answer for it either.
@Test func aDisabledOverlayIgnoresItsChord() {
    #expect(match([.shift, .option], enabled: [.slotNumbers]) == nil)
    #expect(match([.control, .option], enabled: [.activity]) == nil)
    #expect(match([.control, .option], enabled: []) == nil)
}

/// Matched whole. A near miss must show nothing rather than the closest thing — ⌃⌥⌘ is a chord
/// somebody else owns, and answering it would claim a gesture that is not ours.
@Test func aSupersetIsNotTheChord() {
    #expect(match([.control, .option, .command]) == nil)
    #expect(match([.shift, .option, .command]) == nil)
    #expect(match([.control, .option, .shift]) == nil)
    #expect(match([.option]) == nil)
    #expect(match([.shift]) == nil)
}

/// Caps Lock, Fn and the numeric-pad bit ride along on ordinary events; none is part of a chord.
@Test func irrelevantFlagsDoNotBreakAChord() {
    #expect(match([.control, .option, .capsLock]) == .slotNumbers)
    #expect(match([.shift, .option, .function]) == .activity)
}

/// The activity chord doubles as no click gesture, so holding it and clicking cannot quit anything.
/// This is the guard on that: if ⇧⌥ ever gains a click meaning, this test says so.
@Test func theActivityChordIsNotAClickGesture() {
    let item = DockItem(
        kind: .app(AppRef(
            bundleID: "x", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            name: "Finder")),
        isRunning: true)
    #expect(ClickAction.resolve(modifiers: BarOverlay.activityChord, for: item) == nil)
}

// MARK: - Figures

/// Below ten percent the first decimal is the whole story; above it, it is noise that changes every
/// sample and makes the column impossible to read.
@Test func processorUseIsRoundedWhereTheDetailStopsHelping() {
    #expect(ActivitySample.cpuText(0) == "0.0%")
    #expect(ActivitySample.cpuText(3.14) == "3.1%")
    #expect(ActivitySample.cpuText(9.9) == "9.9%")
    #expect(ActivitySample.cpuText(12.4) == "12%")
    #expect(ActivitySample.cpuText(312.7) == "313%")
}

/// Nothing to subtract yet — the first sample of a chord, or of an app that has just appeared.
@Test func unknownProcessorUseSaysSoRatherThanZero() {
    #expect(ActivitySample.cpuText(nil) == "—")
}

/// A tiny negative can fall out of two samples taken across a process's own accounting; it must not
/// be shown as one.
@Test func negativeProcessorUseIsClampedToZero() {
    #expect(ActivitySample.cpuText(-0.4) == "0.0%")
}

@Test func memoryIsRenderedTheWayAPersonWouldSayIt() {
    #expect(ActivitySample.memoryText(0) == "<1 MB")
    #expect(ActivitySample.memoryText(340 * 1_048_576) == "340 MB")
    #expect(ActivitySample.memoryText(999 * 1_048_576) == "999 MB")
    // Over a thousand megabytes it becomes gigabytes, to one decimal.
    #expect(ActivitySample.memoryText(2048 * 1_048_576) == "2.0 GB")
    #expect(ActivitySample.memoryText(12 * 1024 * 1_048_576) == "12 GB")
}

/// A cell one icon thick has no room for the space and the second letter.
@Test func theCompactUnitIsOneLetter() {
    #expect(ActivitySample.compactMemoryText(340 * 1_048_576) == "340M")
    #expect(ActivitySample.compactMemoryText(2048 * 1_048_576) == "2.0G")
}

// MARK: - Settings

@Test func theActivityOverlayIsOffUntilAskedFor() throws {
    #expect(Settings().activityOverlayEnabled == false)
    let existing = try #require(
        try? JSONDecoder().decode(Settings.self, from: Data(#"{"edge":"left"}"#.utf8)))
    #expect(existing.activityOverlayEnabled == false)
    let asked = try #require(
        try? JSONDecoder().decode(
            Settings.self, from: Data(#"{"activityOverlayEnabled":true}"#.utf8)))
    #expect(asked.activityOverlayEnabled)
}
