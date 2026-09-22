import AppKit
import Carbon.HIToolbox

/// What a key means while the bar has the keyboard (§5.27).
///
/// Pure, for the reason `ClickAction` is: which arrow runs along the bar and which opens a menu
/// swaps with the edge, and that is a table to assert rather than to find out by pressing keys on
/// three edges.
enum BarKeyCommand: Equatable {
    case previous
    case next
    case first
    case last
    /// Return or Space, with the modifiers held — read as a click with them, so ⌘Return is Show in
    /// Finder and ⇧Return is Quit, exactly as ⌘- and ⇧-click are. See `ClickAction.resolve`.
    case press(NSEvent.ModifierFlags)
    /// The cell's context menu.
    case showMenu
    /// Give the keyboard back to the app it was taken from.
    case leave
    /// Characters typed to jump to a cell by name.
    case type(String)

    /// - Parameter isTyping: a name is part-way through being typed, which is when Space is part of
    ///   it — "Google C" — rather than a press.
    static func resolve(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?,
        edge: BarEdge,
        isTyping: Bool = false
    ) -> BarKeyCommand? {
        let flags = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .shift, .option, .control])

        switch Int(keyCode) {
        case kVK_Escape:
            return flags.isEmpty ? .leave : nil
        case kVK_Space where isTyping && flags.isEmpty:
            return .type(" ")
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            // ⌃ is the context menu, as ⌃-click is. `ClickAction` refuses it outright, so it has to
            // be read here or a ⌃Return would do nothing at all.
            return flags.contains(.control) ? .showMenu : .press(flags)
        case kVK_Home:
            return flags.isEmpty ? .first : nil
        case kVK_End:
            return flags.isEmpty ? .last : nil
        case kVK_Tab:
            guard flags.isSubset(of: .shift) else { return nil }
            return flags.contains(.shift) ? .previous : .next
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            return arrow(Int(keyCode), flags: flags, edge: edge)
        default:
            return typed(characters, flags: flags)
        }
    }

    /// Along the bar, the arrows move; ⌘ with them goes to the end, as it does in a line of text.
    /// Across it, the arrow pointing into the screen opens the menu — the direction a cell's menu
    /// opens in, and what the system Dock does with the same key. The arrow pointing off the screen
    /// means nothing.
    private static func arrow(_ keyCode: Int, flags: NSEvent.ModifierFlags, edge: BarEdge) -> BarKeyCommand? {
        let (back, forward, inward) = switch edge {
        case .bottom: (kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow)
        case .left: (kVK_UpArrow, kVK_DownArrow, kVK_RightArrow)
        case .right: (kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow)
        }
        switch (keyCode, flags) {
        case (back, []): return .previous
        case (forward, []): return .next
        case (back, [.command]): return .first
        case (forward, [.command]): return .last
        case (inward, []): return .showMenu
        default: return nil
        }
    }

    /// A printable character, with nothing but ⇧ held. The arrow and function keys arrive as
    /// characters too — from the private-use block AppKit keeps for them — and are not names.
    private static func typed(_ characters: String?, flags: NSEvent.ModifierFlags) -> BarKeyCommand? {
        guard flags.isSubset(of: .shift), let characters, !characters.isEmpty else { return nil }
        let printable = characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
        return printable ? .type(characters) : nil
    }
}

/// Where the keyboard can go on the bar, and where each command takes it.
enum BarNavigation {
    /// A cell the keyboard can land on: every one but a separator, which is a gap rather than a
    /// place.
    ///
    /// Not `BarComposition.addressable`, which also leaves out the Apps Menu. That is right for the
    /// slot keys, where counting the launcher would make ⌃⌥1 mean something different on a bar
    /// without one; nothing is counted here, and a button the arrows skip is a button a keyboard
    /// cannot reach.
    static func isStop(_ item: DockItem) -> Bool { !item.isSeparator }

    /// Where the keyboard starts: the app in front, which is where the user just was, or the first
    /// cell when that app has none.
    static func entry(in items: [DockItem]) -> Int? {
        items.indices.first { isStop(items[$0]) && items[$0].isFrontmost }
            ?? items.indices.first { isStop(items[$0]) }
    }

    /// The cell a move lands on, or `nil` when there is nowhere to go.
    ///
    /// Stops at the ends rather than wrapping. On a bar the ends are places — the launcher at one,
    /// the Trash at the other — and arriving back at the start after the Trash reads as the bar
    /// having jumped rather than as having run out.
    static func target(of command: BarKeyCommand, from current: Int, in items: [DockItem]) -> Int? {
        let stops = items.indices.filter { isStop(items[$0]) }
        guard let position = stops.firstIndex(of: current) else { return stop(near: current, in: items) }
        switch command {
        case .previous: return position > 0 ? stops[position - 1] : nil
        case .next: return position + 1 < stops.count ? stops[position + 1] : nil
        case .first: return stops.first == current ? nil : stops.first
        case .last: return stops.last == current ? nil : stops.last
        default: return nil
        }
    }

    /// The cell to move to when the one the keyboard was on has gone — quit, or unpinned from under
    /// it: whatever now stands in its place, or the last cell if the bar got shorter than that.
    static func stop(near index: Int, in items: [DockItem]) -> Int? {
        items.indices.first { $0 >= index && isStop(items[$0]) }
            ?? items.indices.last { isStop(items[$0]) }
    }

    /// The cell whose name starts with what has been typed, looking onward from `current`.
    ///
    /// A second character refines the name being typed, so the cell already reached counts if it
    /// still matches. A first character — or the same one again and again — steps to the next name
    /// starting with it, so repeating a letter walks through every app that starts with it.
    ///
    /// - Parameter labels: each cell's name, aligned with the bar; `nil` for one that has none.
    static func match(_ typed: String, labels: [String?], from current: Int) -> Int? {
        guard !typed.isEmpty else { return nil }
        if typed.count > 1, let hit = search(typed, labels: labels, from: current) { return hit }
        let repeated = Set(typed.lowercased()).count == 1
        guard typed.count == 1 || repeated else { return nil }
        return search(String(typed.prefix(1)), labels: labels, from: current + 1)
    }

    private static func search(_ prefix: String, labels: [String?], from start: Int) -> Int? {
        guard !labels.isEmpty else { return nil }
        for offset in 0..<labels.count {
            let index = (start + offset) % labels.count
            guard let label = labels[index] else { continue }
            let options: String.CompareOptions = [.anchored, .caseInsensitive, .diacriticInsensitive]
            if label.range(of: prefix, options: options) != nil { return index }
        }
        return nil
    }
}
