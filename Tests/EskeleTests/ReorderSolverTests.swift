import Testing
@testable import Eskele

private func entries(_ pairs: [(String, Int)]) -> [ReorderSolver.Entry] {
    pairs.map { ReorderSolver.Entry(id: $0.0, start: $0.1) }
}

// MARK: - Which run a drop belongs to

@Test func aDropPastTheLastCellOfAGroupIsStillInsideIt() {
    // Cells 3, 4 and 5 are the group; 6 is the slot after it, which means "put it last".
    #expect(ReorderSolver.contains([3, 4, 5], index: 6))
    #expect(ReorderSolver.contains([3, 4, 5], index: 3))
    #expect(!ReorderSolver.contains([3, 4, 5], index: 2))
    #expect(!ReorderSolver.contains([3, 4, 5], index: 7))
}

@Test func anEmptyGroupContainsNothing() {
    #expect(!ReorderSolver.contains([], index: 0))
}

// MARK: - Running apps, which have no stored slot

@Test func draggingARunningAppLeftPutsItBeforeTheOneItPassed() {
    let group = entries([("a", 0), ("b", 1), ("c", 2)])
    #expect(ReorderSolver.reordered(group, moving: "c", to: 1) == ["a", "c", "b"])
}

@Test func draggingARunningAppToTheEndPutsItLast() {
    let group = entries([("a", 0), ("b", 1), ("c", 2)])
    #expect(ReorderSolver.reordered(group, moving: "a", to: 3) == ["b", "c", "a"])
}

@Test func draggingARunningAppToTheFrontPutsItFirst() {
    let group = entries([("a", 0), ("b", 1), ("c", 2)])
    #expect(ReorderSolver.reordered(group, moving: "c", to: 0) == ["c", "a", "b"])
}

/// An app split into one button per window still moves as a single app: its entry is recorded at
/// the first of its cells, and every id keeps its place relative to that.
@Test func anAppThatOccupiesSeveralCellsMovesAsAUnit() {
    let group = entries([("mail", 0), ("safari", 1), ("code", 4)])
    #expect(ReorderSolver.reordered(group, moving: "code", to: 1) == ["mail", "code", "safari"])
    #expect(ReorderSolver.reordered(group, moving: "mail", to: 4) == ["safari", "mail", "code"])
}

@Test func droppingSomethingBackWhereItWasChangesNothing() {
    let group = entries([("a", 0), ("b", 1), ("c", 2)])
    #expect(ReorderSolver.reordered(group, moving: "b", to: 1) == ["a", "b", "c"])
}

// MARK: - Window buttons, which move within their own app

@Test func aWindowMovesWithinItsApp() {
    let windows = ["w1", "w2", "w3"]
    #expect(ReorderSolver.moved(windows, id: "w3", toOffset: 0) == ["w3", "w1", "w2"])
    #expect(ReorderSolver.moved(windows, id: "w1", toOffset: 3) == ["w2", "w3", "w1"])
}

/// Dropping just after itself is a no-op, not a shuffle — the classic off-by-one in a reorder.
@Test func movingAWindowOntoItsOwnSlotIsANoOp() {
    let windows = ["w1", "w2", "w3"]
    #expect(ReorderSolver.moved(windows, id: "w2", toOffset: 1) == windows)
    #expect(ReorderSolver.moved(windows, id: "w2", toOffset: 2) == windows)
}

@Test func movingAnUnknownWindowLeavesTheOrderAlone() {
    #expect(ReorderSolver.moved(["w1", "w2"], id: "gone", toOffset: 0) == ["w1", "w2"])
}

// MARK: - Visual position → stored slot

private let stored = ["app:finder", "app:safari", "app:mail", "app:terminal"]

/// The strip as it looks in full-width labelled mode with one button per window: Safari and
/// Terminal are split into window buttons, and two unpinned apps trail the pinned ones.
private let visual = [
    "apps-menu",
    "app:finder",
    "app:safari",     // a window button, standing for its app
    "app:mail",
    "app:terminal",   // likewise
    "app:code",       // running, not pinned — no stored slot
    "app:claude",
    "trash",
]

@Test func aDropBeforeEverythingLandsAtTheStart() {
    #expect(ReorderSolver.storedInsertionIndex(visualIdentities: visual, stored: stored, index: 0) == 0)
    #expect(ReorderSolver.storedInsertionIndex(visualIdentities: visual, stored: stored, index: 1) == 0)
}

/// The bug: a window button is one cell of the strip but is not itself a stored entry. Counting
/// only stored entries made a drop just past a split app land one slot short — which came out as
/// "I dragged it and nothing moved".
@Test func aWindowButtonCountsTowardsItsOwnApp() {
    // Dropping between Safari's window button and Mail must mean "after Safari", slot 2.
    #expect(ReorderSolver.storedInsertionIndex(visualIdentities: visual, stored: stored, index: 3) == 2)
    // And between Mail and Terminal's window button, slot 3.
    #expect(ReorderSolver.storedInsertionIndex(visualIdentities: visual, stored: stored, index: 4) == 3)
}

/// Running apps with no stored slot must not advance the count, or dropping past them would
/// scatter the pinned order.
@Test func unpinnedRunningCellsDoNotAdvanceTheSlot() {
    for index in 5...8 {
        #expect(ReorderSolver.storedInsertionIndex(visualIdentities: visual, stored: stored, index: index) == 4)
    }
}

@Test func anIndexPastTheStripIsClamped() {
    #expect(ReorderSolver.storedInsertionIndex(visualIdentities: visual, stored: stored, index: 99) == 4)
    #expect(ReorderSolver.storedInsertionIndex(visualIdentities: visual, stored: stored, index: -1) == 0)
}

@Test func anEmptyLayoutHasOneSlot() {
    #expect(ReorderSolver.storedInsertionIndex(visualIdentities: [], stored: [], index: 3) == 0)
}
