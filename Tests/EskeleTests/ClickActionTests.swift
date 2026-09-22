import AppKit
import Testing
@testable import Eskele

private let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
private let ref = AppRef(bundleID: "com.apple.finder", url: finder, name: "Finder")

private let appItem = DockItem(kind: .app(ref), isPinned: true, isRunning: true)
private let windowItem = DockItem(
    kind: .window(ref, WindowRef(pid: 1, title: "Downloads", isMinimized: false)),
    isRunning: true)
private let folderItem = DockItem(kind: .folder(finder), isPinned: true)
private let trashItem = DockItem(kind: .trash(isEmpty: true))
private let launcherItem = DockItem(kind: .appsMenu)
private let separatorItem = DockItem(kind: .separator("x"), isPinned: true)

private func resolve(
    _ modifiers: NSEvent.ModifierFlags = [],
    button: ClickAction.Button = .primary,
    on item: DockItem = appItem
) -> ClickAction? {
    ClickAction.resolve(modifiers: modifiers, button: button, for: item)
}

// MARK: - The table

@Test func aPlainClickActivatesWhateverItLandsOn() {
    #expect(resolve() == .activate)
    #expect(resolve(on: folderItem) == .activate)
    #expect(resolve(on: trashItem) == .activate)
    #expect(resolve(on: launcherItem) == .activate)
}

@Test func theModifiersEachMeanOneThing() {
    #expect(resolve(.command) == .revealInFinder)
    #expect(resolve(.option) == .toggleHide)
    #expect(resolve([.option, .command]) == .showOnly)
    #expect(resolve(.shift) == .quit)
    #expect(resolve([.shift, .command]) == .forceRelaunch)
}

/// ⇧ and the middle button both mean "get rid of this". On a window that is closing the window, not
/// quitting the app it happens to belong to — the whole point of a per-window button.
@Test func gettingRidOfAWindowClosesItRatherThanItsApp() {
    #expect(resolve(.shift, on: windowItem) == .closeWindow)
    #expect(resolve(button: .middle, on: windowItem) == .closeWindow)
    #expect(resolve(.shift, on: appItem) == .quit)
    #expect(resolve(button: .middle, on: appItem) == .quit)
}

/// Modifiers held with the middle button do not change what it does, so a stray ⇧ cannot turn a
/// close into a relaunch.
@Test func theMiddleButtonIgnoresModifiers() {
    #expect(resolve([.shift, .command], button: .middle) == .quit)
    #expect(resolve(.option, button: .middle) == .quit)
}

// MARK: - Cells the gestures do not apply to

/// Quitting a folder, hiding the Trash and relaunching a separator are all nonsense. Doing nothing
/// is the only honest reading — a fallback to `.activate` would open things the user never asked to
/// open.
@Test func theAppOnlyGesturesDoNothingElsewhere() {
    for item in [folderItem, trashItem, launcherItem, separatorItem] {
        #expect(resolve(.option, on: item) == nil)
        #expect(resolve([.option, .command], on: item) == nil)
        #expect(resolve(.shift, on: item) == nil)
        #expect(resolve([.shift, .command], on: item) == nil)
        #expect(resolve(button: .middle, on: item) == nil)
    }
}

/// ⌘-click needs somewhere to go. A folder and the Trash both have one; the launcher and a
/// separator do not, and revealing "nothing" used to mean opening the Trash.
@Test func revealOnlyAppliesWhereThereIsSomethingToReveal() {
    #expect(resolve(.command, on: folderItem) == .revealInFinder)
    #expect(resolve(.command, on: trashItem) == .revealInFinder)
    #expect(resolve(.command, on: launcherItem) == nil)
    #expect(resolve(.command, on: separatorItem) == nil)
}

// MARK: - What must not be read as something else

/// ⌃ opens the context menu at mouse-down and never reaches this table. It is rejected rather than
/// masked off, so ⌃⌘ can never arrive here and be served as a plain ⌘.
@Test func controlIsNeverPartOfAClick() {
    #expect(resolve(.control) == nil)
    #expect(resolve([.control, .command]) == nil)
    #expect(resolve([.control, .option]) == nil)
}

/// Caps Lock, Fn and the numeric-pad flag ride along on ordinary events; none of them is a chord.
@Test func irrelevantFlagsAreIgnored() {
    #expect(resolve(.capsLock) == .activate)
    #expect(resolve([.function, .numericPad]) == .activate)
    #expect(resolve([.command, .capsLock]) == .revealInFinder)
}

/// An unassigned chord does nothing rather than falling through to the plain click, which would
/// launch or hide an app on a mis-hit.
@Test func anUnassignedCombinationIsNotAPlainClick() {
    #expect(resolve([.shift, .option]) == nil)
    #expect(resolve([.shift, .option, .command]) == nil)
}
