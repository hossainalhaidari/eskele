import AppKit

/// What a click on a cell means once its modifiers are read.
///
/// Pure, and kept out of the view, because the table is worth asserting rather than discovering by
/// holding keys down: six combinations, two of which differ by a single flag, and two of which do
/// different things to an app than to one of its windows. The combinations are uBar's, so that
/// muscle memory carries across.
enum ClickAction: Equatable {
    /// The plain click: launch, bring forward, cycle or hide, per `ActivationPolicy`.
    case activate
    case revealInFinder
    /// Hide the app, or bring it back when it is already hidden.
    case toggleHide
    /// Bring this app forward and hide every other one.
    case showOnly
    /// Ask the app to quit, so it can still object — an unsaved document is not ours to discard.
    case quit
    /// Kill it and start it again. `forceTerminate`, because the state you are in when you want
    /// this is one where asking politely has already failed.
    case forceRelaunch
    /// Close one window without disturbing the rest of its app.
    case closeWindow

    enum Button {
        case primary
        case middle
    }

    /// - Returns: `nil` when the gesture means nothing on this cell — a ⇧-click on a separator has
    ///   no sensible reading, and guessing one is worse than doing nothing.
    ///
    /// ⌃ never arrives here: `ItemView` treats it as a request for the context menu at mouse-down,
    /// the way the rest of macOS does. It is rejected anyway rather than being quietly ignored,
    /// so a future caller cannot make ⌃⌘ mean ⌘ by accident.
    static func resolve(
        modifiers: NSEvent.ModifierFlags,
        button: Button = .primary,
        for item: DockItem
    ) -> ClickAction? {
        let flags = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .shift, .option, .control])
        guard !flags.contains(.control) else { return nil }

        // The middle button is a shorthand for "get rid of this", whatever is held down with it.
        if button == .middle {
            guard item.isTask else { return nil }
            return item.isWindow ? .closeWindow : .quit
        }

        if flags.isEmpty { return .activate }
        if flags == [.command] { return item.canRevealInFinder ? .revealInFinder : nil }

        // Everything below acts on a running program, so it means nothing on a folder, a file, the
        // Trash or the launcher.
        guard item.isTask else { return nil }
        if flags == [.option] { return .toggleHide }
        if flags == [.option, .command] { return .showOnly }
        if flags == [.shift] { return item.isWindow ? .closeWindow : .quit }
        if flags == [.shift, .command] { return .forceRelaunch }
        return nil
    }

    /// What the modifier-clicks do on `item`, in the order the gestures are listed.
    ///
    /// For VoiceOver, which presses a cell but cannot hold a modifier while it does: these become
    /// the cell's actions, and two of them — Show Only This and the force relaunch — are on no menu,
    /// so without this a VoiceOver user could not reach them at all. Derived from `resolve` rather
    /// than listed, so the two cannot drift apart.
    static func alternatives(for item: DockItem) -> [ClickAction] {
        let gestures: [NSEvent.ModifierFlags] = [
            [.command], [.option], [.option, .command], [.shift], [.shift, .command],
        ]
        return gestures.compactMap { resolve(modifiers: $0, for: item) }
    }

    /// The action's name, as a menu would give it.
    func title(for item: DockItem) -> String {
        switch self {
        case .activate:
            String(localized: "Open", comment: "Action: open, or bring forward, what the cell stands for")
        case .revealInFinder:
            String(localized: "Show in Finder", comment: "Menu item: reveal this item in Finder")
        case .toggleHide:
            item.isHidden
                ? String(localized: "Show", comment: "Menu item: unhide this app's windows")
                : String(localized: "Hide", comment: "Menu item: hide this app's windows")
        case .showOnly:
            String(localized: "Show Only This", comment: "Action: bring this app forward and hide every other one")
        case .quit:
            String(localized: "Quit", comment: "Menu item: quit this app")
        case .forceRelaunch:
            String(localized: "Force Quit and Relaunch", comment: "Action: kill the app and start it again")
        case .closeWindow:
            String(localized: "Close", comment: "Menu item: close this window")
        }
    }
}
