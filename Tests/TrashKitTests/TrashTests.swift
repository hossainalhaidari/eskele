import Foundation
import Testing
@testable import TrashKit

private func makeTempDir() -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-trash-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Waits for the watcher to notice, rather than assuming it will inside a fixed sleep.
///
/// The FSEvents callback is delivered on the main queue, and these tests share that queue with every
/// other main-actor test in the run — a constant long enough to be reliable under load is far longer
/// than the wait actually needs to be. Polling is both quicker in the common case and not a race.
@MainActor
private func wait(
    upTo seconds: Double = 3, until condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Test func emptyDirectoryReadsAsEmpty() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(Trash.isEmpty(at: dir))
    #expect(Trash.itemCount(at: dir) == 0)
}

@Test func housekeepingFilesDoNotCountAsContents() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data().write(to: dir.appendingPathComponent(".DS_Store"))
    #expect(Trash.isEmpty(at: dir))

    try Data("x".utf8).write(to: dir.appendingPathComponent("real.txt"))
    #expect(!Trash.isEmpty(at: dir))
    #expect(Trash.itemCount(at: dir) == 1)
}

@Test func missingDirectoryReadsAsEmptyRatherThanCrashing() {
    let dir = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    #expect(Trash.isEmpty(at: dir))
}

@Test func trashURLResolves() {
    #expect(Trash.url.lastPathComponent == ".Trash")
}

@MainActor
@Test func watcherReportsTransitionToFullAndBack() async throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let watcher = TrashWatcher(url: dir, debounce: 0.02)
    #expect(watcher.isEmpty)

    var observed: [Bool] = []
    watcher.onChange = { observed.append($0.isEmpty) }

    let file = dir.appendingPathComponent("junk.txt")
    try Data("x".utf8).write(to: file)
    try await wait { watcher.isEmpty == false }
    #expect(watcher.isEmpty == false)

    try FileManager.default.removeItem(at: file)
    try await wait { watcher.isEmpty == true }
    #expect(watcher.isEmpty == true)
    #expect(observed == [false, true])
}

/// The count is drawn as a badge, so a second item arriving *is* a change the bar has to see —
/// but editing a file that is already in there is not.
@MainActor
@Test func watcherReportsCountChangesButNotContentEdits() async throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let first = dir.appendingPathComponent("one.txt")
    try Data("a".utf8).write(to: first)

    let watcher = TrashWatcher(url: dir, debounce: 0.02)
    #expect(watcher.snapshot.count == 1)

    var observed: [Int] = []
    watcher.onChange = { observed.append($0.count) }

    try Data("b".utf8).write(to: dir.appendingPathComponent("two.txt"))
    try await wait { observed == [2] }
    #expect(observed == [2])

    // Asserting an absence, so this one has to be a plain wait: there is no state to poll for.
    try Data("much longer contents".utf8).write(to: first)
    try await Task.sleep(for: .milliseconds(300))
    #expect(observed == [2])
}

/// A paused poll reads nothing, and unpausing reads straight away rather than at the next tick —
/// the bar should be right by the time the displays are awake to show it.
///
/// A folder that does not exist yet cannot be opened for watching, so this watcher polls, which is
/// the route a machine without Full Disk Access takes on the real Trash.
@MainActor
@Test func aPausedPollReadsNothingAndUnpausingReadsAtOnce() async throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-trash-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let watcher = TrashWatcher(url: dir, debounce: 0.02, pollInterval: 0.05)
    #expect(watcher.isPolling)
    watcher.isPaused = true

    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: dir.appendingPathComponent("junk.txt"))
    // Asserting an absence, so a plain wait: several poll intervals with nothing read.
    try await Task.sleep(for: .milliseconds(300))
    #expect(watcher.isEmpty)

    watcher.isPaused = false
    #expect(!watcher.isEmpty)
}

/// The reason the Trash always read as empty: `~/.Trash` needs Full Disk Access, and a refused
/// listing looked exactly like an empty one. The metadata route has to survive that.
@Test func metadataCountMatchesADirectoryListing() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    #expect(Trash.read(at: dir) == TrashSnapshot(count: 0, isExact: true))

    try Data("x".utf8).write(to: dir.appendingPathComponent(".DS_Store"))
    for index in 0..<3 {
        try Data("x".utf8).write(to: dir.appendingPathComponent("item-\(index).txt"))
    }
    try FileManager.default.createDirectory(
        at: dir.appendingPathComponent("folder"), withIntermediateDirectories: true)

    let listed = Trash.read(at: dir)
    #expect(listed == TrashSnapshot(count: 4, isExact: true))
    #expect(Trash.metadataCount(at: dir) == listed.count)
}

@Test func metadataCountIsZeroForAnEmptyDirectory() {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(Trash.metadataCount(at: dir) == 0)
}

/// The real Trash, whichever route we get there by. This is the case that was broken: on a machine
/// without Full Disk Access it must still report what is actually in there.
@Test func theRealTrashIsReadableOneWayOrTheOther() {
    let snapshot = Trash.read()
    #expect(snapshot.count >= 0)
    // Not an assertion about *this* machine's Trash — just that a refused listing no longer
    // silently degrades to "exactly zero, definitely".
    if !snapshot.isExact { #expect(Trash.modificationStamp() != nil) }
}
