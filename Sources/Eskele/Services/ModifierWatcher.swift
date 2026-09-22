import AppKit

/// Reports which overlay chord is being held right now, so the bar can label or annotate its cells.
///
/// Polled rather than observed. `NSEvent.addGlobalMonitorForEvents` delivers `.flagsChanged` only to
/// a process trusted for Accessibility, and neither overlay needs a permission of any kind — a
/// Carbon hot key never has, and `proc_pid_rusage` answers for any process the same user owns.
/// Making the hint for permission-free features depend on a permission would be the wrong way round,
/// so this reads `NSEvent.modifierFlags`, which is a local query rather than an event stream. The
/// timer exists only while at least one overlay is switched on.
@MainActor
final class ModifierWatcher {
    /// Called only when the answer changes, so a held key does not redraw the bar ten times a second.
    var onChange: ((BarOverlay?) -> Void)?
    private(set) var held: BarOverlay?

    private var poll: Poll?
    private var chords: [BarOverlay: NSEvent.ModifierFlags] = [:]

    /// Quick enough that the overlay seems to be already there when you look down, slow enough to be
    /// nothing on a battery.
    private static let interval: TimeInterval = 0.08

    /// The switched-on overlays and the chord each answers to — `BarOverlay.chords(for:)`.
    func setChords(_ chords: [BarOverlay: NSEvent.ModifierFlags]) {
        self.chords = chords
        // A chord that has just been switched off, or moved, must not stay on screen.
        if let held, chords[held] == nil { update(nil) }
        if poll != nil { sample() }

        guard chords.isEmpty == (poll != nil) else { return }
        guard !chords.isEmpty else {
            poll?.invalidate()
            poll = nil
            update(nil)
            return
        }
        // Not stretched in Low Power Mode: whoever is holding the chord is waiting on it.
        poll = Poll(
            every: ModifierWatcher.interval, tolerance: ModifierWatcher.interval / 2,
            stretchesInLowPowerMode: false
        ) { [weak self] in self?.sample() }
    }

    private func sample() {
        update(BarOverlay.matching(NSEvent.modifierFlags, chords: chords))
    }

    private func update(_ overlay: BarOverlay?) {
        guard overlay != held else { return }
        held = overlay
        onChange?(overlay)
    }
}
