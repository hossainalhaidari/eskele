import Foundation

/// Spring-loading: holding a dragged file over a cell opens what the cell stands for, so the drag
/// can carry on into it — the app's window, or the folder in Finder. The system Dock does this, and
/// it is how a file reaches a mail being written or a folder two levels down.
///
/// Pure, so the rules are asserted rather than found by dragging things across the bar. The view
/// keeps one of these for the length of a drag and arms a timer whenever `hover` says to.
struct SpringLoad: Equatable {
    /// The cell under the drag, by `DockItem.id`.
    private(set) var target: String?
    /// Whether `target` has already opened. Once is enough: a cell that went on re-opening for as
    /// long as the drag rested on it would keep pulling the window back in front of the one the
    /// user is trying to reach.
    private(set) var hasSprung = false

    /// Records the cell the drag is over now, or nil for a gap or a cell that does not spring.
    ///
    /// - Returns: whether to start the delay — only on arriving at a new cell, so a drag that
    ///   wobbles inside one cell does not keep pushing the moment it opens further away.
    mutating func hover(_ id: String?) -> Bool {
        guard id != target else { return false }
        target = id
        hasSprung = false
        return id != nil
    }

    /// The delay has run out for `id`.
    ///
    /// - Returns: whether to open it — not if the drag has moved on in the meantime, or if it
    ///   already opened.
    mutating func fire(_ id: String) -> Bool {
        guard id == target, !hasSprung else { return false }
        hasSprung = true
        return true
    }

    /// The drag left the bar or ended.
    mutating func reset() {
        target = nil
        hasSprung = false
    }

    /// How long a drag has to rest on a cell, or nil when the user has switched spring-loading off.
    ///
    /// The system's own setting, under *Accessibility ▸ Pointer Control ▸ Spring-loading*, which
    /// Finder and the Dock both follow; a bar that sprang at its own pace would be the one place
    /// that ignored it. The setting is absent until somebody moves the slider, and then the Dock's
    /// default of half a second applies.
    static func delay(in defaults: UserDefaults = .standard) -> TimeInterval? {
        // `bool(forKey:)` and `double(forKey:)` rather than a cast, because they also read the
        // string a `defaults write` without a type flag leaves behind.
        let enabled = "com.apple.springing.enabled", seconds = "com.apple.springing.delay"
        return delay(
            enabled: defaults.object(forKey: enabled) == nil ? nil : defaults.bool(forKey: enabled),
            seconds: defaults.object(forKey: seconds) == nil ? nil : defaults.double(forKey: seconds))
    }

    /// The rule behind `delay(in:)`, over the two values as stored — nil where there is none.
    static func delay(enabled: Bool?, seconds: Double?) -> TimeInterval? {
        guard enabled ?? true else { return nil }
        // The slider runs from 0 to 2; anything outside that is a hand-edited value, and a drag
        // that never springs, or springs the instant it touches the bar, helps nobody.
        return min(max(seconds ?? 0.5, 0.1), 2)
    }
}

extension DockItem {
    /// Whether holding a drag over this cell opens it.
    ///
    /// A running app comes forward — and a window button raises its window — so the file can be
    /// dropped into it. A folder opens in Finder. An app that is not running does not launch:
    /// starting an app because a drag passed slowly over it is a heavy thing to do by accident,
    /// and dropping on the cell already launches it with the files. The Trash, a file, the clock
    /// and the launcher have nothing to drag into.
    var springsOpen: Bool {
        switch kind {
        case .app: isRunning
        case .window: true
        case .folder: true
        case .file, .separator, .trash, .appsMenu, .clock: false
        }
    }
}
