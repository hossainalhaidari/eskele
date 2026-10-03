import AppKit

/// Builds the pop-up list for a pinned folder — a "stack".
///
/// An `NSMenu` rather than a bespoke grid panel: it is the same thing the system Dock's list view
/// is, and it comes with keyboard navigation, overflow scrolling and correct screen-edge placement
/// for free. A fan or grid presentation would be a separate v2 view.
@MainActor
final class StackMenuController: NSObject, NSMenuDelegate {
    /// Beyond this the menu stops being a shortcut and starts being a bad Finder.
    private static let maximumEntries = 40
    private static let iconSize: CGFloat = 16

    private var directories: [ObjectIdentifier: (url: URL, sort: StackSort)] = [:]

    /// - Parameter sort: how to list `directory`, and every folder opened from inside it — a
    ///   subfolder of Downloads is read the way Downloads is.
    func menu(for directory: URL, sort: StackSort) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        directories[ObjectIdentifier(menu)] = (directory, sort)
        return menu
    }

    // Submenus are filled in on demand, so opening a stack never walks the whole tree.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let (directory, sort) = directories[ObjectIdentifier(menu)] else { return }
        menu.removeAllItems()

        let entries = contents(of: directory, sorted: sort)
        if entries.isEmpty {
            let empty = NSMenuItem(
                title: String(localized: "Empty", comment: "Greyed-out menu item: this folder has nothing in it"),
                action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for url in entries.prefix(StackMenuController.maximumEntries) {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(open(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = icon(for: url)

            if url.hasDirectoryPath && url.pathExtension != "app" {
                let submenu = self.menu(for: url, sort: sort)
                submenu.title = url.lastPathComponent
                item.submenu = submenu
            }
            menu.addItem(item)
        }

        if entries.count > StackMenuController.maximumEntries {
            let more = NSMenuItem(
                title: "\(entries.count - StackMenuController.maximumEntries) more…",
                action: nil, keyEquivalent: "")
            more.isEnabled = false
            menu.addItem(more)
        }

        menu.addItem(.separator())
        let reveal = NSMenuItem(
            title: String(localized: "Open in Finder", comment: "Menu item: open this folder in Finder"),
            action: #selector(open(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = directory
        menu.addItem(reveal)
    }

    private func contents(of directory: URL, sorted sort: StackSort) -> [URL] {
        let keys: [URLResourceKey] = [
            .addedToDirectoryDateKey, .contentModificationDateKey, .creationDateKey,
            .localizedTypeDescriptionKey,
        ]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        let entries = urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return StackSort.Entry(
                url: url,
                isFolder: url.hasDirectoryPath && url.pathExtension != "app",
                added: values?.addedToDirectoryDate,
                modified: values?.contentModificationDate,
                created: values?.creationDate,
                kind: values?.localizedTypeDescription)
        }
        return sort.ordered(entries).map(\.url)
    }

    private func icon(for url: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: StackMenuController.iconSize, height: StackMenuController.iconSize)
        return image
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }
}
