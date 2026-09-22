import AppKit

@MainActor
protocol StatusItemControllerDelegate: AnyObject {
    var currentSettings: Settings { get }
    func statusItemDidChangeSettings(_ settings: Settings)
    func statusItemDidShowPreferences()
    func statusItemDidRequestQuit()
}

/// The only always-available affordance we have. It matters more than usual here: while the system
/// Dock is suppressed this menu is the user's way back out.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var delegate: StatusItemControllerDelegate?
    private let updates: UpdateService

    init(delegate: StatusItemControllerDelegate, updates: UpdateService) {
        self.delegate = delegate
        self.updates = updates
        super.init()
    }

    /// Installs or removes the menu-bar icon.
    ///
    /// Removing is the real thing rather than a zero-length item: a hidden status item still holds
    /// its slot in the menu bar and still shows up as a gap on a crowded one.
    func setVisible(_ visible: Bool) {
        guard visible != (statusItem != nil) else { return }
        guard visible else {
            statusItem.map(NSStatusBar.system.removeStatusItem)
            statusItem = nil
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusItemIcon.make()

        let menu = NSMenu()
        menu.delegate = self
        // Each item's `isEnabled` is decided in `menuNeedsUpdate`. Left on, AppKit would enable
        // every item whose target answers its action — which unlocked Hide Menu Bar Icon while it
        // was the last route to Settings.
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let delegate else { return }
        let settings = delegate.currentSettings
        menu.removeAllItems()

        // First, and on its own: the one item that answers "what kind of bar is this?", where
        // everything under it answers "and how exactly?".
        //
        // The designs themselves rather than a submenu holding them. It makes the menu as wide as
        // four tiles, which is the price of being able to read the answer without opening anything.
        menu.addItem(.sectionHeader(title: String(
            localized: "Design", comment: "Menu heading over the design tiles")))
        let designRow = NSMenuItem()
        designRow.view = DesignMenuRow(settings: settings) { [weak self] preset in
            self?.selectDesign(preset)
        }
        menu.addItem(designRow)
        menu.addItem(.separator())

        let preferences = NSMenuItem(
            title: String(localized: "Settings…", comment: "Menu item: open the settings window"),
            action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        if updates.isAvailable { menu.addItem(updateItem()) }

        let hideIcon = NSMenuItem(
            title: String(
                localized: "Hide Menu Bar Icon",
                comment: "Menu item: remove Eskele's own icon from the system menu bar"),
            action: #selector(hideStatusItem), keyEquivalent: "")
        hideIcon.target = self
        hideIcon.isEnabled = settings.showAppsMenu
        hideIcon.toolTip = settings.showAppsMenu
            ? String(
                localized: "Reach Settings from the gear in the Apps Menu. Bring the icon back from there.",
                comment: "Tooltip: where Settings still is once the menu bar icon is hidden")
            : String(
                localized: "Turn the Apps Menu on first — it would otherwise be the last way back to Settings.",
                comment: "Tooltip: why Hide Menu Bar Icon is greyed out")
        menu.addItem(hideIcon)

        menu.addItem(toggle(
            String(
                localized: "Auto-hide the Bar",
                comment: "Menu item: let the bar slide away until the pointer reaches the edge"),
            #selector(toggleAutohide), settings.autohide))

        menu.addItem(.separator())
        let about = NSMenuItem(
            title: String(localized: "About Eskele", comment: "Menu item: open the About window"),
            action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(
            title: String(localized: "Quit Eskele", comment: "Menu item: quit this app"),
            action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Names the version when a scheduled check has found one and is holding it back — this menu is
    /// the one place an agent can say so without interrupting. Either way the click is a check, which
    /// is also what brings a waiting update's alert forward.
    private func updateItem() -> NSMenuItem {
        let title = updates.waitingVersion.map {
            String(
                localized: "Update to Eskele \($0)…",
                comment: "Menu item: an update was found and is waiting. The argument is its version")
        } ?? String(localized: "Check for Updates…", comment: "Menu item: look for a newer version now")
        let item = NSMenuItem(title: title, action: #selector(checkForUpdates), keyEquivalent: "")
        item.target = self
        // Greyed out while a check or a background download is already running.
        item.isEnabled = updates.canCheck
        return item
    }

    private func toggle(_ title: String, _ action: Selector, _ on: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private func mutate(_ change: (inout Settings) -> Void) {
        guard let delegate else { return }
        var settings = delegate.currentSettings
        change(&settings)
        delegate.statusItemDidChangeSettings(settings)
    }

    private func selectDesign(_ preset: DesignPreset) {
        // A click inside a custom view does not dismiss the menu the way an ordinary item's does.
        // Close it first, so the bar is seen changing rather than redrawn under an open menu.
        statusItem?.menu?.cancelTracking()
        mutate { $0 = preset.applied(to: $0) }
    }

    @objc private func hideStatusItem() { mutate { $0.showStatusItem = false } }

    @objc private func toggleAutohide() {
        mutate {
            $0.autohide.toggle()
            if !$0.autohide { $0.revealHotKeyEnabled = false }
        }
    }

    @objc private func showPreferences() { delegate?.statusItemDidShowPreferences() }
    @objc private func checkForUpdates() { updates.checkForUpdates() }
    @objc private func showAbout() { AboutPanel.show() }
    @objc private func quit() { delegate?.statusItemDidRequestQuit() }
}
