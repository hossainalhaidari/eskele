import Foundation
import Testing
@testable import DockPrefsKit

private func makeSuppressor(
    initial: [String: Any] = [:],
    backup: DockPrefsSnapshot? = nil
) -> (DockSuppressor, InMemoryPreferencesStore, InMemoryBackupStore, @Sendable () -> Int) {
    let store = InMemoryPreferencesStore(initial: initial)
    let backups = InMemoryBackupStore(backup)
    let restarts = Counter()
    let suppressor = DockSuppressor(store: store, backups: backups, restartDock: { restarts.bump() })
    return (suppressor, store, backups, { restarts.value })
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@Test func suppressAppliesValuesAndRestartsDock() {
    let (suppressor, store, _, restarts) = makeSuppressor()
    suppressor.suppress()

    #expect(store.bool(forKey: DockPrefKey.autohide) == true)
    #expect(store.double(forKey: DockPrefKey.autohideDelay) == 1000)
    #expect(store.double(forKey: DockPrefKey.autohideTimeModifier) == 0)
    #expect(suppressor.isSuppressed)
    #expect(restarts() == 1)
}

@Test func suppressCapturesTheUsersOriginalValues() {
    let (suppressor, _, backups, _) = makeSuppressor(
        initial: [DockPrefKey.autohide: false, DockPrefKey.autohideDelay: 0.5])
    suppressor.suppress()

    let backup = backups.loadBackup()
    #expect(backup?.autohide == false)
    #expect(backup?.autohideDelay == 0.5)
    #expect(backup?.cleanlyRestored == false)
}

@Test func restorePutsTheUsersValuesBack() {
    let (suppressor, store, _, restarts) = makeSuppressor(
        initial: [DockPrefKey.autohide: false, DockPrefKey.autohideDelay: 0.5])
    suppressor.suppress()
    #expect(suppressor.restore())

    #expect(store.bool(forKey: DockPrefKey.autohide) == false)
    #expect(store.double(forKey: DockPrefKey.autohideDelay) == 0.5)
    #expect(restarts() == 2)
}

/// A key that was absent must be *removed* on restore, not written back as an explicit value —
/// otherwise we permanently freeze a system default the user never set.
@Test func restoreRemovesKeysThatWereNotPresentBefore() {
    let (suppressor, store, _, _) = makeSuppressor()
    suppressor.suppress()
    suppressor.restore()

    #expect(store.bool(forKey: DockPrefKey.autohide) == nil)
    #expect(store.double(forKey: DockPrefKey.autohideDelay) == nil)
    #expect(store.double(forKey: DockPrefKey.autohideTimeModifier) == nil)
}

/// Drift repair must not clobber the backup, or the user's real settings would be lost after the
/// first time System Settings touches the Dock.
@Test func repeatedSuppressionKeepsTheOriginalBackup() {
    let (suppressor, store, backups, _) = makeSuppressor(initial: [DockPrefKey.autohide: false])
    suppressor.suppress()
    store.setBool(false, forKey: DockPrefKey.autohide)   // user hits ⌥⌘D
    #expect(suppressor.hasDrifted())
    suppressor.suppress()                                // watchdog repairs

    #expect(backups.loadBackup()?.autohide == false)
    #expect(suppressor.isSuppressed)
}

@Test func restoreIsIdempotent() {
    let (suppressor, _, _, restarts) = makeSuppressor()
    suppressor.suppress()
    #expect(suppressor.restore())
    #expect(suppressor.restore() == false)
    #expect(restarts() == 2)
}

@Test func restoreWithoutSuppressionDoesNothing() {
    let (suppressor, _, _, restarts) = makeSuppressor()
    #expect(suppressor.restore() == false)
    #expect(restarts() == 0)
}

/// The SIGKILL path: a dirty backup on disk at launch means the last run never restored.
@Test func recoveryRestoresAfterAnUncleanExit() {
    let dirty = DockPrefsSnapshot(autohide: false, autohideDelay: nil, cleanlyRestored: false)
    let (suppressor, store, _, _) = makeSuppressor(
        initial: [DockPrefKey.autohide: true, DockPrefKey.autohideDelay: 1000.0], backup: dirty)

    #expect(suppressor.recoverIfNeeded(wantsSuppression: false))
    #expect(store.bool(forKey: DockPrefKey.autohide) == false)
    #expect(store.double(forKey: DockPrefKey.autohideDelay) == nil)
}

@Test func recoveryLeavesTheDockHiddenWhenTheUserStillWantsThat() {
    let dirty = DockPrefsSnapshot(autohide: false, cleanlyRestored: false)
    let (suppressor, store, backups, _) = makeSuppressor(
        initial: [DockPrefKey.autohide: true, DockPrefKey.autohideDelay: 1000.0], backup: dirty)

    #expect(suppressor.recoverIfNeeded(wantsSuppression: true) == false)
    #expect(store.bool(forKey: DockPrefKey.autohide) == true)
    #expect(backups.loadBackup()?.cleanlyRestored == false)
}

@Test func recoveryIgnoresACleanBackup() {
    let clean = DockPrefsSnapshot(autohide: false, cleanlyRestored: true)
    let (suppressor, _, _, restarts) = makeSuppressor(backup: clean)
    #expect(suppressor.recoverIfNeeded(wantsSuppression: false) == false)
    #expect(restarts() == 0)
}

@Test func fileBackupStoreRoundTrips() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = FileBackupStore(url: dir.appendingPathComponent("dock-backup.json"))
    #expect(store.loadBackup() == nil)

    let snapshot = DockPrefsSnapshot(
        autohide: true, autohideDelay: 0.25, autohideTimeModifier: nil, noBouncing: true,
        schema: DockPrefsSnapshot.currentSchema)
    store.saveBackup(snapshot)
    let loaded = store.loadBackup()
    #expect(loaded?.autohide == true)
    #expect(loaded?.autohideDelay == 0.25)
    #expect(loaded?.autohideTimeModifier == nil)
    #expect(loaded?.noBouncing == true)
    #expect(loaded?.launchAnimation == nil)
    #expect(loaded?.schema == DockPrefsSnapshot.currentSchema)

    store.saveBackup(nil)
    #expect(store.loadBackup() == nil)
}

/// A backup written before `schema` existed must still decode — it is exactly the file a user
/// upgrading mid-suppression has on disk.
@Test func legacyBackupFileDecodes() throws {
    let json = #"{"autohide":false,"capturedAt":811160411.07,"cleanlyRestored":false,"orientation":"left","tilesize":31}"#
    let snapshot = try JSONDecoder().decode(DockPrefsSnapshot.self, from: Data(json.utf8))
    #expect(snapshot.orientation == "left")
    #expect(snapshot.schema == nil)
    #expect(!snapshot.capturesBounceKeys)
}

@Test func dockProcessLookupFindsTheRunningDock() {
    // The Dock is always running in a normal user session; if this ever returns empty the restart
    // path is silently a no-op, which is the failure we most need to know about.
    #expect(!DockSuppressor.dockProcessIDs().isEmpty)
}

// MARK: - Reserved-space mode

/// Measured on macOS 26.6: the reservation the window server keeps for the Dock is exactly
/// `tilesize + 20` points, and `defaults` accepts tile sizes below the 16pt floor the Dock's own
/// slider enforces (4 → 24pt reserved).
@Test func tileSizeMapsToReservedThickness() {
    #expect(DockReservation.tileSize(forReservedThickness: 32) == 12)
    #expect(DockReservation.tileSize(forReservedThickness: 24) == 4)
    #expect(DockReservation.reservedThickness(forTileSize: 12) == 32)
    // A bar thinner than the fixed overhead cannot be matched exactly; clamp rather than go negative.
    #expect(DockReservation.tileSize(forReservedThickness: 10) == DockReservation.minimumTileSize)
    #expect(DockReservation.tileSize(forReservedThickness: 900) == DockReservation.maximumTileSize)
}

/// The parked Dock must stay *visible*: a hidden one gives its reservation up at its next re-layout,
/// and only the Dock's own publications reach running apps. One restart, no second phase.
@Test func parkLeavesTheDockVisibleOnTheBarsEdge() {
    let (suppressor, store, _, restarts) = makeSuppressor(
        initial: [DockPrefKey.orientation: "left", DockPrefKey.tilesize: 42.0])
    suppressor.park(orientation: "bottom", tileSize: 12)

    #expect(store.string(forKey: DockPrefKey.orientation) == "bottom")
    #expect(store.double(forKey: DockPrefKey.tilesize) == 12)
    #expect(store.bool(forKey: DockPrefKey.autohide) == false)
    #expect(store.bool(forKey: DockPrefKey.launchAnimation) == false)
    #expect(store.bool(forKey: DockPrefKey.noBouncing) == true)
    #expect(suppressor.isParked(orientation: "bottom", tileSize: 12))
    #expect(restarts() == 1)
}

/// ⌥⌘D turns auto-hide back on, and a parked Dock that is hidden reserves nothing — so that is drift,
/// as is anything moving it off the bar's edge or changing its size.
@Test func parkedDockDriftsWhenMovedOrHidden() {
    let (suppressor, store, _, _) = makeSuppressor()
    suppressor.park(orientation: "bottom", tileSize: 12)
    #expect(!suppressor.isParked(orientation: "left", tileSize: 12))
    #expect(!suppressor.isParked(orientation: "bottom", tileSize: 16))

    store.setBool(true, forKey: DockPrefKey.autohide)
    #expect(!suppressor.isParked(orientation: "bottom", tileSize: 12))
}

@Test func restoreUndoesEverythingParkingWrote() {
    let (suppressor, store, _, _) = makeSuppressor(
        initial: [DockPrefKey.orientation: "left", DockPrefKey.tilesize: 42.0, DockPrefKey.autohide: false])
    suppressor.park(orientation: "bottom", tileSize: 12)
    #expect(suppressor.restore())

    #expect(store.string(forKey: DockPrefKey.orientation) == "left")
    #expect(store.double(forKey: DockPrefKey.tilesize) == 42)
    #expect(store.bool(forKey: DockPrefKey.autohide) == false)
    #expect(store.double(forKey: DockPrefKey.autohideDelay) == nil)
    #expect(store.bool(forKey: DockPrefKey.launchAnimation) == nil)
    #expect(store.bool(forKey: DockPrefKey.noBouncing) == nil)
}

/// Moving between hidden and parked is one episode: the backup captured first must survive, or
/// restore would put the user back to *our* Dock position.
@Test func switchingModesKeepsOneBackup() {
    let (suppressor, _, backups, _) = makeSuppressor(
        initial: [DockPrefKey.orientation: "right", DockPrefKey.tilesize: 64.0])
    suppressor.park(orientation: "bottom", tileSize: 12)
    suppressor.suppress()
    suppressor.park(orientation: "left", tileSize: 12)

    let backup = backups.loadBackup()
    #expect(backup?.orientation == "right")
    #expect(backup?.tilesize == 64)
}

/// A backup left dirty by a version that never wrote the bounce keys is brought up to date before
/// they are written, so it is the user's own values that come back.
@Test func legacyBackupCapturesBounceKeysBeforeParking() {
    let legacy = DockPrefsSnapshot(autohide: false, orientation: "left", cleanlyRestored: false)
    let (suppressor, store, backups, _) = makeSuppressor(
        initial: [DockPrefKey.launchAnimation: false], backup: legacy)
    suppressor.park(orientation: "bottom", tileSize: 12)

    let upgraded = backups.loadBackup()
    #expect(upgraded?.schema == DockPrefsSnapshot.currentSchema)
    #expect(upgraded?.launchAnimation == false)
    #expect(upgraded?.noBouncing == nil)
    #expect(upgraded?.orientation == "left")

    suppressor.restore()
    #expect(store.bool(forKey: DockPrefKey.launchAnimation) == false)
    #expect(store.bool(forKey: DockPrefKey.noBouncing) == nil)
}

/// Restoring a legacy backup must not touch keys it never captured: its `nil` there means
/// "unknown", and removing them would erase a value the user set themselves.
@Test func legacyBackupRestoreLeavesBounceKeysAlone() {
    let legacy = DockPrefsSnapshot(autohide: false, cleanlyRestored: false)
    let (suppressor, store, _, _) = makeSuppressor(
        initial: [DockPrefKey.autohide: true, DockPrefKey.launchAnimation: false], backup: legacy)

    #expect(suppressor.recoverIfNeeded(wantsSuppression: false))
    #expect(store.bool(forKey: DockPrefKey.autohide) == false)
    #expect(store.bool(forKey: DockPrefKey.launchAnimation) == false)
}
