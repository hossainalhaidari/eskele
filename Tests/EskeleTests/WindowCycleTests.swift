import AppKit
import Testing
@testable import Eskele

private func key(_ title: String, _ x: CGFloat = 0, _ y: CGFloat = 0) -> CycleKey {
    CycleKey(title: title, origin: CGPoint(x: x, y: y))
}

/// The step a click takes: where focus is now, and where the next click's focus lands.
private func cycle(_ keys: [CycleKey], from focused: Int) -> Int {
    let order = WindowService.cycleOrder(keys)
    let found = order.firstIndex(of: focused) ?? 0
    return order[(found + 1) % order.count]
}

/// The bug: the z-order `AXWindows` returns puts the window just raised at the head, so cycling by
/// it walked back and forth between two windows. Five clicks must visit five windows.
@Test func cyclingReachesEveryWindow() {
    let keys = [key("Alpha"), key("Bravo"), key("Charlie"), key("Delta"), key("Echo")]
    var visited: Set<Int> = [0]
    var current = 0
    for _ in 1..<keys.count {
        current = cycle(keys, from: current)
        visited.insert(current)
    }
    #expect(visited.count == keys.count)
    #expect(cycle(keys, from: current) == 0)
}

/// The order is a property of the windows, not of which one happens to be in front — so raising
/// one and asking again gives the same sequence rather than a new one.
@Test func theOrderDoesNotMoveWhenFocusDoes() {
    let keys = [key("Charlie"), key("Alpha"), key("Bravo")]
    #expect(WindowService.cycleOrder(keys) == [1, 2, 0])
    // The z-order after raising "Alpha": same windows, front-to-back order changed.
    let raised = [keys[1], keys[0], keys[2]]
    #expect(WindowService.cycleOrder(raised).map { raised[$0].title }
            == WindowService.cycleOrder(keys).map { keys[$0].title })
}

/// Windows sharing a title — several Finder windows, or the untitled ones — are ordered by where
/// they sit, which is the one thing about them that stays put while focus moves.
@Test func windowsSharingATitleAreSeparatedByPosition() {
    let keys = [key("Untitled", 900, 100), key("Untitled", 100, 400), key("Untitled", 100, 20)]
    #expect(WindowService.cycleOrder(keys) == [2, 1, 0])
    var visited: Set<Int> = [0]
    var current = 0
    for _ in 1..<keys.count {
        current = cycle(keys, from: current)
        visited.insert(current)
    }
    #expect(visited.count == keys.count)
}

/// Two windows in the same place with the same name cannot be told apart, and still have to come
/// out in some fixed order rather than whichever one `sorted` felt like putting first.
@Test func indistinguishableWindowsStillGetAFixedOrder() {
    let keys = [key("Window"), key("Window"), key("Window")]
    #expect(WindowService.cycleOrder(keys) == [0, 1, 2])
}

/// Titles sort the way the bar's window buttons do: by `localizedStandardCompare`, which reads
/// numbers as numbers.
@Test func titlesSortTheWayTheBarShowsThem() {
    let keys = [key("Note 10"), key("Note 2"), key("Note 1")]
    #expect(WindowService.cycleOrder(keys).map { keys[$0].title } == ["Note 1", "Note 2", "Note 10"])
}
