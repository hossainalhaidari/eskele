import AppKit
import DockPrefsKit

/// Owns the system Dock's fate for the lifetime of the process.
///
/// The contract: whatever happens to us, the user's Dock comes back. Every exit path restores, and a
/// backup left dirty on disk is treated on the next launch as proof we were killed mid-flight.
@MainActor
final class SystemDockController {
    private let suppressor: DockSuppressor
    private var watchdog: Poll?
    private var signalSources: [DispatchSourceSignal] = []
    private var lastRepair: Date = .distantPast
    private var lastRequest: Request?

    private(set) var isEnabled = false

    /// What the bar wants from the system Dock. Compared as a whole so a change to any part
    /// re-applies, and so the watchdog can repeat the exact same request.
    struct Request: Equatable {
        var enabled: Bool
        var reserveSpace: Bool
        var edge: BarEdge
        var thickness: CGFloat

        var tileSize: Double { DockReservation.tileSize(forReservedThickness: Double(thickness)) }
    }

    init(backupURL: URL) {
        suppressor = DockSuppressor(backups: FileBackupStore(url: backupURL))
        atexitSuppressor = suppressor
        atexit(restoreDockAtExit)
    }

    /// Launch-time recovery, before we do anything else.
    func recoverIfNeeded(wantsSuppression: Bool) {
        if suppressor.recoverIfNeeded(wantsSuppression: wantsSuppression) {
            NSLog("Eskele: restored the system Dock after an unclean exit")
        }
    }

    func apply(_ request: Request) {
        guard request != lastRequest else { return }
        lastRequest = request

        guard request.enabled else {
            stopWatchdog()
            isEnabled = false
            suppressor.restore()
            return
        }

        isEnabled = true
        if request.reserveSpace {
            // Parked visible under the bar rather than hidden. A hidden Dock's reservation lasts
            // only until its next re-layout — the next app to launch or quit — and nothing but the
            // Dock itself can publish one that running apps will hear about. See DockParkingValues.
            suppressor.park(orientation: request.edge.dockOrientation, tileSize: request.tileSize)
        } else {
            suppressor.suppress()
        }
        startWatchdog()
    }

    /// Explicit rescue from the status menu, and the path taken on quit.
    func restoreNow() {
        stopWatchdog()
        isEnabled = false
        lastRequest = nil
        suppressor.restore()
    }

    // MARK: - Watchdog

    /// System Settings, ⌥⌘D, or another utility can put the Dock back while we are running.
    ///
    /// Repairs are rate-limited: re-applying the preferences restarts the Dock, and something
    /// fighting us must not turn into a Dock-restart loop.
    private func startWatchdog() {
        stopWatchdog()
        watchdog = Poll(every: 5, tolerance: 2) { [weak self] in self?.repairIfDrifted() }
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    /// Drift is judged against the mode asked for: a parked Dock is *meant* to have auto-hide off,
    /// so the hidden-mode test would read it as drifted on every tick.
    private func hasDrifted(from request: Request) -> Bool {
        request.reserveSpace
            ? !suppressor.isParked(orientation: request.edge.dockOrientation, tileSize: request.tileSize)
            : suppressor.hasDrifted()
    }

    private func repairIfDrifted() {
        guard isEnabled, let request = lastRequest, hasDrifted(from: request) else { return }
        guard Date().timeIntervalSince(lastRepair) > 30 else { return }
        lastRepair = Date()
        // Re-run the whole request: in reserved-space mode the orientation and tile size matter as
        // much as auto-hide, and something that reset one probably reset the others.
        lastRequest = nil
        apply(request)
        NSLog("Eskele: Dock preferences drifted; re-applied")
    }

    // MARK: - Termination

    /// `DispatchSource` signal handling rather than `sigaction`, precisely so the handler can do
    /// real work (writing preferences) instead of being limited to async-signal-safe calls.
    func installTerminationHandlers() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.restoreNow()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

// `atexit` takes a C function pointer and cannot capture context, so the suppressor is reachable
// through a file-scope global. DockSuppressor is internally locked, so this is safe to touch from
// whatever thread is unwinding.
private nonisolated(unsafe) var atexitSuppressor: DockSuppressor?

private func restoreDockAtExit() {
    atexitSuppressor?.restore()
}
