import CoreGraphics
import Foundation
import Testing
@testable import Eskele

private let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

private func app(_ name: String, running: Bool) -> DockItem {
    DockItem(
        kind: .app(AppRef(bundleID: "test.\(name)", url: finder, name: name)),
        isPinned: true,
        isRunning: running)
}

private func names(_ items: [DockItem]) -> [String] {
    items.map { $0.isSeparator ? "|" : $0.displayName }
}

private func task(_ name: String, on displays: Set<CGDirectDisplayID>) -> DockItem {
    var item = app(name, running: true)
    item.displays = displays
    return item
}

// MARK: - Per-display filtering

/// The whole point of the mode: a display's bar lists the apps whose windows are on it.
@Test func eachDisplayKeepsOnlyItsOwnTasks() {
    let items = [task("Safari", on: [1]), task("Mail", on: [2]), task("Notes", on: [1, 2])]

    #expect(names(BarComposition.onDisplay(items, 1)) == ["Safari", "Notes"])
    #expect(names(BarComposition.onDisplay(items, 2)) == ["Mail", "Notes"])
}

/// Everything that is not a task carries no display, and belongs on every bar.
@Test func shortcutsAndTheTrashStayOnEveryBar() {
    let items = BarComposition.strip(
        leading: [DockItem(kind: .appsMenu)],
        groups: BarComposition.Groups(
            pins: [app("Safari", running: false)], tasks: [task("Mail", on: [2])]),
        trailing: [DockItem(kind: .trash(isEmpty: true)), DockItem(kind: .clock)])

    #expect(names(BarComposition.onDisplay(items, 2)) == ["Apps", "Safari", "|", "Mail", "Trash", "Clock"])
    // Display 1 has none of the tasks, so the divider has nothing left to divide.
    #expect(names(BarComposition.onDisplay(items, 1)) == ["Apps", "Safari", "Trash", "Clock"])
}

/// A user's own separator sits among the pins, which are never filtered, so it is left alone.
@Test func aUserSeparatorSurvivesTheFilter() {
    let items = [
        app("Safari", running: false),
        DockItem(kind: .separator("mine"), isPinned: true),
        app("Notes", running: false),
        task("Mail", on: [2]),
    ]
    #expect(names(BarComposition.onDisplay(items, 1)) == ["Safari", "|", "Notes"])
}

/// A task nobody could place — no Accessibility, nothing open, a Space we cannot reach — is shown
/// everywhere rather than nowhere. Losing an app off every bar is the one outcome worth ruling out.
@Test func anUnplaceableTaskIsShownOnEveryBar() {
    let items = [task("Safari", on: []), task("Mail", on: [2])]
    #expect(names(BarComposition.onDisplay(items, 1)) == ["Safari"])
    #expect(names(BarComposition.onDisplay(items, 2)) == ["Safari", "Mail"])
}

// MARK: - Icons-only mode is untouched

/// The pin group is a labelled-mode idea. An icons-only bar draws a launcher and a task the same
/// way, so hoisting one would move icons about for nothing.
@Test func compactModeLeavesEveryPinnedItemWhereTheUserPutIt() {
    let items = [app("Safari", running: false), app("Mail", running: true), app("Notes", running: false)]
    let groups = BarComposition.groups(for: items, groupsPins: false)

    #expect(groups.pins.isEmpty)
    #expect(names(groups.tasks) == ["Safari", "Mail", "Notes"])
    #expect(groups.tasks.allSatisfy { !$0.isPinLauncher })
}

@Test func compactModeKeepsPinnedFoldersAfterTheApps() {
    let items = [app("Mail", running: true), DockItem(kind: .folder(finder), isPinned: true)]
    let groups = BarComposition.groups(for: items, groupsPins: false)

    #expect(names(groups.tasks) == ["Mail"])
    #expect(names(groups.trailing) == ["Finder.app"])
}

// MARK: - Labelled mode groups the launchers

/// The point of the change: with labels on, a pinned app that is not running is a shortcut, and
/// shortcuts belong together at the leading end rather than in among the buttons.
@Test func labelledModeHoistsPinnedAppsThatAreNotRunning() {
    let items = [app("Safari", running: false), app("Mail", running: true), app("Notes", running: false)]
    let groups = BarComposition.groups(for: items, groupsPins: true)

    #expect(names(groups.pins) == ["Safari", "Notes"])
    #expect(names(groups.tasks) == ["Mail"])
}

@Test func aHoistedPinIsMarkedAsALauncher() {
    let groups = BarComposition.groups(for: [app("Safari", running: false)], groupsPins: true)
    #expect(groups.pins.allSatisfy { $0.isPinLauncher })
}

/// A pinned app that *is* running is a task, and gets its labelled button like any other.
@Test func aRunningPinnedAppStaysInTheTaskRun() {
    let groups = BarComposition.groups(for: [app("Mail", running: true)], groupsPins: true)
    #expect(groups.pins.isEmpty)
    #expect(names(groups.tasks) == ["Mail"])
    #expect(!groups.tasks[0].isPinLauncher)
}

@Test func labelledModePutsPinnedFilesAndFoldersInThePinGroupToo() {
    let items = [DockItem(kind: .folder(finder), isPinned: true), app("Mail", running: true)]
    let groups = BarComposition.groups(for: items, groupsPins: true)

    #expect(names(groups.pins) == ["Finder.app"])
    #expect(groups.trailing.isEmpty)
}

// MARK: - Assembly

@Test func theDividerSeparatesThePinsFromTheTasks() {
    let groups = BarComposition.groups(
        for: [app("Safari", running: false), app("Mail", running: true)], groupsPins: true)
    let strip = BarComposition.strip(leading: [], groups: groups, trailing: [])

    #expect(names(strip) == ["Safari", "|", "Mail"])
    #expect(strip[1].isImplicitSeparator)
}

/// A divider with nothing on one side of it is a stray line at the end of the bar.
@Test func thereIsNoDividerWhenOnlyOneGroupHasAnything() {
    let onlyPins = BarComposition.groups(for: [app("Safari", running: false)], groupsPins: true)
    #expect(names(BarComposition.strip(leading: [], groups: onlyPins, trailing: [])) == ["Safari"])

    let onlyTasks = BarComposition.groups(for: [app("Mail", running: true)], groupsPins: true)
    #expect(names(BarComposition.strip(leading: [], groups: onlyTasks, trailing: [])) == ["Mail"])
}

@Test func theLauncherLeadsAndTheTrashTrails() {
    let groups = BarComposition.groups(
        for: [app("Safari", running: false), app("Mail", running: true)], groupsPins: true)
    let strip = BarComposition.strip(
        leading: [DockItem(kind: .appsMenu)],
        groups: groups,
        trailing: [DockItem(kind: .trash(isEmpty: true))])

    #expect(strip.first?.isAppsMenu == true)
    #expect(strip.last?.isTrash == true)
}

/// The bar's own divider has no stored counterpart, so it must not offer to remove itself the way
/// a separator the user added does.
@Test func onlyTheBarsOwnDividerIsImplicit() {
    #expect(DockItem(kind: .separator(DockItem.pinDividerToken)).isImplicitSeparator)
    #expect(!DockItem(kind: .separator("user-added")).isImplicitSeparator)
}

// MARK: - What the positional hot keys address

/// ⌃⌥1 has to mean the same kind of thing on every bar. The launcher is always at the leading end,
/// so counting it would make ⌃⌥1 "open the Apps Menu" for anyone who has it on and "activate the
/// first app" for anyone who does not.
@Test func slotsSkipTheLauncherAndTheSeparators() {
    let strip = BarComposition.strip(
        leading: [DockItem(kind: .appsMenu)],
        groups: BarComposition.Groups(
            pins: [app("Safari", running: false)],
            tasks: [app("Mail", running: true), app("Notes", running: true)]),
        trailing: [DockItem(kind: .trash(isEmpty: true))])

    // The strip itself carries the launcher and the divider the pin group earns.
    #expect(names(strip) == ["Apps", "Safari", "|", "Mail", "Notes", "Trash"])
    #expect(names(BarComposition.addressable(strip)) == ["Safari", "Mail", "Notes", "Trash"])
}

/// A user-placed divider is a gap, not a position — numbering it would shift every app after it by
/// one for a cell that cannot be activated.
@Test func aUserPlacedSeparatorTakesNoSlot() {
    let items = [
        app("Mail", running: true),
        DockItem(kind: .separator("user"), isPinned: true),
        app("Notes", running: true),
    ]
    #expect(names(BarComposition.addressable(items)) == ["Mail", "Notes"])
}

@Test func slotsAreEmptyWhenTheBarHasNothingOnIt() {
    #expect(BarComposition.addressable([]).isEmpty)
    #expect(BarComposition.addressable([DockItem(kind: .appsMenu)]).isEmpty)
}

// MARK: - Numbering the cells for the hint overlay

/// The overlay and the keys have to agree, or the bar tells you to press a number that does
/// something else. Both come from the same rule; this pins them together.
@Test func theNumbersDrawnMatchTheKeysThatFire() {
    let strip = BarComposition.strip(
        leading: [DockItem(kind: .appsMenu)],
        groups: BarComposition.Groups(
            pins: [app("Safari", running: false)],
            tasks: [app("Mail", running: true), app("Notes", running: true)]),
        trailing: [DockItem(kind: .trash(isEmpty: true))])

    let slots = BarComposition.slotNumbers(for: strip, limit: 10)
    let addressable = BarComposition.addressable(strip)
    for (index, slot) in slots.enumerated() {
        guard let slot else { continue }
        #expect(strip[index].id == addressable[slot].id)
    }
    #expect(slots == [nil, 0, nil, 1, 2, 3])
}

/// A bar filtered by display draws the strip's numbers, not a second set of its own — the keys are
/// global, so a bar showing half the tasks has to show gaps rather than renumber them 1, 2, 3.
@Test func aFilteredBarKeepsTheStripsNumbering() {
    var strip = BarComposition.strip(
        leading: [DockItem(kind: .appsMenu)],
        groups: BarComposition.Groups(
            tasks: [task("Safari", on: [1]), task("Mail", on: [2]), task("Notes", on: [1])]),
        trailing: [])
    for (index, slot) in BarComposition.slotNumbers(for: strip, limit: 10).enumerated() {
        strip[index].slotNumber = slot
    }

    let second = BarComposition.onDisplay(strip, 2)
    #expect(names(second) == ["Apps", "Mail"])
    #expect(second.map(\.slotNumber) == [nil, 1])

    let first = BarComposition.onDisplay(strip, 1)
    #expect(first.map(\.slotNumber) == [nil, 0, 2])
}

/// The eleventh cell has no key, so it must not wear a number.
@Test func nothingPastTheTenthIsNumbered() {
    let items = (0..<14).map { app("App\($0)", running: true) }
    let slots = BarComposition.slotNumbers(for: items, limit: 10)
    #expect(slots.prefix(10).allSatisfy { $0 != nil })
    #expect(slots.suffix(4).allSatisfy { $0 == nil })
    #expect(slots[9] == 9)
}

/// ⌃⌥0 is the tenth slot, and the chip has to say "0" — the key you press — not "10".
@Test func theTenthSlotIsLabelledZero() {
    #expect(GlobalHotKey.slotLabel(0) == "1")
    #expect(GlobalHotKey.slotLabel(8) == "9")
    #expect(GlobalHotKey.slotLabel(9) == "0")
    #expect(GlobalHotKey.slotCount == 10)
}
