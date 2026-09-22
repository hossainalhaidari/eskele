import AppKit
import Testing
@testable import Eskele

private func entry(_ name: String, _ category: AppCategory = .other) -> CatalogEntry {
    CatalogEntry(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, category: category)
}

private let developer = AppCategory(title: "Developer Tools")
private let productivity = AppCategory(title: "Productivity")

// MARK: - Grouping

/// Grouping is the whole point of the All Apps list, and the whole wrong answer for the others.
@Test func allAppsIsGroupedByCategory() {
    let entries = [entry("Xcode", developer), entry("Pages", productivity), entry("Ghostty", developer)]
    let sections = LauncherContent.sections(source: .allApps, entries: entries, query: "")

    #expect(sections.map(\.title) == ["Developer Tools", "Productivity"])
    #expect(sections[0].entries.map(\.name) == ["Ghostty", "Xcode"])
}

/// Favourites are in bar order and Recents in recency order. Both orders are the answer the list
/// exists to give, so neither may be regrouped or re-sorted.
@Test func theOtherSourcesAreOneUngroupedRunInTheirGivenOrder() {
    let entries = [entry("Zebra", developer), entry("Alpha", productivity)]

    for source in [AppsMenuSource.favorites, .recentApps] {
        let sections = LauncherContent.sections(source: source, entries: entries, query: "")
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].entries.map(\.name) == ["Zebra", "Alpha"])
    }
}

/// "Other" is where everything undeclared lands, and it is large. Alphabetically it would sit in
/// the middle of the real categories and bury them.
@Test func theCatchAllCategorySortsLast() {
    let entries = [entry("Steam"), entry("Xcode", developer), entry("Weather")]
    let sections = LauncherContent.sections(source: .allApps, entries: entries, query: "")
    #expect(sections.map(\.title) == ["Developer Tools", "Other"])
}

@Test func gameGenresCollapseIntoOneCategory() {
    #expect(AppCategory.declared("public.app-category.board-games")?.title == "Games")
    #expect(AppCategory.declared("public.app-category.games")?.title == "Games")
}

/// A category invented after this ships should still read as a heading rather than falling into
/// "Other" alongside everything unlabelled.
@Test func anUnknownCategoryIsTitleCasedFromItsIdentifier() {
    #expect(AppCategory.declared("public.app-category.time-travel")?.title == "Time Travel")
    #expect(AppCategory.declared("com.example.something") == nil)
    #expect(AppCategory.declared(nil) == nil)
}

// MARK: - Search

/// A search is already a filter; grouping five results under four headings is more chrome than
/// answer.
@Test func searchingFlattensTheGroups() {
    let entries = [entry("Xcode", developer), entry("Pages", productivity)]
    let sections = LauncherContent.sections(source: .allApps, entries: entries, query: "e")
    #expect(sections.count == 1)
    #expect(sections[0].title == nil)
}

/// The name you started typing comes before the name that merely contains it.
@Test func matchesAreRankedPrefixThenWordThenInitialsThenAnywhere() {
    let entries = [
        entry("Xcode"),          // contains
        entry("Visual Studio Code"), // word prefix
        entry("Code Editor"),    // prefix
    ]
    #expect(LauncherContent.matches(in: entries, query: "code").map(\.name)
        == ["Code Editor", "Visual Studio Code", "Xcode"])
}

@Test func initialsFindAMultiWordName() {
    let entries = [entry("Visual Studio Code"), entry("Notes")]
    #expect(LauncherContent.matches(in: entries, query: "vsc").map(\.name) == ["Visual Studio Code"])
}

@Test func searchIgnoresCaseAndAccents() {
    let entries = [entry("Café Player")]
    #expect(LauncherContent.matches(in: entries, query: "CAFE").count == 1)
}

@Test func nothingMatchingProducesNoSections() {
    let entries = [entry("Xcode", developer)]
    #expect(LauncherContent.sections(source: .allApps, entries: entries, query: "zzz").isEmpty)
}

/// Whitespace alone is not a search: it must not empty the list.
@Test func aBlankQueryIsNotASearch() {
    let entries = [entry("Xcode", developer)]
    let sections = LauncherContent.sections(source: .allApps, entries: entries, query: "   ")
    #expect(sections.map(\.title) == ["Developer Tools"])
}

// MARK: - Recents

@MainActor
@Test func mostRecentlyUsedComesFirstAndIsNotDuplicated() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-recents-\(UUID().uuidString)")
    let recents = RecentAppsService(persistence: Persistence(directory: directory), limit: 3)

    recents.note("com.example.a")
    recents.note("com.example.b")
    recents.note("com.example.a")

    #expect(recents.bundleIDs.first == "com.example.a")
    #expect(recents.bundleIDs.filter { $0 == "com.example.a" }.count == 1)
}

@MainActor
@Test func recentsAreCappedAtTheLimit() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-recents-\(UUID().uuidString)")
    let recents = RecentAppsService(persistence: Persistence(directory: directory), limit: 3)

    for index in 0..<10 { recents.note("com.example.\(index)") }
    #expect(recents.bundleIDs.count == 3)
    #expect(recents.bundleIDs.first == "com.example.9")
}

/// Recents are seeded from what is already running, so the launcher is useful on first launch
/// instead of blank until the user has switched apps a few times.
@MainActor
@Test func recentsAreSeededFromRunningApps() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-recents-\(UUID().uuidString)")
    let recents = RecentAppsService(persistence: Persistence(directory: directory))
    #expect(!recents.entries().isEmpty)
}
