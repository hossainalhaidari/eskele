import AppKit
import Testing
@testable import Eskele

// Run without the app bundle, so every string here is the English key itself — which is what the
// assertions are written against. Counted strings are the exception: without the stringsdict a
// count reads "1 windows", so only counts above one are asserted here and the singular is checked
// against the catalogue in LocalizationTests.

private let safari = AppRef(
    bundleID: "com.apple.Safari",
    url: URL(fileURLWithPath: "/Applications/Safari.app"),
    name: "Safari")

private func app(
    running: Bool = true,
    frontmost: Bool = false,
    windows: Int = 0,
    configure: (inout DockItem) -> Void = { _ in }
) -> DockItem {
    var item = DockItem(kind: .app(safari), isPinned: true, isRunning: running, isFrontmost: frontmost)
    item.windowCount = windows
    configure(&item)
    return item
}

private func describe(_ item: DockItem, progress: ProgressReport? = nil) -> CellDescription? {
    CellDescription(item: item, progress: progress)
}

@Test func anAppIsAButtonNamedForTheApp() throws {
    let description = try #require(describe(app(frontmost: true, windows: 3)))
    #expect(description.role == .button)
    #expect(description.label == "Safari")
    #expect(description.states == ["running", "active", "3 windows"])
    #expect(description.value == "running, active, 3 windows")
}

/// Silence for a pin that is not open, as in the system Dock — otherwise every launcher on the bar
/// says so, and the ones that are open get lost among them.
@Test func aPinThatIsNotRunningSaysNothing() throws {
    let description = try #require(describe(app(running: false)))
    #expect(description.states.isEmpty)
    #expect(description.value == nil)
}

/// Zero windows is "unknown" as well as "none", so it is not claimed.
@Test func anUnknownWindowCountIsNotSaid() throws {
    #expect(try #require(describe(app(windows: 0))).states == ["running"])
}

/// Stalled or starting is the news, so it comes first — and it replaces "running", which it implies.
@Test func aStalledAppSaysSoFirst() throws {
    let stalled = try #require(describe(app(frontmost: true) { $0.isUnresponsive = true }))
    #expect(stalled.states == ["not responding", "active"])

    let starting = try #require(describe(app { $0.isLaunching = true }))
    #expect(starting.states == ["opening"])

    let asking = try #require(describe(app { $0.needsAttention = true }))
    #expect(asking.states == ["needs attention", "running"])
}

@Test func hiddenAndFullScreenAreSaid() throws {
    let description = try #require(describe(app {
        $0.isHidden = true
        $0.isFullScreen = true
    }))
    #expect(description.states == ["running", "hidden", "full screen"])
}

/// The name the user gave the cell is its name to VoiceOver too.
@Test func aCustomNameIsTheLabel() throws {
    #expect(try #require(describe(app { $0.customName = "Browser" })).label == "Browser")
}

/// The page is context, so it goes last — and is left out when it only repeats the name.
@Test func theWindowTitleIsSaidLast() throws {
    let reading = try #require(describe(app(windows: 2) { $0.windowTitle = "Inbox" }))
    #expect(reading.states.last == "Inbox")

    let same = try #require(describe(app { $0.windowTitle = "Safari" }))
    #expect(same.states == ["running"])
}

/// A window button is named for its document, so the app it belongs to is said straight after.
@Test func aWindowButtonIsNamedForItsTitle() throws {
    var window = WindowRef(pid: 42, title: "Inbox", isMinimized: true)
    window.isOffSpace = true
    let item = DockItem(kind: .window(safari, window), isRunning: true)
    let description = try #require(describe(item))
    #expect(description.role == .button)
    #expect(description.label == "Inbox")
    #expect(description.states == ["Safari", "minimised", "on another Space"])

    let untitled = DockItem(kind: .window(safari, WindowRef(pid: 42, title: "", isMinimized: false)))
    #expect(try #require(describe(untitled)).label == "Safari")
}

/// A badge is only a number; what it counts is the app's business, so it is read as exactly that.
@Test func aBadgeIsReadAsANumber() throws {
    let description = try #require(describe(app { $0.badge = 3 }))
    #expect(description.states == ["running", "badge 3"])
    #expect(try #require(describe(app { $0.badge = 0 })).states == ["running"])
}

@Test func theTrashSaysWhetherItIsEmpty() throws {
    let empty = try #require(describe(DockItem(kind: .trash(isEmpty: true))))
    #expect(empty.label == "Trash")
    #expect(empty.states == ["empty"])

    let full = try #require(describe(DockItem(kind: .trash(isEmpty: false))))
    #expect(full.states == ["not empty"])

    // Its badge is a count of what is in it, and is said as one — not a second time as a badge.
    var counted = DockItem(kind: .trash(isEmpty: false))
    counted.badge = 4
    #expect(try #require(describe(counted)).states == ["4 items"])
}

/// A press on these opens a list rather than doing something, and VoiceOver says so before it is
/// pressed.
@Test func folderAndAppsMenuAreMenuButtons() throws {
    let folder = DockItem(kind: .folder(URL(fileURLWithPath: "/Users/someone/Downloads")), isPinned: true)
    #expect(try #require(describe(folder)).role == .menuButton)
    #expect(try #require(describe(folder)).label == "Downloads")

    let launcher = try #require(describe(DockItem(kind: .appsMenu)))
    #expect(launcher.role == .menuButton)
    #expect(launcher.label == "Apps")

    let file = DockItem(kind: .file(URL(fileURLWithPath: "/Users/someone/notes.txt")), isPinned: true)
    #expect(try #require(describe(file)).role == .button)
}

/// The reading in full, whatever the face drawn on the bar leaves out.
@Test func theClockSaysTheDateAndTime() throws {
    let moment = Date(timeIntervalSince1970: 1_757_000_000)
    let description = try #require(CellDescription(item: DockItem(kind: .clock), now: moment))
    #expect(description.label == "Clock")
    #expect(description.states == [ClockContent.description(at: moment)])
}

@Test func progressIsSaidWithWhatItIsProgressOf() throws {
    let report = ProgressReport(kind: .file, fraction: 0.4, detail: "Copying big.zip")
    let folder = DockItem(kind: .folder(URL(fileURLWithPath: "/Users/someone/Downloads")), isPinned: true)
    let description = try #require(describe(folder, progress: report))
    // The percentage in the reader's own locale — "40%" here, "40 %" in German.
    let percent = 0.4.formatted(.percent.precision(.fractionLength(0)))
    #expect(description.states == ["Copying big.zip", percent])
}

/// A separator is a gap, not a place: nothing to name and nothing to press.
@Test func aSeparatorIsNotDescribed() {
    #expect(describe(DockItem(kind: .separator("x"), isPinned: true)) == nil)
}
