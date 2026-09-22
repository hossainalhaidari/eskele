import AppKit
import Carbon.HIToolbox
import Testing
@testable import Eskele

private func command(
    _ keyCode: Int,
    _ modifiers: NSEvent.ModifierFlags = [],
    characters: String? = nil,
    edge: BarEdge = .bottom,
    isTyping: Bool = false
) -> BarKeyCommand? {
    BarKeyCommand.resolve(
        keyCode: UInt16(keyCode), modifiers: modifiers, characters: characters, edge: edge, isTyping: isTyping)
}

private func named(_ name: String, frontmost: Bool = false) -> DockItem {
    DockItem(
        kind: .app(AppRef(bundleID: "test.\(name)", url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name)),
        isPinned: true, isRunning: true, isFrontmost: frontmost)
}

private let separator = DockItem(kind: .separator("s"), isPinned: true)

// MARK: - Keys

@Test func theArrowsAlongABottomBarMoveAndTheOneIntoTheScreenOpensTheMenu() {
    #expect(command(kVK_LeftArrow) == .previous)
    #expect(command(kVK_RightArrow) == .next)
    #expect(command(kVK_UpArrow) == .showMenu)
    // Pointing off the screen means nothing.
    #expect(command(kVK_DownArrow) == nil)
}

/// On a side bar the long axis is vertical, and "into the screen" points away from the edge.
@Test func theArrowsTurnWithTheEdge() {
    #expect(command(kVK_UpArrow, edge: .left) == .previous)
    #expect(command(kVK_DownArrow, edge: .left) == .next)
    #expect(command(kVK_RightArrow, edge: .left) == .showMenu)
    #expect(command(kVK_LeftArrow, edge: .left) == nil)

    #expect(command(kVK_UpArrow, edge: .right) == .previous)
    #expect(command(kVK_DownArrow, edge: .right) == .next)
    #expect(command(kVK_LeftArrow, edge: .right) == .showMenu)
    #expect(command(kVK_RightArrow, edge: .right) == nil)
}

/// ⌘ with an arrow goes to the end, as it does in a line of text; Home and End do too.
@Test func theEndsAreOneKeyAway() {
    #expect(command(kVK_LeftArrow, .command) == .first)
    #expect(command(kVK_RightArrow, .command) == .last)
    #expect(command(kVK_DownArrow, .command, edge: .right) == .last)
    #expect(command(kVK_Home) == .first)
    #expect(command(kVK_End) == .last)
    // Arrow keys arrive carrying the numeric-pad and function bits; they are no modifier of ours.
    #expect(command(kVK_RightArrow, [.numericPad, .function]) == .next)
    #expect(command(kVK_RightArrow, .option) == nil)
}

/// Return is a click, and reads its modifiers as a click would — ⌘Return is ⌘-click.
@Test func returnIsAClickWithItsModifiers() {
    #expect(command(kVK_Return) == .press([]))
    #expect(command(kVK_ANSI_KeypadEnter) == .press([]))
    #expect(command(kVK_Space) == .press([]))
    #expect(command(kVK_Return, [.shift, .command]) == .press([.shift, .command]))
    // ⌃ is the menu, as ⌃-click is — `ClickAction` refuses it, so it could not mean anything else.
    #expect(command(kVK_Return, .control) == .showMenu)
    #expect(command(kVK_Return, [.control, .option]) == .showMenu)
}

@Test func escapeLeavesAndTabMoves() {
    #expect(command(kVK_Escape) == .leave)
    #expect(command(kVK_Escape, .shift) == nil)
    #expect(command(kVK_Tab) == .next)
    #expect(command(kVK_Tab, .shift) == .previous)
    #expect(command(kVK_Tab, .option) == nil)
}

@Test func lettersAreANameBeingTyped() {
    #expect(command(kVK_ANSI_S, characters: "s") == .type("s"))
    #expect(command(kVK_ANSI_S, .shift, characters: "S") == .type("S"))
    // ⌘ and ⌥ letters are shortcuts and accents, not names.
    #expect(command(kVK_ANSI_S, .command, characters: "s") == nil)
    #expect(command(kVK_ANSI_E, .option, characters: "´") == nil)
    // A function key arrives as a character from AppKit's private-use block.
    #expect(command(kVK_F5, characters: "\u{F708}") == nil)
}

/// Mid-name, Space is part of the name — "Google C" — rather than a press.
@Test func spaceContinuesANameBeingTyped() {
    #expect(command(kVK_Space, characters: " ", isTyping: true) == .type(" "))
    #expect(command(kVK_Space, characters: " ", isTyping: false) == .press([]))
}

// MARK: - Where the keyboard goes

/// Separators are gaps. The Apps Menu is a button — unlike for the slot keys, which skip it.
@Test func everyCellButASeparatorIsAStop() {
    let items = [DockItem(kind: .appsMenu), named("A"), separator, named("B")]
    #expect(BarNavigation.target(of: .next, from: 0, in: items) == 1)
    #expect(BarNavigation.target(of: .next, from: 1, in: items) == 3)
    #expect(BarNavigation.target(of: .previous, from: 3, in: items) == 1)
    #expect(BarNavigation.target(of: .previous, from: 1, in: items) == 0)
    #expect(BarComposition.addressable(items).count == 2)
}

/// The ends are places; running off one does not come back round the other.
@Test func movingStopsAtTheEnds() {
    let items = [named("A"), named("B"), named("C")]
    #expect(BarNavigation.target(of: .previous, from: 0, in: items) == nil)
    #expect(BarNavigation.target(of: .next, from: 2, in: items) == nil)
    #expect(BarNavigation.target(of: .first, from: 2, in: items) == 0)
    #expect(BarNavigation.target(of: .last, from: 0, in: items) == 2)
    #expect(BarNavigation.target(of: .first, from: 0, in: items) == nil)
}

@Test func theKeyboardArrivesOnTheAppInFront() {
    let items = [DockItem(kind: .appsMenu), named("A"), named("B", frontmost: true)]
    #expect(BarNavigation.entry(in: items) == 2)
    #expect(BarNavigation.entry(in: [separator, named("A"), named("B")]) == 1)
    #expect(BarNavigation.entry(in: [separator]) == nil)
}

/// After the cell the keyboard was on goes away: whatever now stands there, or the last cell.
@Test func aVanishedCellHandsOverToItsNeighbour() {
    let items = [named("A"), separator, named("C")]
    #expect(BarNavigation.stop(near: 1, in: items) == 2)
    #expect(BarNavigation.stop(near: 5, in: items) == 2)
    #expect(BarNavigation.stop(near: 0, in: []) == nil)
}

// MARK: - Typing a name

private let labels: [String?] = ["Apps", "Safari", nil, "Slack", "Mail", "Škoda"]

@Test func aLetterStepsToTheNextNameStartingWithIt() {
    #expect(BarNavigation.match("s", labels: labels, from: 0) == 1)
    #expect(BarNavigation.match("s", labels: labels, from: 1) == 3)
    // Round the end and back.
    #expect(BarNavigation.match("a", labels: labels, from: 4) == 0)
}

/// A second letter refines the name, so the cell already reached still counts.
@Test func moreLettersRefineTheName() {
    #expect(BarNavigation.match("sl", labels: labels, from: 1) == 3)
    #expect(BarNavigation.match("sa", labels: labels, from: 1) == 1)
    #expect(BarNavigation.match("sx", labels: labels, from: 1) == nil)
}

/// The same letter again, quickly, walks through every name that starts with it.
@Test func aRepeatedLetterCycles() {
    #expect(BarNavigation.match("ss", labels: labels, from: 1) == 3)
    #expect(BarNavigation.match("sss", labels: labels, from: 3) == 5)
}

@Test func typingIgnoresCaseAndAccents() {
    #expect(BarNavigation.match("SK", labels: labels, from: 0) == 5)
    #expect(BarNavigation.match("m", labels: labels, from: 0) == 4)
}

// MARK: - The actions a screen reader is offered

@Test func anAppOffersEveryModifierClick() {
    #expect(ClickAction.alternatives(for: named("A"))
        == [.revealInFinder, .toggleHide, .showOnly, .quit, .forceRelaunch])
}

@Test func aWindowButtonClosesRatherThanQuits() {
    let window = DockItem(kind: .window(
        AppRef(bundleID: "a", url: URL(fileURLWithPath: "/Applications/A.app"), name: "A"),
        WindowRef(pid: 1, title: "Doc", isMinimized: false)))
    #expect(ClickAction.alternatives(for: window).contains(.closeWindow))
    #expect(!ClickAction.alternatives(for: window).contains(.quit))
}

/// A folder has only ⌘-click to offer; the launcher and a separator have nothing.
@Test func whatCannotBeDoneIsNotOffered() {
    let folder = DockItem(kind: .folder(URL(fileURLWithPath: "/tmp")), isPinned: true)
    #expect(ClickAction.alternatives(for: folder) == [.revealInFinder])
    #expect(ClickAction.alternatives(for: DockItem(kind: .appsMenu)).isEmpty)
    #expect(ClickAction.alternatives(for: separator).isEmpty)
}

@Test func hideIsNamedForWhatItWillDo() {
    var item = named("A")
    #expect(ClickAction.toggleHide.title(for: item) == "Hide")
    item.isHidden = true
    #expect(ClickAction.toggleHide.title(for: item) == "Show")
}
