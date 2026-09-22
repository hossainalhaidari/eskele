import Foundation
import Testing
@testable import Eskele

// MARK: - Fractions

/// A source is a shell command written by a person, so both conventions have to work — and the one
/// case that is genuinely ambiguous, `1`, has to be settled the way the person meant it.
@Test func commandOutputIsReadAsAPercentageOrAFraction() {
    #expect(ProgressReport.fraction(fromCommandOutput: "42") == 0.42)
    #expect(ProgressReport.fraction(fromCommandOutput: "42%") == 0.42)
    #expect(ProgressReport.fraction(fromCommandOutput: "0.42") == 0.42)
    // "1 out of 1" is finished, not one percent.
    #expect(ProgressReport.fraction(fromCommandOutput: "1") == 1)
    #expect(ProgressReport.fraction(fromCommandOutput: "1%") == 0.01)
    #expect(ProgressReport.fraction(fromCommandOutput: "0") == 0)
}

@Test func chattyOrEmptyOutputIsHandled() {
    #expect(ProgressReport.fraction(fromCommandOutput: "  building: 73% done\n") == 0.73)
    #expect(ProgressReport.fraction(fromCommandOutput: "") == nil)
    #expect(ProgressReport.fraction(fromCommandOutput: "still working\n") == nil)
    // Out of range clamps rather than drawing a bar off the end of the cell.
    #expect(ProgressReport.fraction(fromCommandOutput: "180") == 1)
}

/// Nothing downstream defends itself against a bad number, so this has to.
///
/// A number that is not a number reads as *nothing done*, not as done: an empty bar says "we do not
/// know how far along this is", and a full one would claim something untrue.
@Test func reportsClampWhateverTheyAreGiven() {
    #expect(ProgressReport(kind: .custom, fraction: 5).fraction == 1)
    #expect(ProgressReport(kind: .custom, fraction: -2).fraction == 0)
    #expect(ProgressReport(kind: .custom, fraction: .nan).fraction == 0)
    #expect(ProgressReport(kind: .custom, fraction: 0 / 0.0).fraction == 0)
    #expect(ProgressReport(kind: .custom, fraction: .infinity).fraction == 0)
}

// MARK: - Media position

private let noon = Date(timeIntervalSince1970: 1_700_000_000)

@Test func aPlayingTrackAdvancesBetweenReadings() {
    let sample = MediaPosition(position: 30, duration: 240, isPlaying: true, sampledAt: noon)
    #expect(sample.position(at: noon) == 30)
    #expect(sample.position(at: noon.addingTimeInterval(10)) == 40)
    #expect(sample.report(at: noon.addingTimeInterval(90))?.fraction == 0.5)
}

/// A paused player holds where it is, however long ago it was asked.
@Test func aPausedTrackDoesNotAdvance() {
    let sample = MediaPosition(position: 30, duration: 240, isPlaying: false, sampledAt: noon)
    #expect(sample.position(at: noon.addingTimeInterval(600)) == 30)
}

/// A track that ends between readings must stop at the end rather than run off the scale until the
/// next one arrives.
@Test func extrapolationStopsAtTheEndOfTheTrack() {
    let sample = MediaPosition(position: 230, duration: 240, isPlaying: true, sampledAt: noon)
    #expect(sample.position(at: noon.addingTimeInterval(3600)) == 240)
    #expect(sample.report(at: noon.addingTimeInterval(3600))?.fraction == 1)
}

/// A live stream has no end, so it has no bar.
@Test func aTrackWithNoDurationReportsNothing() {
    #expect(MediaPosition(position: 12, duration: 0, isPlaying: true, sampledAt: noon)
        .report(at: noon) == nil)
}

@Test func timesReadAsTimes() {
    #expect(MediaPosition.clock(0) == "0:00")
    #expect(MediaPosition.clock(9) == "0:09")
    #expect(MediaPosition.clock(83) == "1:23")
    #expect(MediaPosition.clock(245) == "4:05")
    // Only past an hour, so a three-minute track is not written as a stopwatch.
    #expect(MediaPosition.clock(3600) == "1:00:00")
    #expect(MediaPosition.clock(3725) == "1:02:05")
    #expect(MediaPosition.clock(-5) == "0:00")
}

@Test func theHoverDetailNamesBothEnds() {
    let sample = MediaPosition(position: 83, duration: 245, isPlaying: false, sampledAt: noon)
    #expect(sample.report(at: noon)?.detail == "1:23 of 4:05")
}

// MARK: - Player replies

private func music() -> MediaPlayer { MediaPlayer.known(bundleID: "com.apple.Music")! }
private func spotify() -> MediaPlayer { MediaPlayer.known(bundleID: "com.spotify.client")! }

/// The scripts answer in whole milliseconds; the bar works in seconds.
@Test func aPlayersReplyIsParsed() {
    let parsed = music().parse("playing|83500|245000\n", now: noon)
    #expect(parsed?.position == 83.5)
    #expect(parsed?.duration == 245)
    #expect(parsed?.isPlaying == true)

    #expect(music().parse("paused|10000|100000", now: noon)?.isPlaying == false)
}

/// Both players normalise to milliseconds in their own script, so the same reply means the same
/// thing whichever one sent it — Spotify's duration is already in milliseconds and Music's is not.
@Test func everyPlayerAnswersInTheSameUnits() {
    #expect(music().parse("playing|60000|240000", now: noon)?.duration == 240)
    #expect(spotify().parse("playing|60000|240000", now: noon)?.duration == 240)
    #expect(spotify().parse("playing|60000|240000", now: noon)?.report(at: noon)?.fraction == 0.25)
}

/// The bug that made this feature do nothing on a German Mac: AppleScript coerces a real to text
/// with the *system's* decimal separator, so the reply came back as `268,60` and was thrown away —
/// player running, Automation granted, script exit 0, no bar. The scripts now emit integers, and
/// this stays lenient so the same mistake cannot be made twice.
@Test func aCommaDecimalSeparatorIsUnderstood() {
    #expect(MediaPlayer.milliseconds("268605") == 268605)
    #expect(MediaPlayer.milliseconds("268,605987548828") == 268.605987548828)
    #expect(MediaPlayer.milliseconds("268.605987548828") == 268.605987548828)
    // Both separators: the comma is grouping thousands, not marking a decimal.
    #expect(MediaPlayer.milliseconds("1,234.5") == 1234.5)
    #expect(MediaPlayer.milliseconds("nonsense") == nil)

    let german = music().parse("playing|268,605987548828|313,730987548828", now: noon)
    #expect(german != nil)
    #expect(abs((german?.report(at: noon)?.fraction ?? 0) - 0.856) < 0.001)
}

/// An AppleScript error, a refused Automation prompt and a player that just quit all arrive as
/// noise. None of them may put a bar on a tile.
@Test func anythingButTheAgreedShapeIsRefused() {
    #expect(music().parse("stopped||", now: noon) == nil)
    #expect(music().parse("", now: noon) == nil)
    #expect(music().parse("execution error: Music got an error", now: noon) == nil)
    #expect(music().parse("playing|abc|245000", now: noon) == nil)
    #expect(music().parse("playing|83000", now: noon) == nil)
    #expect(music().parse("playing|83000|245000|extra", now: noon) == nil)
}

// MARK: - Addressing

/// A window button answers to its app's key: the track belongs to the app, not to one of its
/// windows, so every window of a playing app shows the same bar.
@Test func aWindowButtonAnswersToItsApp() {
    let url = URL(fileURLWithPath: "/System/Applications/Music.app")
    let ref = AppRef(bundleID: "com.apple.Music", url: url, name: "Music")
    let window = WindowRef(pid: 1, title: "Music", isMinimized: false)

    #expect(DockItem(kind: .app(ref)).progressKey == "app:com.apple.Music")
    #expect(DockItem(kind: .window(ref, window)).progressKey == "app:com.apple.Music")
}

@Test func foldersAreAddressedByPath() {
    let downloads = URL(fileURLWithPath: "/Users/someone/Downloads")
    #expect(DockItem(kind: .folder(downloads)).progressKey == "path:/Users/someone/Downloads")
    #expect(DockItem(kind: .trash(isEmpty: true)).progressKey == nil)
    #expect(DockItem(kind: .appsMenu).progressKey == nil)
    #expect(DockItem(kind: .clock).progressKey == nil)
}

/// One field in `progress.json` addresses either kind, and the leading slash is what says which.
@Test func aSourceTargetsAnAppOrAPath() {
    #expect(ProgressService.key(for: "com.apple.Music") == "app:com.apple.Music")
    #expect(ProgressService.key(for: "/Users/someone/Renders") == "path:/Users/someone/Renders")
}

// MARK: - Settings

/// Media costs a consent per player, so it stays off for everyone who already had a settings file;
/// the free sources stay on, because they cost nothing until there is something to show.
@Test func progressDefaultsAreTheFreeOnes() throws {
    let settings = Settings()
    #expect(settings.showProgress)
    #expect(!settings.mediaProgress)
    #expect(!settings.tracksMediaProgress)

    let existing = try #require(
        try? JSONDecoder().decode(Settings.self, from: Data(#"{"edge": "left"}"#.utf8)))
    #expect(existing.showProgress)
    #expect(!existing.mediaProgress)
}

/// Turning the whole feature off has to take the Apple events with it, not just the drawing.
@Test func switchingProgressOffStopsAskingPlayers() {
    var settings = Settings()
    settings.mediaProgress = true
    #expect(settings.tracksMediaProgress)
    settings.showProgress = false
    #expect(!settings.tracksMediaProgress)
}

// MARK: - The service end to end

/// Everything except the AppleScript: configuration is read, the command runs, and the number comes
/// out keyed the way the bar addresses its cells.
@MainActor
@Test func aCommandSourceBecomesAReportOnTheRightKey() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-progress-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let persistence = Persistence(directory: directory)
    try #"{"sources": [{"bundleID": "com.example.build", "command": "echo 64%", "interval": 2}]}"#
        .write(to: persistence.progressURL, atomically: true, encoding: .utf8)

    let service = ProgressService(persistence: persistence)
    defer { service.stop() }

    let deadline = Date().addingTimeInterval(5)
    while service.reports["app:com.example.build"] == nil, Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    let report = try #require(service.reports["app:com.example.build"])
    #expect(report.kind == .custom)
    #expect(abs(report.fraction - 0.64) < 0.001)
}
