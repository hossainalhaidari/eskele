import Foundation

/// Hides the system Dock by rewriting `com.apple.dock` and restarting the Dock process.
///
/// The invariant this type exists to protect: **the user's Dock always comes back.** Every path out
/// of the process restores, and a backup left on disk with `cleanlyRestored == false` is treated on
/// the next launch as evidence that we were killed mid-flight.
public final class DockSuppressor: @unchecked Sendable {
    private let store: PreferencesStore
    private let backups: BackupStore
    private let restartDock: @Sendable () -> Void
    private let lock = NSLock()

    public init(
        store: PreferencesStore = CFPreferencesStore(),
        backups: BackupStore,
        restartDock: @escaping @Sendable () -> Void = DockSuppressor.terminateDockProcess
    ) {
        self.store = store
        self.backups = backups
        self.restartDock = restartDock
    }

    // MARK: - State

    /// True when the live preferences currently hold our suppression values.
    public var isSuppressed: Bool {
        store.bool(forKey: DockPrefKey.autohide) == true
            && (store.double(forKey: DockPrefKey.autohideDelay) ?? 0) >= DockSuppressionValues.autohideDelay
    }

    /// True when something else (System Settings, ⌥⌘D, another utility) has moved our values.
    public func hasDrifted() -> Bool { !isSuppressed }

    /// True when the live preferences hold the Dock parked by `park(orientation:tileSize:)`.
    ///
    /// ⌥⌘D is the likely culprit when this goes false: it turns auto-hide back on, and a hidden Dock
    /// gives up its reservation the next time it re-lays out.
    public func isParked(orientation: String, tileSize: Double) -> Bool {
        store.bool(forKey: DockPrefKey.autohide) != true
            && store.string(forKey: DockPrefKey.orientation) == orientation
            && store.double(forKey: DockPrefKey.tilesize) == tileSize
    }

    public func currentSnapshot() -> DockPrefsSnapshot {
        DockPrefsSnapshot(
            autohide: store.bool(forKey: DockPrefKey.autohide),
            autohideDelay: store.double(forKey: DockPrefKey.autohideDelay),
            autohideTimeModifier: store.double(forKey: DockPrefKey.autohideTimeModifier),
            orientation: store.string(forKey: DockPrefKey.orientation),
            tilesize: store.double(forKey: DockPrefKey.tilesize),
            launchAnimation: store.bool(forKey: DockPrefKey.launchAnimation),
            noBouncing: store.bool(forKey: DockPrefKey.noBouncing),
            schema: DockPrefsSnapshot.currentSchema
        )
    }

    /// Captured exactly once per suppression episode. Re-entrancy here is what stops a drift repair
    /// from overwriting the user's real settings with our own.
    ///
    /// A dirty backup from before the bounce keys existed is brought up to date first. The version
    /// that wrote it never touched those keys, so their live values are still the user's own — and
    /// this runs before anything here writes them.
    @discardableResult
    private func captureBackupIfNeededLocked() -> DockPrefsSnapshot {
        if var existing = backups.loadBackup(), !existing.cleanlyRestored {
            if !existing.capturesBounceKeys {
                existing.launchAnimation = store.bool(forKey: DockPrefKey.launchAnimation)
                existing.noBouncing = store.bool(forKey: DockPrefKey.noBouncing)
                existing.schema = DockPrefsSnapshot.currentSchema
                backups.saveBackup(existing)
            }
            return existing
        }
        let backup = currentSnapshot()
        backups.saveBackup(backup)
        return backup
    }

    // MARK: - Reserved-space mode

    /// Pins the Dock, **visible**, to `orientation` at `tileSize`, where the bar covers it.
    ///
    /// Visible is the whole point: see `DockParkingValues` for why a hidden Dock cannot hold a
    /// reservation. A pinned Dock republishes the right size every time it re-lays out, with the
    /// right orientation, and every running app hears about it.
    @discardableResult
    public func park(orientation: String, tileSize: Double, restartingDock: Bool = true) -> DockPrefsSnapshot {
        lock.lock()
        let backup = captureBackupIfNeededLocked()
        store.setString(orientation, forKey: DockPrefKey.orientation)
        store.setDouble(tileSize, forKey: DockPrefKey.tilesize)
        store.setBool(DockParkingValues.autohide, forKey: DockPrefKey.autohide)
        store.setDouble(DockSuppressionValues.autohideDelay, forKey: DockPrefKey.autohideDelay)
        store.setDouble(DockSuppressionValues.autohideTimeModifier, forKey: DockPrefKey.autohideTimeModifier)
        store.setBool(DockParkingValues.launchAnimation, forKey: DockPrefKey.launchAnimation)
        store.setBool(DockParkingValues.noBouncing, forKey: DockPrefKey.noBouncing)
        store.synchronize()
        lock.unlock()

        if restartingDock { restartDock() }
        return backup
    }

    // MARK: - Suppress / restore

    /// Captures a backup (once) and applies the suppression values.
    ///
    /// Re-entrant: calling it while already suppressed re-applies the values but never overwrites the
    /// backup, so a drift-repair cannot destroy the user's original settings.
    @discardableResult
    public func suppress(restartingDock: Bool = true) -> DockPrefsSnapshot {
        lock.lock()
        let backup = captureBackupIfNeededLocked()

        store.setBool(DockSuppressionValues.autohide, forKey: DockPrefKey.autohide)
        store.setDouble(DockSuppressionValues.autohideDelay, forKey: DockPrefKey.autohideDelay)
        store.setDouble(DockSuppressionValues.autohideTimeModifier, forKey: DockPrefKey.autohideTimeModifier)
        store.synchronize()
        lock.unlock()

        if restartingDock { restartDock() }
        return backup
    }

    /// Writes the user's original values back and drops the backup.
    ///
    /// Safe to call when we never suppressed, when we already restored, and from a signal handler
    /// context (it is driven by a `DispatchSource`, not a raw `sigaction`, precisely so this can do
    /// real work).
    @discardableResult
    public func restore(restartingDock: Bool = true) -> Bool {
        lock.lock()
        guard let backup = backups.loadBackup(), !backup.cleanlyRestored else {
            lock.unlock()
            return false
        }

        store.setBool(backup.autohide, forKey: DockPrefKey.autohide)
        store.setDouble(backup.autohideDelay, forKey: DockPrefKey.autohideDelay)
        store.setDouble(backup.autohideTimeModifier, forKey: DockPrefKey.autohideTimeModifier)
        store.setString(backup.orientation, forKey: DockPrefKey.orientation)
        store.setDouble(backup.tilesize, forKey: DockPrefKey.tilesize)
        if backup.capturesBounceKeys {
            store.setBool(backup.launchAnimation, forKey: DockPrefKey.launchAnimation)
            store.setBool(backup.noBouncing, forKey: DockPrefKey.noBouncing)
        }
        store.synchronize()

        var done = backup
        done.cleanlyRestored = true
        backups.saveBackup(done)
        lock.unlock()

        if restartingDock { restartDock() }
        return true
    }

    /// Launch-time recovery. Returns true when it actually restored something.
    ///
    /// - Parameter wantsSuppression: the user's current setting. If they still want the Dock hidden
    ///   we leave it hidden and simply keep the existing backup; otherwise a dirty backup means a
    ///   previous run was `SIGKILL`ed and we owe them their Dock back.
    @discardableResult
    public func recoverIfNeeded(wantsSuppression: Bool) -> Bool {
        guard let backup = backups.loadBackup(), !backup.cleanlyRestored else { return false }
        if wantsSuppression { return false }
        return restore()
    }

    // MARK: - Dock process

    /// `SIGTERM` rather than a Quit Apple Event: terminating another process owned by the same user
    /// needs no entitlement and no Automation consent, and `launchd` brings the Dock straight back.
    public static let terminateDockProcess: @Sendable () -> Void = {
        for pid in dockProcessIDs() { kill(pid, SIGTERM) }
    }

    static func dockProcessIDs() -> [pid_t] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&name, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&name, 4, &procs, &size, nil, 0) == 0 else { return [] }
        let actual = size / MemoryLayout<kinfo_proc>.stride
        let uid = getuid()
        var pids: [pid_t] = []
        for i in 0..<min(actual, procs.count) {
            var p = procs[i]
            guard p.kp_eproc.e_ucred.cr_uid == uid else { continue }
            let comm = withUnsafeBytes(of: &p.kp_proc.p_comm) { raw -> String in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            if comm == "Dock" { pids.append(p.kp_proc.p_pid) }
        }
        return pids
    }
}
