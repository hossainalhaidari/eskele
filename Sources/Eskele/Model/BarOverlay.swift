import AppKit

/// What the bar draws over its cells while a modifier chord is held down.
///
/// Both overlays answer a question about the whole bar at once — "which key is this one?", "what is
/// eating the battery?" — so they are held rather than clicked, and only one can be up at a time.
enum BarOverlay: String, CaseIterable, Equatable, Sendable {
    /// The slot keys' chord, ⌃⌥ unless changed: the number each of the first ten cells answers to.
    case slotNumbers
    /// ⇧⌥: processor and memory use, per app.
    case activity

    static let activityChord: NSEvent.ModifierFlags = [.shift, .option]
    static let activityChordName = "⇧⌥"

    /// The chord each switched-on overlay answers to.
    ///
    /// The slot numbers answer to whatever the slot keys are held with. The overlay's whole job is
    /// to say which number goes with which cell, so holding the keys you are about to press has to
    /// be what shows it — a fixed ⌃⌥ beside ⌃⌘ slot keys would be a hint for keys that do nothing.
    /// No `SlotChord` is ⇧⌥, so the two never compete for a chord.
    static func chords(for settings: Settings) -> [BarOverlay: NSEvent.ModifierFlags] {
        var chords: [BarOverlay: NSEvent.ModifierFlags] = [:]
        if settings.slotHotKeysEnabled { chords[.slotNumbers] = settings.slotChord.modifiers.eventFlags }
        if settings.activityOverlayEnabled { chords[.activity] = activityChord }
        return chords
    }

    /// Flags that take part in a chord. Caps Lock, Fn and the numeric-pad bit ride along on ordinary
    /// events and are none of a chord's business.
    static let considered: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    /// The overlay a set of held modifiers asks for, among the ones in `chords`.
    ///
    /// Matched exactly. ⌃⌥⌘ is a different chord from ⌃⌥, and lighting the bar up for it would
    /// promise a gesture that does nothing — worse, ⇧⌥ overlapping a *click* modifier is precisely
    /// how a "just looking" gesture would quit an app, so the chords are checked whole.
    static func matching(
        _ modifiers: NSEvent.ModifierFlags, chords: [BarOverlay: NSEvent.ModifierFlags]
    ) -> BarOverlay? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask).intersection(considered)
        guard !flags.isEmpty else { return nil }
        return allCases.first { chords[$0] == flags }
    }
}
