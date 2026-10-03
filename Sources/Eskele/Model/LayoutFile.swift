import Foundation

/// Export Layout and Import Layout: what is pinned to the bar, taken to another Mac.
///
/// `layout.json` cannot simply be copied across. Its pins lead with bookmarks, which name a file on
/// one particular volume and resolve to nothing — or worse, to a stale guess — anywhere else, and
/// its paths start with this Mac's home folder, which on another Mac belongs to another name. So an
/// export leaves the bookmarks out and writes paths under the home folder as `~/…`; apps travel by
/// bundle identifier, which `PersistedItem.resolveURL` already tries before the path.
///
/// The file is still a `Layout`, so a copy of `layout.json` imports as well — on the same Mac its
/// bookmarks still work, and elsewhere they fail and the rest of the entry is tried.
enum LayoutFile {
    enum ReadError: Error, Equatable {
        /// Not JSON, or JSON that is not an object with an `items` list.
        case notLayout
    }

    /// The pins as an export writes them.
    static func portable(_ items: [PersistedItem], home: URL) -> [PersistedItem] {
        items.map { item in
            var copy = item
            copy.bookmark = nil
            copy.path = item.path.map { abbreviating($0, home: home) }
            return copy
        }
    }

    /// What an import would leave on the bar, and the names of what it could not find here.
    struct Resolution: Equatable {
        var items: [PersistedItem]
        var missing: [String]
    }

    /// Finds each entry on this Mac and makes it afresh from what was found, so it gets a bookmark
    /// that means something here and a path that is really this Mac's; the user's own name for it
    /// and its stack order come along.
    ///
    /// Separators come too, but not one with nothing found on either side of it: two separators
    /// together, or one at an end, would be a gap with no reason that the user could only find by
    /// looking for it.
    ///
    /// - Parameters:
    ///   - locate: where an entry is on this Mac, or nil. `PersistedItem.resolveURL` in the app;
    ///     a stand-in in the tests, which cannot install applications.
    ///   - make: an entry for a URL that was found; `PersistedItem.make` in the app.
    static func resolve(
        _ incoming: [PersistedItem],
        home: URL,
        locate: (PersistedItem) -> URL? = { $0.resolveURL() },
        make: (URL) -> PersistedItem? = PersistedItem.make
    ) -> Resolution {
        var items: [PersistedItem] = []
        var missing: [String] = []
        for entry in incoming {
            if entry.kind == .separator {
                if let last = items.last, last.kind != .separator { items.append(entry) }
                continue
            }
            var expanded = entry
            expanded.path = entry.path.map { expanding($0, home: home) }
            guard let url = locate(expanded), var found = make(url) else {
                missing.append(entry.customName ?? entry.name ?? entry.path ?? entry.bundleID ?? "?")
                continue
            }
            found.customName = entry.customName
            found.stackSort = entry.stackSort
            // The same thing twice — a folder listed under two paths that are one folder here.
            guard !items.contains(where: { $0.identity == found.identity }) else { continue }
            items.append(found)
        }
        if items.last?.kind == .separator { items.removeLast() }
        return Resolution(items: items, missing: missing)
    }

    /// Reads an exported layout, or a copy of `layout.json`.
    ///
    /// `Layout`'s own decoder makes an empty layout out of any JSON object, so a settings file
    /// would import as a bar with nothing on it. An `items` list is what makes a file a layout.
    static func read(_ data: Data) throws(ReadError) -> [PersistedItem] {
        guard let census = try? JSONDecoder().decode(ItemsCensus.self, from: data), census.hasItems,
              let layout = try? JSONDecoder().decode(Layout.self, from: data)
        else { throw .notLayout }
        return layout.items
    }

    static func encode(_ items: [PersistedItem], home: URL) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Layout(items: portable(items, home: home)))
    }

    /// `home.path` as it is, not standardised: standardising takes `/private` off a path whose
    /// shorter form also exists, and the paths it is compared with keep theirs.
    private static func abbreviating(_ path: String, home: URL) -> String {
        let root = home.path
        if path == root { return "~" }
        guard path.hasPrefix(root + "/") else { return path }
        return "~" + path.dropFirst(root.count)
    }

    private static func expanding(_ path: String, home: URL) -> String {
        let root = home.path
        if path == "~" { return root }
        guard path.hasPrefix("~/") else { return path }
        return root + path.dropFirst(1)
    }

    // MARK: - Wording

    /// Offered in the save panel, which adds the extension.
    static var suggestedName: String {
        String(
            localized: "Eskele Layout",
            comment: "Suggested file name for an exported layout; the .json extension is added for you")
    }

    static func refusal(filename: String) -> String {
        String(
            localized: "“\(filename)” is not an Eskele layout file.",
            comment: "Layout import refused. The file name is already quoted.")
    }

    static var refusalDetail: String {
        String(
            localized: """
                Nothing was changed. A layout file is one saved with Export Layout, or a copy of \
                layout.json.
                """,
            comment: "Layout import refused, under the message")
    }

    static func nothingFound(filename: String) -> String {
        String(
            localized: "Nothing in “\(filename)” is on this Mac.",
            comment: "Layout import refused because none of its apps, folders or files exist here")
    }

    static var nothingFoundDetail: String {
        String(
            localized: """
                Nothing was changed, so the bar keeps what it has. Install the apps, or copy the \
                folders and files across, and import it again.
                """,
            comment: "Layout import refused because nothing in it exists here, under the message")
    }

    static var someMissing: String {
        String(
            localized: "Some items are not on this Mac",
            comment: "Layout imported, but some pinned items could not be found")
    }

    /// The names, one to a line: the list is the point, and a sentence would bury it.
    static func someMissingDetail(_ names: [String]) -> String {
        let lead = String(
            localized: "The rest of the layout is on the bar. These were left out:",
            comment: "Layout imported with some items missing; the names follow on their own lines")
        return ([lead, ""] + names).joined(separator: "\n")
    }
}

/// Whether a JSON object has an `items` list, which is what makes it a layout.
private struct ItemsCensus: Decodable {
    var hasItems: Bool

    private enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasItems = (try? container.nestedUnkeyedContainer(forKey: .items)) != nil
    }
}
