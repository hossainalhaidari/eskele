import AppKit
import ApplicationServices

/// A running app's recent documents, read from its own *Open Recent* menu through Accessibility.
///
/// No file URL comes with them: AppKit keeps the URL on the menu item, where Accessibility cannot
/// see it, so an entry is a title and the item to press. Pressing it is the app opening its own
/// recent document, which is what the Dock's entry does too. Only running apps have a menu bar to
/// read, so an app that is not running has no list — the one thing the Dock's version still does
/// that this does not. See §5.30.
@MainActor
final class RecentDocumentsService {
    struct Document {
        let title: String
        let element: AXUIElement
    }

    /// The same budget `WindowService` gives a read: this runs while a context menu is opening, and
    /// an app that does not answer in that time is not going to.
    private static let messagingTimeout: Float = 0.12
    /// Long enough for the activation to land before the menu item is pressed, as for a window
    /// reached through the Window menu.
    private static let pressDelay: TimeInterval = 0.2

    /// AppKit's own title for the item, in the language AppKit is running in.
    private let titles = RecentDocuments.menuTitles(
        localized: Bundle(for: NSApplication.self)
            .localizedString(forKey: "Open Recent", value: nil, table: "MenuCommands"))

    func documents(for pid: pid_t) -> [Document] {
        guard AXIsProcessTrusted(), let submenu = locate(pid: pid)?.menu else { return [] }
        let (items, entries) = read(submenu)
        return RecentDocuments.documentIndices(in: entries).map {
            Document(title: entries[$0].title, element: items[$0])
        }
    }

    /// Every item of the submenu, documents or not, as the filter sees it.
    func read(_ submenu: AXUIElement) -> (items: [AXUIElement], entries: [RecentDocuments.Entry]) {
        let items = children(submenu) ?? []
        let entries = items.map { item in
            RecentDocuments.Entry(
                title: string(of: item, kAXTitleAttribute) ?? "",
                hasShortcut: !(string(of: item, kAXMenuItemCmdCharAttribute) ?? "").isEmpty)
        }
        return (items, entries)
    }

    /// Brings the app forward and has it open the document.
    func open(_ document: Document, pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
        let item = document.element
        DispatchQueue.main.asyncAfter(deadline: .now() + RecentDocumentsService.pressDelay) {
            AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
    }

    /// The menu inside the *Open Recent* item, or nil when the app has none where we look, with
    /// the route to it for `--diagnose-recents`.
    /// - Parameter everywhere: search every menu rather than only File, which only the diagnostic
    ///   does — to say where an app keeps a list the bar cannot find.
    func locate(pid: pid_t, everywhere: Bool = false) -> (menu: AXUIElement, path: String)? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, RecentDocumentsService.messagingTimeout)
        guard let bar = element(application, kAXMenuBarAttribute), let menus = children(bar) else {
            return nil
        }
        let searched = everywhere
            ? Array(menus.indices.dropFirst())
            : menus.indices.contains(RecentDocuments.menuIndex) ? [RecentDocuments.menuIndex] : []
        for index in searched {
            guard let contents = children(menus[index])?.first, let items = children(contents) else {
                continue
            }
            for item in items {
                guard let title = string(of: item, kAXTitleAttribute), titles.contains(title),
                      let submenu = children(item)?.first
                else { continue }
                let parent = string(of: menus[index], kAXTitleAttribute) ?? "?"
                return (submenu, "\(parent) ▸ \(title), menu \(index)")
            }
        }
        return nil
    }

    private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return (value as! AXUIElement)
    }

    private func children(_ parent: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            parent, kAXChildrenAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
