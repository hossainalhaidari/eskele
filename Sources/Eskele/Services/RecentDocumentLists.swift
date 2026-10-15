import Foundation

/// Each app's recent documents, from the lists macOS keeps for the Dock.
///
/// The complete source, where `RecentDocumentsService` is the partial one: an app that is not
/// running has a list here and no menu bar to read, and every entry is a real file whose folder can
/// be shown.
/// It costs Full Disk Access, so it is read only when `Settings.recentDocumentLists` asks for it,
/// and the menu stays the fallback. See §5.30.
enum RecentDocumentLists {
    static var sharedFileListDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
    }

    static var directory: URL {
        sharedFileListDirectory
            .appendingPathComponent("com.apple.LSSharedFileList.ApplicationRecentDocuments")
    }

    /// How many documents a list gives the menu. The Dock's own is as long as the *Recent items*
    /// setting, ten by default; a list kept longer than that should not become a menu taller than
    /// the screen.
    static let limit = 20

    /// Whether the lists can be read — which is to say whether Eskele has Full Disk Access.
    ///
    /// macOS has no call that answers that, and a refused read never raises a prompt, so trying is
    /// both the honest test and a harmless one.
    static var isReadable: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: sharedFileListDirectory.path)) != nil
    }

    /// The app's recent documents, newest first, or nil when there is no list to read — no access,
    /// or no list for that app.
    static func documents(forBundleID bundleID: String) -> [URL]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
              let name = SharedFileList.listName(forBundleID: bundleID, among: names),
              let archive = try? Data(contentsOf: directory.appendingPathComponent(name))
        else { return nil }
        return resolve(SharedFileList.bookmarks(in: archive))
    }

    /// The bookmarks as file URLs, leaving out any that no longer resolve to something on disk.
    ///
    /// Without UI and without mounting: this runs while a context menu is opening, and a document on
    /// a server that is not connected should drop out of the list rather than put up a sign-in.
    static func resolve(_ bookmarks: [Data]) -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        for bookmark in bookmarks where urls.count < limit {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &stale),
                url.isFileURL,
                FileManager.default.fileExists(atPath: url.path),
                seen.insert(url.path).inserted
            else { continue }
            urls.append(url)
        }
        return urls
    }
}
