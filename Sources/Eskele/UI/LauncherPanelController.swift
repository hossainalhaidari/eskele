import AppKit

/// The launcher popup: a search field, a grouped list of apps, and a way into the Applications
/// folder. The Start button's menu.
///
/// It was an `NSMenu` until it needed a search field (§5.15). A menu runs its own event-tracking
/// loop and keeps the keyboard for itself, so no view inside one can be the first responder; the
/// only way to let the user type is to own the window. What that costs is edge-aware placement and
/// keyboard navigation, both of which are written out below and neither of which is large.
@MainActor
final class LauncherPanelController: NSObject {
    /// Wide enough for a long app name at 14pt without turning into a file browser.
    private static let width: CGFloat = 320
    private static let rowHeight: CGFloat = 40
    private static let headerHeight: CGFloat = 28
    private static let iconSize: CGFloat = 28
    private static let searchHeight: CGFloat = 30
    private static let footerHeight: CGFloat = 34
    /// The row of power buttons above the footer.
    private static let powerHeight: CGFloat = 34
    private static let padding: CGFloat = 8
    /// Clear of the bar, in the way the system's own menus stand clear of the menu bar.
    private static let gap: CGFloat = 6
    private static let screenMargin: CGFloat = 8
    private static let emptyHeight: CGFloat = 64
    /// A click on the launcher button that arrives just after the panel lost key is the *same*
    /// click that dismissed it, and must not reopen what it just closed.
    private static let reopenGuard: TimeInterval = 0.25

    /// Supplied by the model: "favourites" means the apps pinned to the bar.
    var favorites: () -> [URL] = { [] }
    var source: AppsMenuSource = .allApps
    /// Whether All Apps also lists settings panes, folders and the power actions.
    var showsSystemItems = true
    /// The settings button's action. With the menu-bar icon hidden this is the only way in, so it
    /// lives here rather than behind a right-click.
    var onShowSettings: (() -> Void)?

    private let catalog: AppCatalogService
    private let recents: RecentAppsService

    private let panel = LauncherPanel()
    private let searchField = NSSearchField()
    private let settingsButton = NSButton()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let footerButton = NSButton()
    private let powerBar = NSStackView()
    private let power = PowerService()
    /// Collapsed to nothing rather than merely hidden, so the panel loses the height too.
    private var powerBarHeight: NSLayoutConstraint?
    private let emptyLabel = NSTextField(labelWithString: "")

    private enum Row {
        case header(String)
        case app(CatalogEntry)
    }
    private var rows: [Row] = []
    private var iconCache: [String: NSImage] = [:]

    private var anchor = NSRect.zero
    private var edge = BarEdge.bottom
    private var anchorScreen: NSScreen?
    private var onDismiss: (() -> Void)?
    /// Restored when the launcher closes without launching anything, so a stray Escape does not
    /// leave the user typing into an agent that owns no windows.
    private var previousApp: NSRunningApplication?
    private var lastClose = Date.distantPast
    private var isTearingDown = false

    var isVisible: Bool { panel.isVisible }

    init(catalog: AppCatalogService, recents: RecentAppsService) {
        self.catalog = catalog
        self.recents = recents
        super.init()
        buildPanel()
        catalog.onChange = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.reload()
        }
    }

    // MARK: - Presentation

    /// - Parameters:
    ///   - anchor: the launcher button, in screen coordinates.
    ///   - handedOver: who to give the keyboard back to when Eskele is already in front — because
    ///     the bar had it, and is passing on the app *it* took it from.
    /// - Returns: `true` if the panel opened, `false` if this click closed an open one.
    @discardableResult
    func toggle(
        anchor: NSRect,
        edge: BarEdge,
        screen: NSScreen?,
        returningTo handedOver: NSRunningApplication? = nil,
        onDismiss: @escaping () -> Void
    ) -> Bool {
        guard !panel.isVisible, Date().timeIntervalSince(lastClose) > Self.reopenGuard else {
            close()
            return false
        }

        self.anchor = anchor
        self.edge = edge
        self.anchorScreen = screen
        self.onDismiss = onDismiss

        searchField.stringValue = ""
        searchField.placeholderString = String(
            localized: "Search \(source.title)",
            comment: "Search field placeholder, e.g. 'Search All Apps'")
        // Next time this opens, the list should be current.
        catalog.refreshIfStale()
        reload()

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == .current ? handedOver : front
        // An agent is never the active app, and an inactive app's window does not receive typing —
        // so a launcher with a search field has to activate, exactly as Spotlight does.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        return true
    }

    func close(didLaunch: Bool = false) {
        guard panel.isVisible else { return }
        isTearingDown = true
        panel.orderOut(nil)
        isTearingDown = false
        lastClose = Date()

        // Whatever the user was in before stays in front — but only if nobody else has taken the
        // front already. Dismissing by clicking straight into another app must not snatch that app's
        // focus back out from under the click that chose it.
        if !didLaunch, NSWorkspace.shared.frontmostApplication == .current,
           let previousApp, previousApp != .current {
            previousApp.activate()
        }
        previousApp = nil

        let dismiss = onDismiss
        onDismiss = nil
        dismiss?()
    }

    /// Closes for the bar, which is taking the keyboard over, and says who the keyboard would have
    /// gone back to — the bar gives it back there itself, later. Handing it back now as well would
    /// send it to that app and straight out again.
    func relinquishKeyboard() -> NSRunningApplication? {
        let returnApp = previousApp
        close(didLaunch: true)
        return returnApp
    }

    // MARK: - Content

    /// System rows are appended to All Apps rather than given a list of their own, so one search
    /// reaches an application, a settings pane, a folder and Restart alike. They carry system
    /// categories, which sort after every application category — so browsing still opens on apps.
    private func entries() -> [CatalogEntry] {
        switch source {
        case .allApps:
            guard showsSystemItems else { return catalog.entries }
            var all = catalog.entries + SystemCatalog.settingsPanes() + SystemCatalog.folders()
            // The power actions have a row of buttons of their own, permanently on screen, so a
            // section for them as well would be the same four things twice. They still answer to
            // what you type: "restart" should find Restart whether or not you can see it.
            if !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                all += SystemCatalog.power()
            }
            return all
        case .recentApps:
            return recents.entries()
        case .favorites:
            return favorites().map { url in
                let name = FileManager.default.displayName(atPath: url.path)
                return CatalogEntry(url: url, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
            }
        }
    }

    private func reload() {
        let sections = LauncherContent.sections(
            source: source, entries: entries(), query: searchField.stringValue)
        rows = sections.flatMap { section in
            (section.title.map { [Row.header($0)] } ?? []) + section.entries.map(Row.app)
        }

        powerBar.isHidden = !showsSystemItems
        powerBarHeight?.constant = showsSystemItems ? Self.powerHeight : 0

        emptyLabel.stringValue = emptyMessage
        emptyLabel.isHidden = !rows.isEmpty
        scrollView.isHidden = rows.isEmpty

        tableView.reloadData()
        layoutPanel()
        selectFirstApp()
    }

    private var emptyMessage: String {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return String(
                localized: "No apps match “\(query)”",
                comment: "Shown in place of the list when a search finds nothing")
        }
        return switch source {
        case .allApps: String(
            localized: "Still looking…", comment: "Shown while the applications folders are being scanned")
        case .recentApps: String(
            localized: "No recent apps yet", comment: "Shown when nothing has been launched yet")
        case .favorites: String(
            localized: "Pin an app to the bar to see it here",
            comment: "Shown when the Favourites list is empty")
        }
    }

    /// A file's own icon where there is a file, and a symbol where there is not.
    private func icon(for entry: CatalogEntry) -> NSImage {
        if let url = entry.url {
            if let cached = iconCache[url.path] { return cached }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: Self.iconSize, height: Self.iconSize)
            iconCache[url.path] = image
            return image
        }

        let name = entry.symbolName ?? "questionmark"
        if let cached = iconCache["symbol:\(name)"] { return cached }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: Self.iconSize * 0.72, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: entry.name)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        iconCache["symbol:\(name)"] = image
        return image
    }

    // MARK: - Selection

    private func appRow(from index: Int, step: Int) -> Int? {
        var candidate = index
        while candidate >= 0 && candidate < rows.count {
            if case .app = rows[candidate] { return candidate }
            candidate += step
        }
        return nil
    }

    private func selectFirstApp() {
        guard let row = appRow(from: 0, step: 1) else { return }
        select(row)
    }

    private func select(_ row: Int) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func moveSelection(by step: Int) {
        let current = tableView.selectedRow
        let start = current < 0 ? (step > 0 ? 0 : rows.count - 1) : current + step
        // Stopping at the ends rather than wrapping: the list is grouped and long, and a jump from
        // Utilities back to Books reads as a glitch.
        if let row = appRow(from: start, step: step) { select(row) }
    }

    private func activateSelection() {
        guard tableView.selectedRow >= 0, case .app(let entry) = rows[tableView.selectedRow] else { return }
        perform(entry)
    }

    private func perform(_ entry: CatalogEntry) {
        switch entry.action {
        case .launch(let url):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .power(let action):
            // The launcher closes first either way: a confirmation sheet belonging to a panel that
            // is about to vanish would go with it, and the alert has to outlive the list.
            close(didLaunch: true)
            power.perform(action)
            return
        }
        close(didLaunch: true)
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, case .app(let entry) = rows[row] else { return }
        perform(entry)
    }

    @objc private func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        close(didLaunch: true)
    }

    @objc private func showSettings() {
        // `didLaunch` here means "we are handing the front to someone else": the settings window is
        // about to take it, so putting the previously frontmost app back would fight with it.
        close(didLaunch: true)
        onShowSettings?()
    }

    // MARK: - Geometry

    private func height(for row: Row) -> CGFloat {
        switch row {
        case .header: Self.headerHeight
        case .app: Self.rowHeight
        }
    }

    /// Anchored to the inward edge of the launcher button, then clamped into the screen — the same
    /// rule `ItemView.present(_:)` used to get from `NSMenu` for free.
    private func layoutPanel() {
        let visible = (anchorScreen ?? panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let chrome = Self.padding * 2 + Self.searchHeight + Self.footerHeight
            + (showsSystemItems ? Self.powerHeight : 0)
        let list = rows.isEmpty ? Self.emptyHeight : rows.reduce(0) { $0 + height(for: $1) }
        let ceiling = max(Self.rowHeight * 3, visible.height - 2 * Self.screenMargin - chrome)
        let size = NSSize(width: Self.width, height: chrome + min(list, ceiling))

        var origin = switch edge {
        case .bottom: NSPoint(x: anchor.minX, y: anchor.maxY + Self.gap)
        case .left: NSPoint(x: anchor.maxX + Self.gap, y: anchor.maxY - size.height)
        case .right: NSPoint(x: anchor.minX - Self.gap - size.width, y: anchor.maxY - size.height)
        }
        origin.x = min(max(origin.x, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)
        origin.y = min(max(origin.y, visible.minY + Self.screenMargin), visible.maxY - size.height - Self.screenMargin)

        panel.setFrame(NSRect(origin: origin, size: size), display: panel.isVisible)
    }

    // MARK: - Construction

    private func buildPanel() {
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        panel.contentView = effect
        panel.delegate = self

        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 14)
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.gridStyleMask = []
        tableView.intercellSpacing = .zero
        tableView.rowSizeStyle = .custom
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("launcher"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.lineBreakMode = .byTruncatingTail

        footerButton.title = String(
            localized: "Open Applications Folder",
            comment: "Button at the bottom of the launcher")
        footerButton.image = NSImage(
            systemSymbolName: "folder", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        footerButton.imagePosition = .imageLeading
        footerButton.bezelStyle = .accessoryBarAction
        footerButton.isBordered = false
        footerButton.font = .systemFont(ofSize: 13)
        footerButton.contentTintColor = .secondaryLabelColor
        footerButton.target = self
        footerButton.action = #selector(openApplicationsFolder)

        settingsButton.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: String(
                localized: "Settings", comment: "Name of the settings window"))?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        settingsButton.imagePosition = .imageOnly
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.isBordered = false
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.toolTip = String(
            localized: "Eskele Settings", comment: "Tooltip on the launcher's settings button")
        settingsButton.setAccessibilityLabel(String(
            localized: "Settings", comment: "Name of the settings window"))
        // A search field swallows Tab and the list is driven from it; keeping the button out of the
        // key loop stops Tab from quietly moving focus off the field mid-search.
        settingsButton.refusesFirstResponder = true
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)

        buildPowerBar()

        let separator = NSBox()
        separator.boxType = .separator

        for view in
            [searchField, settingsButton, scrollView, emptyLabel, separator, powerBar, footerButton]
            as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(view)
        }

        let padding = Self.padding
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: effect.topAnchor, constant: padding),
            searchField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: padding),
            searchField.trailingAnchor.constraint(
                equalTo: settingsButton.leadingAnchor, constant: -padding / 2),
            searchField.heightAnchor.constraint(equalToConstant: Self.searchHeight),

            settingsButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -padding),
            settingsButton.widthAnchor.constraint(equalToConstant: Self.searchHeight),
            settingsButton.heightAnchor.constraint(equalToConstant: Self.searchHeight),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: padding),
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: padding),
            emptyLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -padding),

            separator.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: powerBar.topAnchor),

            powerBar.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: padding),
            powerBar.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -padding),
            powerBar.bottomAnchor.constraint(equalTo: footerButton.topAnchor),

            footerButton.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: padding + 4),
            footerButton.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -padding),
            footerButton.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            footerButton.heightAnchor.constraint(equalToConstant: Self.footerHeight),
        ])

        let height = powerBar.heightAnchor.constraint(equalToConstant: Self.powerHeight)
        height.isActive = true
        powerBarHeight = height
    }

    /// Sleep, Log Out, Restart and Shut Down as a permanent row, rather than four rows in a list you
    /// have to scroll to the bottom of.
    ///
    /// Icon-only and evenly spread, so the row reads as a strip of controls rather than as more
    /// list. Every one of them names itself in a tooltip, because a power symbol and a restart
    /// symbol are not worth guessing between.
    private func buildPowerBar() {
        powerBar.orientation = .horizontal
        powerBar.distribution = .fillEqually
        powerBar.spacing = 0

        for (index, action) in PowerAction.allCases.enumerated() {
            let button = NSButton()
            button.image = NSImage(
                systemSymbolName: action.symbolName, accessibilityDescription: action.searchName)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            button.imagePosition = .imageOnly
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = action.title
            button.setAccessibilityLabel(action.searchName)
            // The search field owns the keyboard the whole time the launcher is open; letting Tab
            // reach these would move focus off the field mid-search.
            button.refusesFirstResponder = true
            button.tag = index
            button.target = self
            button.action = #selector(powerButtonClicked(_:))
            powerBar.addArrangedSubview(button)
        }
    }

    @objc private func powerButtonClicked(_ sender: NSButton) {
        guard PowerAction.allCases.indices.contains(sender.tag) else { return }
        let action = PowerAction.allCases[sender.tag]
        // Closed first: the confirmation alert has to outlive the panel it was asked from.
        close(didLaunch: true)
        power.perform(action)
    }
}

// MARK: - Window

extension LauncherPanelController: NSWindowDelegate {
    /// Clicking anywhere else — another app, the desktop, the bar — dismisses, which is what a menu
    /// does and what the user expects from something that took their focus.
    func windowDidResignKey(_ notification: Notification) {
        guard !isTearingDown else { return }
        close()
    }
}

// MARK: - Search field

extension LauncherPanelController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    /// The search field keeps the first responder the whole time the launcher is open, so the keys
    /// that drive the list have to be borrowed from it here.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            activateSelection()
        case #selector(NSResponder.cancelOperation(_:)):
            // Escape backs out one step at a time: clear the search, then close.
            if searchField.stringValue.isEmpty {
                close()
            } else {
                searchField.stringValue = ""
                reload()
            }
        default:
            return false
        }
        return true
    }
}

// MARK: - List

extension LauncherPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        height(for: rows[row])
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        LauncherRowView()
    }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let identifier = NSUserInterfaceItemIdentifier("header")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? LauncherHeaderCell(identifier: identifier)
            cell.textField?.stringValue = title
            return cell
        case .app(let entry):
            let identifier = NSUserInterfaceItemIdentifier("app")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? LauncherAppCell(identifier: identifier, iconSize: Self.iconSize)
            cell.textField?.stringValue = entry.name
            cell.imageView?.image = icon(for: entry)
            return cell
        }
    }
}

// MARK: - Cells

/// Draws its own selection so the highlight is a rounded pill like a menu's, and reports itself as
/// emphasized whatever the first responder is — the search field holds that the whole time, and an
/// unemphasized grey highlight would read as "this list is not listening".
private final class LauncherRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set { _ = newValue }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 2), xRadius: 6, yRadius: 6).fill()
    }

    /// A group row is drawn as an opaque gradient slab with a rule under it — a source-list look
    /// that reads as a seam across the blur here. The panel's own material is the background.
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSeparator(in dirtyRect: NSRect) {}
}

private final class LauncherAppCell: NSTableCellView {
    init(identifier: NSUserInterfaceItemIdentifier, iconSize: CGFloat) {
        super.init(frame: .zero)
        self.identifier = identifier

        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        imageView = image
        textField = label

        for view in [image, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: iconSize),
            image.heightAnchor.constraint(equalToConstant: iconSize),

            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            textField?.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
        }
    }
}

private final class LauncherHeaderCell: NSTableCellView {
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        textField = label

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// A heading is not selectable, so it must never take the emphasized text colour.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { textField?.textColor = .secondaryLabelColor }
    }
}
