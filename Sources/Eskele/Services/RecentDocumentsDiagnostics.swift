import AppKit
import ApplicationServices

/// What every running app's recent documents are, from both sources, and how long each read took.
///
/// An app with no list in its context menu has several causes that look the same from outside —
/// Accessibility was never granted, the app keeps no recent documents, it calls the item something
/// else, or it files it under a menu we do not search — and, for the lists macOS keeps for the Dock,
/// whether Full Disk Access is there and the list file was found. This says which.
///
///     open -n <Eskele.app> --args --diagnose-recents
@MainActor
enum RecentDocumentsDiagnostics {
    static func report(service: RecentDocumentsService, settings: Settings) -> String {
        let readable = RecentDocumentLists.isReadable
        let lists = (try? FileManager.default.contentsOfDirectory(
            atPath: RecentDocumentLists.directory.path)) ?? []
        var report = """
            Eskele — recent documents

            accessibility:    \(AXIsProcessTrusted() ? "granted" : "NOT granted — no app's menu can be read")
            full disk access: \(readable ? "granted" : "NOT granted — the Dock's lists cannot be read")
            read Dock lists:  \(settings.recentDocumentLists ? "on" : "off — the bar reads menus only")
            list files:       \(readable ? "\(lists.count) in \(RecentDocumentLists.directory.path)" : "unreadable")

            """
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        // The names as they are on disk, so a list the bar fails to find can be matched by eye.
        if readable {
            report += "list file names:\n"
            for name in lists.sorted() { report += "  \(name)\n" }
        }
        for app in apps {
            let pid = app.processIdentifier
            let start = Date()
            let found = service.locate(pid: pid)
            let documents = found == nil ? [] : service.documents(for: pid)
            let elapsed = Date().timeIntervalSince(start) * 1000
            report += "\n\(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "no bundle id"))"
            report += String(format: " — menu %.1f ms\n", elapsed)
            if readable, let bundleID = app.bundleIdentifier {
                let start = Date()
                let name = SharedFileList.listName(forBundleID: bundleID, among: lists)
                let files = RecentDocumentLists.documents(forBundleID: bundleID)
                let elapsed = Date().timeIntervalSince(start) * 1000
                if let name, let files {
                    // Bookmarks found against documents kept: a list with bookmarks and no documents
                    // has moved files. One with no bookmarks is empty or misread — the limits and the
                    // sidebar list below tell those apart.
                    let archive = try? Data(contentsOf: RecentDocumentLists.directory.appendingPathComponent(name))
                    let found = archive.map { SharedFileList.bookmarks(in: $0).count } ?? 0
                    report += "  list \(name): \(found) bookmark(s), \(files.count) document(s)"
                    report += String(format: " — %.1f ms\n", elapsed)
                    for file in files { report += "    \(file.path)\n" }
                } else {
                    report += "  no list file\n"
                }
            }
            guard let found else {
                if let elsewhere = service.locate(pid: pid, everywhere: true) {
                    report += "  only outside File, which the bar does not search: \(elsewhere.path)\n"
                } else {
                    report += "  no Open Recent menu\n"
                }
                continue
            }
            report += "  \(found.path): \(documents.count) document(s)\n"
            for document in documents { report += "    \(document.title)\n" }
            let entries = service.read(found.menu).entries
            report += "  every item: "
            report += entries.map { $0.title.isEmpty ? "—" : $0.title + ($0.hasShortcut ? " [⌘]" : "") }
                .joined(separator: " | ") + "\n"
        }
        // The largest list is the one most likely to have items in it.
        let size = { (name: String) in
            (try? RecentDocumentLists.directory.appendingPathComponent(name)
                .resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        if readable {
            report += "\nshared file list folder\n"
            let root = RecentDocumentLists.sharedFileListDirectory
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            while let url = walker?.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                // The per-app lists are already named above; their sizes are what matter here.
                report += "  \(relative) \(values?.fileSize.map { "\($0) B" } ?? "dir")"
                report += " \(values?.contentModificationDate.map { "\($0)" } ?? "")\n"
            }
        }
        if readable {
            // Each list records the limit it keeps to; zero is the Recent Items setting at None.
            var limits: [String: Int] = [:]
            var zeroLimit: [String] = []
            for name in lists {
                guard let data = try? Data(contentsOf: RecentDocumentLists.directory.appendingPathComponent(name)),
                      let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let objects = root["$objects"] as? [Any],
                      let index = objects.firstIndex(where: { ($0 as? String) == "com.apple.LSSharedFileList.MaxAmount" })
                else { continue }
                // The value follows its key among the objects when the dictionary was archived.
                let number = objects[(index + 1)...].lazy.compactMap { $0 as? NSNumber }.first
                limits["\(number.map { "\($0)" } ?? "?")", default: 0] += 1
                if number == 0 { zeroLimit.append(name) }
            }
            report += "\nMaxAmount across the lists: \(limits.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))\n"
            if !zeroLimit.isEmpty { report += "  kept to none: \(zeroLimit.sorted().joined(separator: ", "))\n" }
            // A list known to hold bookmarks, to tell an empty list from a misread format.
            let favourites = RecentDocumentLists.sharedFileListDirectory
                .appendingPathComponent("com.apple.LSSharedFileList.FavoriteItems.sfl4")
            if let data = try? Data(contentsOf: favourites) {
                let bookmarks = SharedFileList.bookmarks(in: data)
                let urls = RecentDocumentLists.resolve(bookmarks)
                report += "FavoriteItems.sfl4: \(bookmarks.count) bookmark(s), \(urls.count) resolve\n"
                for url in urls { report += "  \(url.path)\n" }
            }
        }
        if readable, let name = lists.max(by: { size($0) < size($1) }) {
            report += "\nstructure of \(name)\n"
            report += structure(of: RecentDocumentLists.directory.appendingPathComponent(name))
        }
        return report
    }

    /// The shape of one list, without unarchiving it: how it starts, what kind of property list it
    /// is, its top-level keys, and what the archived objects are. Enough to see where the bookmarks
    /// went when the reader finds none.
    private static func structure(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "  unreadable\n" }
        var out = "  \(data.count) bytes, starts \(data.prefix(8).map { String(format: "%02x", $0) }.joined())"
        out += " (\(String(decoding: data.prefix(8), as: UTF8.self).filter { $0.isASCII && !$0.isNewline }))\n"
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: &format) else {
            return out + "  not a property list\n"
        }
        out += "  property list, format \(format.rawValue), root \(type(of: plist))\n"
        guard let root = plist as? [String: Any] else { return out }
        for key in root.keys.sorted() { out += "  key \(key): \(type(of: root[key]!))\n" }
        if let objects = root["$objects"] as? [Any] {
            var kinds: [String: Int] = [:]
            for object in objects { kinds["\(type(of: object))", default: 0] += 1 }
            out += "  $objects: \(objects.count) — " + kinds.sorted { $0.key < $1.key }
                .map { "\($0.key) ×\($0.value)" }.joined(separator: ", ") + "\n"
            for case let blob as Data in objects {
                out += "    data \(blob.count) bytes, starts \(blob.prefix(8).map { String(format: "%02x", $0) }.joined())"
                out += " (\(String(decoding: blob.prefix(8), as: UTF8.self).filter { $0.isASCII && !$0.isNewline }))\n"
            }
            for case let text as String in objects.prefix(40) { out += "    string \(text.prefix(80))\n" }
        }
        return out
    }
}
