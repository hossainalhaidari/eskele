import Foundation

/// One run of rows in the launcher, optionally under a heading.
struct LauncherSection: Equatable, Sendable {
    /// `nil` for an ungrouped run, which is what every list is while a search is running.
    var title: String?
    var entries: [CatalogEntry]
}

/// Turns a source's entries into the rows the launcher draws.
///
/// Pure, and tested as such: the grouping rule and the match ranking are the whole behaviour of the
/// list, and neither of them needs a window to be true.
enum LauncherContent {
    static func sections(source: AppsMenuSource, entries: [CatalogEntry], query: String) -> [LauncherSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty else {
            // A search is already a filter; grouping its handful of results by category would put
            // more headings on screen than answers.
            let matches = matches(in: entries, query: trimmed)
            return matches.isEmpty ? [] : [LauncherSection(title: nil, entries: matches)]
        }

        // Favourites are in bar order and Recents are in recency order; both orders are the point of
        // the list, and grouping would destroy them.
        guard source == .allApps else {
            return entries.isEmpty ? [] : [LauncherSection(title: nil, entries: entries)]
        }

        let grouped = Dictionary(grouping: entries, by: \.category)
        return grouped.keys.sorted().map { category in
            let members = grouped[category, default: []]
            // Applications are sorted by name; the system sections arrive in an order that was
            // chosen — the Finder's sidebar order for the folders, and Sleep before Shut Down for
            // the power rows, so the destructive one is not next to the harmless one.
            return LauncherSection(
                title: category.title,
                entries: category.isSystem
                    ? members
                    : members.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }

    // MARK: - Search

    /// Best matches first: what you typed starting the name, then starting a word inside it, then
    /// its initials, then anywhere at all. "code" should reach Visual Studio Code before Xcode.
    static func matches(in entries: [CatalogEntry], query: String) -> [CatalogEntry] {
        let needle = fold(query)
        guard !needle.isEmpty else { return entries }

        // Two statements, not one chain: as a single expression it is more than Swift 6.4's type
        // checker will solve in time.
        let ranked: [(rank: Int, index: Int, entry: CatalogEntry)] = entries
            .enumerated()
            .compactMap { index, entry in score(entry.name, needle).map { (rank: $0, index: index, entry: entry) } }
        // `sorted` is not stable, so the original index breaks ties rather than leaving the
        // order of equally good matches to the sort's internals.
        return ranked
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.index < $1.index }
            .map(\.entry)
    }

    private static func score(_ name: String, _ needle: String) -> Int? {
        let haystack = fold(name)
        if haystack.hasPrefix(needle) { return 0 }
        let words = haystack.split(whereSeparator: { " -_.".contains($0) })
        if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if words.count > 1, String(words.compactMap(\.first)).hasPrefix(needle) { return 2 }
        if haystack.contains(needle) { return 3 }
        return nil
    }

    /// Case and accents both have to go: nobody types the é in Café.
    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
