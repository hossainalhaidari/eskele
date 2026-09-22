import AppKit
import Carbon.HIToolbox
import Testing
@testable import Eskele

/// Records what the strip asks of its owner, so a key press can be checked for what it did.
@MainActor
private final class Recorder: BarContentViewDelegate {
    var performed: [(ClickAction, String)] = []

    func barContent(_ view: BarContentView, perform action: ClickAction, on item: DockItem) {
        performed.append((action, item.id))
    }
    func barContent(_ view: BarContentView, stackMenuFor item: DockItem) -> NSMenu? { nil }
    func barContent(
        _ view: BarContentView, showLauncherAt anchor: NSRect, onDismiss: @escaping () -> Void
    ) -> Bool { false }
    func barContent(_ view: BarContentView, menuFor item: DockItem) -> NSMenu { NSMenu() }
    func barContent(_ view: BarContentView, menuForBackgroundAt index: Int) -> NSMenu { NSMenu() }
    func barContent(_ view: BarContentView, didMove item: DockItem, toVisualIndex index: Int) {}
    func barContent(_ view: BarContentView, didDropFiles urls: [URL], on item: DockItem) {}
    func barContent(_ view: BarContentView, didDropFiles urls: [URL], atVisualIndex index: Int) {}
    func barContent(_ view: BarContentView, didDragOutOfBar item: DockItem, at screenPoint: NSPoint) {}
    func barContent(_ view: BarContentView, previewFor item: DockItem) async -> NSImage? { nil }
}

private func app(_ name: String, frontmost: Bool = false) -> DockItem {
    DockItem(
        kind: .app(AppRef(
            bundleID: "test.\(name)",
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            name: name)),
        isPinned: true, isRunning: true, isFrontmost: frontmost)
}

private let separator = DockItem(kind: .separator("s"), isPinned: true)

@MainActor
private final class Strip {
    let view = BarContentView()
    let recorder = Recorder()
    var settings = Settings()
    var left = 0

    init(_ items: [DockItem], edge: BarEdge = .bottom) {
        settings.edge = edge
        settings.showAppsMenu = false
        settings.showTrash = false
        view.delegate = recorder
        view.onLeaveKeyboard = { [unowned self] in self.left += 1 }
        show(items)
    }

    func show(_ items: [DockItem]) {
        view.configure(items: items, settings: settings, thickness: 32, scale: 2)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 32)
        view.layoutSubtreeIfNeeded()
    }

    var cells: [ItemView] { view.accessibilityChildren()?.compactMap { $0 as? ItemView } ?? [] }
    var focusedName: String? { view.keyboardFocus.map { view.items[$0].displayName } }
    var ringed: [String] {
        view.subviews.compactMap { $0 as? ItemView }.filter(\.hasKeyboardFocus).map(\.item.displayName)
    }

    func press(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = [], _ characters: String = "") {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: UInt16(keyCode))!
        view.keyDown(with: event)
    }
}

// MARK: - Entering and leaving

@MainActor
@Test func theKeyboardLandsOnTheAppInFront() {
    let strip = Strip([app("A"), app("B", frontmost: true), app("C")])
    #expect(strip.view.keyboardFocus == nil)
    #expect(!strip.view.isInteracting)

    strip.view.beginKeyboardNavigation()
    #expect(strip.focusedName == "B")
    #expect(strip.ringed == ["B"])
    // Holds an auto-hiding bar open: the pointer is likely nowhere near it.
    #expect(strip.view.isInteracting)
}

@MainActor
@Test func leavingClearsTheRing() {
    let strip = Strip([app("A"), app("B")])
    strip.view.beginKeyboardNavigation()
    strip.view.endKeyboardNavigation()
    #expect(strip.view.keyboardFocus == nil)
    #expect(strip.ringed.isEmpty)
    #expect(!strip.view.isInteracting)
}

@MainActor
@Test func escapeAsksToGiveTheKeyboardBack() {
    let strip = Strip([app("A")])
    strip.view.beginKeyboardNavigation()
    strip.press(kVK_Escape)
    #expect(strip.left == 1)
}

// MARK: - Moving

@MainActor
@Test func theArrowsStepOverSeparators() {
    let strip = Strip([app("A"), separator, app("B"), app("C")])
    strip.view.beginKeyboardNavigation()
    #expect(strip.focusedName == "A")

    strip.press(kVK_RightArrow)
    #expect(strip.focusedName == "B")
    strip.press(kVK_RightArrow, .command)
    #expect(strip.focusedName == "C")
    strip.press(kVK_LeftArrow)
    strip.press(kVK_LeftArrow)
    #expect(strip.focusedName == "A")
    #expect(strip.ringed == ["A"])
}

@MainActor
@Test func aSideBarMovesWithUpAndDown() {
    let strip = Strip([app("A"), app("B")], edge: .left)
    strip.view.beginKeyboardNavigation()
    strip.press(kVK_DownArrow)
    #expect(strip.focusedName == "B")
    strip.press(kVK_UpArrow)
    #expect(strip.focusedName == "A")
}

@MainActor
@Test func typingANameGoesToIt() {
    let strip = Strip([app("Mail"), app("Safari"), app("Slack")])
    strip.view.beginKeyboardNavigation()
    strip.press(kVK_ANSI_S, [], "s")
    #expect(strip.focusedName == "Safari")
    strip.press(kVK_ANSI_L, [], "l")
    #expect(strip.focusedName == "Slack")
}

// MARK: - Pressing

@MainActor
@Test func returnIsAClickOnTheFocusedCell() {
    let strip = Strip([app("A"), app("B")])
    strip.view.beginKeyboardNavigation()
    strip.press(kVK_RightArrow)
    strip.press(kVK_Return)
    strip.press(kVK_Return, .shift)
    strip.press(kVK_Return, .command)
    #expect(strip.recorder.performed.map(\.0) == [.activate, .quit, .revealInFinder])
    #expect(strip.recorder.performed.allSatisfy { $0.1 == "app:test.B" })
}

// MARK: - Rebuilds

/// The bar rebuilds whenever anything on it changes. The keyboard stays on its cell, found by what
/// it is rather than where it was.
@MainActor
@Test func aRebuildKeepsTheKeyboardOnItsCell() {
    let strip = Strip([app("A"), app("B")])
    strip.view.beginKeyboardNavigation()
    strip.press(kVK_RightArrow)

    strip.show([app("New"), app("A"), app("B")])
    #expect(strip.focusedName == "B")
    #expect(strip.ringed == ["B"])
}

/// Quitting the focused app from the keyboard leaves you on whatever took its place.
@MainActor
@Test func aVanishedCellHandsTheKeyboardToItsNeighbour() {
    let strip = Strip([app("A"), app("B"), app("C")])
    strip.view.beginKeyboardNavigation()
    strip.press(kVK_RightArrow)

    strip.show([app("A"), app("C")])
    #expect(strip.focusedName == "C")
    #expect(strip.ringed == ["C"])

    strip.show([app("A")])
    #expect(strip.focusedName == "A")
}

@MainActor
@Test func anEmptiedBarGivesTheKeyboardBack() {
    let strip = Strip([app("A")])
    strip.view.beginKeyboardNavigation()
    strip.show([])
    #expect(strip.view.keyboardFocus == nil)
    #expect(strip.left == 1)
}

// MARK: - What VoiceOver sees

/// In bar order. A cell for an app that launched mid-session is added to the view last, wherever it
/// sits on the bar, and left to AppKit it would be read last too.
@MainActor
@Test func voiceOverReadsTheCellsInBarOrder() {
    let strip = Strip([app("A"), app("C")])
    strip.show([app("A"), app("B"), separator, app("C")])
    #expect(strip.cells.map(\.item.displayName) == ["A", "B", "C"])
    #expect(strip.view.accessibilityRole() == .list)
    #expect(strip.view.accessibilityOrientation() == .horizontal)
}

@MainActor
@Test func aCellIsANamedButtonWithActions() throws {
    var item = app("Safari", frontmost: true)
    item.windowCount = 2
    let cell = ItemView(item: item, edge: .bottom, metrics: BarMetrics(thickness: 32, settings: Settings()))
    #expect(cell.isAccessibilityElement())
    #expect(cell.accessibilityRole() == .button)
    #expect(cell.accessibilityLabel() == "Safari")
    #expect(cell.accessibilityValue() as? String == "running, active, 2 windows")
    let actions = try #require(cell.accessibilityCustomActions()).map(\.name)
    #expect(actions == ["Show in Finder", "Hide", "Show Only This", "Quit", "Force Quit and Relaunch"])

    let gap = ItemView(item: separator, edge: .bottom, metrics: BarMetrics(thickness: 32, settings: Settings()))
    #expect(!gap.isAccessibilityElement())
}

// MARK: - In a real window

/// What the running app relies on and a bare view cannot show: the focused cell is the panel's
/// first responder, keys sent to it climb the responder chain to the strip, and no other cell can be
/// made first responder — which is what keeps a click from giving focus to a panel meant never to
/// take it.
@MainActor
@Test func keysReachTheStripThroughTheFocusedCell() throws {
    _ = NSApplication.shared
    let strip = Strip([app("A"), app("B"), app("C")])
    let panel = BarPanel()
    panel.contentView = strip.view
    panel.setFrame(NSRect(x: 0, y: -1000, width: 600, height: 32), display: false)
    strip.view.layoutSubtreeIfNeeded()
    defer { panel.close() }

    #expect(!panel.canBecomeKey)
    panel.acceptsKeyboard = true
    #expect(panel.canBecomeKey)

    strip.view.beginKeyboardNavigation()
    let first = try #require(panel.firstResponder as? ItemView)
    #expect(first.item.displayName == "A")
    #expect(first.isAccessibilityFocused())
    #expect(first.accessibilityParent() as? BarContentView === strip.view)

    let right = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, characters: "\u{F703}",
        charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: UInt16(kVK_RightArrow)))
    first.keyDown(with: right)
    let second = try #require(panel.firstResponder as? ItemView)
    #expect(second.item.displayName == "B")
    #expect(!first.isAccessibilityFocused())

    // Only the cell the strip chose will take it, even when asked directly: the others refuse, and
    // the window keeps the first responder for itself.
    let third = try #require(strip.cells.last)
    panel.makeFirstResponder(third)
    #expect(panel.firstResponder !== third)

    strip.view.endKeyboardNavigation()
    #expect(!(panel.firstResponder is ItemView))
}
