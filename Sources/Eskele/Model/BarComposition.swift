import CoreGraphics
import Foundation

/// How the bar's contents are grouped, and in what order the groups are laid out.
///
/// Split out of `DockModel.rebuild` because it is the part with rules rather than plumbing: three
/// buckets, two item styles, and a divider that must appear only when it separates something.
enum BarComposition {
    struct Groups: Equatable {
        /// Pinned things that are not currently a task — shortcuts, drawn compact.
        var pins: [DockItem] = []
        /// Running apps, and the separators the user placed among the pinned ones.
        var tasks: [DockItem] = []
        /// Pinned folders and files, which sit after the apps and before the Trash.
        var trailing: [DockItem] = []
    }

    /// Sorts the resolved pinned items into groups.
    ///
    /// With `groupsPins` off — an icons-only bar — nothing is hoisted: a launcher and a task are
    /// drawn identically there, so separating them would only move icons around for no reason. With
    /// it on, a pinned app that is not running is a shortcut rather than a task, and a shortcut
    /// stranded among labelled buttons reads as a button that has lost its label.
    static func groups(for items: [DockItem], groupsPins: Bool) -> Groups {
        var groups = Groups()
        for item in items {
            switch item.kind {
            case .app:
                if groupsPins && !item.isRunning {
                    groups.pins.append(pin(item))
                } else {
                    groups.tasks.append(item)
                }
            case .separator:
                if groupsPins { groups.pins.append(item) } else { groups.tasks.append(item) }
            case .folder, .file:
                if groupsPins { groups.pins.append(pin(item)) } else { groups.trailing.append(item) }
            case .trash, .appsMenu, .window, .clock:
                break
            }
        }
        return groups
    }

    /// The finished strip: launcher, pins, divider, tasks, pinned files, Trash.
    ///
    /// The divider only appears where it has something on both sides of it — a bar of nothing but
    /// pins, or nothing but tasks, should not grow a stray line at one end.
    static func strip(leading: [DockItem], groups: Groups, trailing: [DockItem]) -> [DockItem] {
        var result = leading
        result.append(contentsOf: groups.pins)
        if !groups.pins.isEmpty && !groups.tasks.isEmpty {
            result.append(DockItem(kind: .separator(DockItem.pinDividerToken)))
        }
        result.append(contentsOf: groups.tasks)
        result.append(contentsOf: groups.trailing)
        result.append(contentsOf: trailing)
        return result
    }

    /// Reorders one run of tasks.
    ///
    /// Stable by construction rather than by hope: `sorted(by:)` gives no stability guarantee, so
    /// every comparison falls back to the item's existing position. Without that, two apps with the
    /// same name — or the whole run under `.launch`, where nothing that is closed has a date —
    /// would shuffle between rebuilds for no reason the user could see.
    ///
    /// Separators are dropped rather than sorted. A divider earns its place by sitting between two
    /// things the user put on either side of it; once the order is the machine's, it is a line
    /// between two arbitrary neighbours. They stay in `layout.json` and come back with `.manual`.
    static func sorted(_ items: [DockItem], by order: SortOrder) -> [DockItem] {
        guard order != .manual else { return items }
        return items
            .filter { !$0.isSeparator }
            .enumerated()
            .sorted { left, right in
                switch order {
                case .manual:
                    return left.offset < right.offset
                case .alphabetical:
                    let comparison = left.element.displayName.localizedStandardCompare(
                        right.element.displayName)
                    if comparison != .orderedSame { return comparison == .orderedAscending }
                case .launch:
                    // An app that is not running has no launch time; those keep their stored order
                    // and follow everything that does.
                    switch (left.element.launchDate, right.element.launchDate) {
                    case let (l?, r?) where l != r: return l < r
                    case (nil, .some): return false
                    case (.some, nil): return true
                    default: break
                    }
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    /// The strip as one display's bar shows it, under `ScreenMode.perDisplay`.
    ///
    /// Only tasks are filtered. The launcher, the pins, the Trash and the clock carry no display and
    /// so appear on every bar — a shortcut is not on a display the way a window is, and a second bar
    /// without a launcher on it would be a worse bar.
    static func onDisplay(_ items: [DockItem], _ display: CGDirectDisplayID) -> [DockItem] {
        var kept = items.filter { $0.displays.isEmpty || $0.displays.contains(display) }
        // The divider the bar inserts for itself earns its place by having tasks on the far side of
        // it. On a display where none of them landed it is a line at the end of the pins.
        if let divider = kept.firstIndex(where: \.isImplicitSeparator),
           !kept[(divider + 1)...].contains(where: \.isTask) {
            kept.remove(at: divider)
        }
        return kept
    }

    /// The cells a positional hot key can address, in bar order.
    ///
    /// Two things are skipped: a separator, which is a gap rather than a place, and the launcher,
    /// which is always at the leading end and would otherwise make ⌃⌥1 mean "open the Apps Menu"
    /// on one bar and "activate Safari" on another. So ⌃⌥1 is the first *thing* on the bar, which
    /// is what a user counting icons would point at.
    static func addressable(_ items: [DockItem]) -> [DockItem] {
        items.filter { !$0.isSeparator && !$0.isAppsMenu }
    }

    /// The slot each item answers to, aligned one-for-one with `items`, and `nil` for the cells no
    /// key addresses — the launcher, the separators, and everything past the tenth.
    ///
    /// The same rule as `addressable`, expressed per position, so the bar can label its cells
    /// without having to work out which of them the filter dropped.
    static func slotNumbers(for items: [DockItem], limit: Int) -> [Int?] {
        var next = 0
        return items.map { item in
            guard !item.isSeparator, !item.isAppsMenu, next < limit else { return nil }
            defer { next += 1 }
            return next
        }
    }

    private static func pin(_ item: DockItem) -> DockItem {
        var pin = item
        pin.isPinLauncher = true
        return pin
    }
}
