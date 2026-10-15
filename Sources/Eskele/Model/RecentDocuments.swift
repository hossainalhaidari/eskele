import Foundation

/// The pure half of reading an app's recent documents out of its own *Open Recent* menu.
///
/// The system Dock reads them from the per-app lists under
/// `~/Library/Application Support/com.apple.sharedfilelist`, which macOS guards behind Full Disk
/// Access — measured: `ls` on the directory is refused even outside any sandbox — and
/// `LSSharedFileList`'s recent-documents list, the old public route, comes back empty. What *is*
/// open to Accessibility, which Eskele already holds, is the app's menu bar, and AppKit keeps the
/// same per-app list there. See §5.30.
enum RecentDocuments {
    /// What the *Open Recent* item is called, in English and in the language AppKit is running in.
    ///
    /// AppKit ships the title in its own `MenuCommands` table, and an app built from Xcode's
    /// template uses that same string, so the pair covers both the apps that localise and the ones
    /// that never did.
    static func menuTitles(localized: String?) -> Set<String> {
        var titles: Set<String> = ["Open Recent"]
        if let localized, !localized.isEmpty { titles.insert(localized) }
        return titles
    }

    /// One item of the submenu, as much of it as decides whether it is a document.
    struct Entry: Equatable {
        var title: String
        /// The item has a key equivalent — `AXMenuItemCmdChar` is set.
        var hasShortcut: Bool = false
    }

    /// Which of a submenu's items are documents.
    ///
    /// The documents come first and *Clear Menu* comes last, after a separator — and Accessibility
    /// presents a separator as an untitled item. So the documents are among the titled items before
    /// the last separator. Xcode splits its list into projects and files with further separators;
    /// those groups stay in. A submenu without a separator is an empty list showing only *Clear
    /// Menu*, or something that is not a recent-documents list at all, and either way it has nothing
    /// to offer.
    ///
    /// Not every app keeps commands out of the list. Measured on VS Code: *Reopen Closed Editor*
    /// (⇧⌘T) heads it and *More…* closes it. A document has no key equivalent, and a title ending in
    /// an ellipsis is, by the menu convention, a command that asks for more first — a file named that
    /// way loses its entry, which is the cheaper mistake.
    static func documentIndices(in entries: [Entry]) -> [Int] {
        guard let separator = entries.lastIndex(where: { $0.title.isEmpty }) else { return [] }
        return entries[..<separator].indices.filter { index in
            let entry = entries[index]
            return !entry.title.isEmpty && !entry.hasShortcut
                && !entry.title.hasSuffix("…") && !entry.title.hasSuffix("...")
        }
    }

    /// Where *Open Recent* is looked for: the File menu, third in the menu bar after the Apple menu
    /// and the app's own.
    ///
    /// Only there, because looking is a round trip into the app for every item of every menu
    /// searched, made while a context menu is opening. Measured, with Accessibility granted: 17 to
    /// 41 ms to search four menus of an app that has no such item, against a few for one. Every app
    /// measured that keeps the list keeps it in File.
    static let menuIndex = 2
}
