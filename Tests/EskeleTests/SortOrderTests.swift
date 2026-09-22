import Foundation
import Testing
@testable import Eskele

private let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

private func app(_ name: String, running: Bool = true, launched: Double? = nil) -> DockItem {
    var item = DockItem(
        kind: .app(AppRef(bundleID: "test.\(name)", url: finder, name: name)),
        isPinned: true,
        isRunning: running)
    item.launchDate = launched.map { Date(timeIntervalSince1970: $0) }
    return item
}

private func names(_ items: [DockItem]) -> [String] {
    items.map { $0.isSeparator ? "|" : $0.displayName }
}

// MARK: - As arranged

@Test func manualOrderIsTheStoredOrder() {
    let items = [app("Safari"), app("Mail"), app("Notes")]
    #expect(names(BarComposition.sorted(items, by: .manual)) == ["Safari", "Mail", "Notes"])
}

/// The user's own dividers only survive their own ordering. Everywhere else they would sit between
/// two neighbours nobody chose to put together.
@Test func manualOrderKeepsSeparatorsAndTheOthersDoNot() {
    let items = [app("Safari"), DockItem(kind: .separator("user"), isPinned: true), app("Mail")]
    #expect(names(BarComposition.sorted(items, by: .manual)) == ["Safari", "|", "Mail"])
    #expect(names(BarComposition.sorted(items, by: .alphabetical)) == ["Mail", "Safari"])
    #expect(names(BarComposition.sorted(items, by: .launch)) == ["Safari", "Mail"])
}

// MARK: - By name

@Test func alphabeticalSortsByDisplayName() {
    let items = [app("Safari"), app("mail"), app("Notes")]
    #expect(names(BarComposition.sorted(items, by: .alphabetical)) == ["mail", "Notes", "Safari"])
}

/// `localizedStandardCompare`, so "App 10" follows "App 9" rather than "App 1" — the Finder's rule.
@Test func alphabeticalOrdersNumbersTheWayFinderDoes() {
    let items = [app("App 10"), app("App 9"), app("App 1")]
    #expect(names(BarComposition.sorted(items, by: .alphabetical)) == ["App 1", "App 9", "App 10"])
}

// MARK: - By launch time

@Test func launchOrderPutsTheOldestFirst() {
    let items = [app("Third", launched: 300), app("First", launched: 100), app("Second", launched: 200)]
    #expect(names(BarComposition.sorted(items, by: .launch)) == ["First", "Second", "Third"])
}

/// An app that is closed has no launch time. It cannot be placed among the ones that do, so it
/// keeps its stored order and follows them.
@Test func closedAppsKeepTheirOrderAfterTheRunningOnes() {
    let items = [
        app("PinnedB", running: false),
        app("Running", launched: 100),
        app("PinnedA", running: false),
    ]
    #expect(names(BarComposition.sorted(items, by: .launch)) == ["Running", "PinnedB", "PinnedA"])
}

// MARK: - Stability

/// `sorted(by:)` promises nothing about equal elements, and the bar is rebuilt on every activation,
/// hide and window change. Without the positional tie-break two apps sharing a name — or a bar full
/// of closed apps under By Launch Time — would reshuffle while the user watched.
@Test func equalItemsNeverChangePlaces() {
    let duplicates = [app("Same"), app("Same"), app("Other")]
    let byName = names(BarComposition.sorted(duplicates, by: .alphabetical))
    #expect(byName == ["Other", "Same", "Same"])
    // Same input, same answer, however many times it is asked.
    for _ in 0..<20 {
        #expect(names(BarComposition.sorted(duplicates, by: .alphabetical)) == byName)
    }

    let closed = (0..<8).map { app("App\($0)", running: false) }
    let order = names(BarComposition.sorted(closed, by: .launch))
    #expect(order == names(closed))
}

@Test func sortingAnEmptyRunIsEmpty() {
    #expect(BarComposition.sorted([], by: .alphabetical).isEmpty)
    #expect(BarComposition.sorted([], by: .launch).isEmpty)
}

// MARK: - Settings

@Test func sortOrderDefaultsToManualAndRoundTrips() throws {
    #expect(Settings().sortOrder == .manual)
    var settings = Settings()
    settings.sortOrder = .launch
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(Settings.self, from: data).sortOrder == .launch)
    // A file written before the setting existed, and one with a value from a later version.
    let old = try #require(try? JSONDecoder().decode(Settings.self, from: Data(#"{"edge":"left"}"#.utf8)))
    #expect(old.sortOrder == .manual)
    let odd = try #require(try? JSONDecoder().decode(
        Settings.self, from: Data(#"{"sortOrder":"byVibes"}"#.utf8)))
    #expect(odd.sortOrder == .manual)
}
