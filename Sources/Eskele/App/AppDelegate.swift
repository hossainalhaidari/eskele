import AppKit
import TrashKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let persistence = Persistence()
    private var settings = Settings()

    private var running: RunningAppsService!
    private var model: DockModel!
    private var coordinator: ScreenCoordinator!
    private var systemDock: SystemDockController!
    private var statusItem: StatusItemController!
    private var trashWatcher: TrashWatcher!
    private var badgeService: BadgeService!
    private var progressService: ProgressService!
    private let fileProgress = FileProgressService()
    private var iconOverrides: IconOverrideService!
    private let attention = AttentionService()
    private let hotKey = GlobalHotKey()
    private let rightCommand = RightCommandWatcher()
    private let modifiers = ModifierWatcher()
    private let activity = ActivityService()
    private let stacks = StackMenuController()
    private let catalog = AppCatalogService()
    private var recents: RecentAppsService!
    private var launcher: LauncherPanelController!
    private let windows = WindowService()
    private let previews = WindowPreviewService()
    private let services = ServicesProvider()
    private var fullScreen: FullScreenMonitor!
    private var windowInfo: WindowInfoService!
    private let spaceWindows = SpaceWindowService()
    private let accessoryApps = AccessoryAppsService()
    private let updates = UpdateService()
    private let preferencesWindow = PreferencesWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private var store: SettingsStore!
    /// While a shortcut is being recorded, none of ours are registered — otherwise pressing the key
    /// already assigned, to record it again, would fire it instead of reaching the recorder.
    private var hotKeysSuspended = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = persistence.loadSettings()
        // A hand-edited file can turn off both routes to the settings window at once; the UI does
        // not allow it, so put the menu-bar icon back rather than launching unreachable.
        if !settings.hasSettingsRoute { settings.showStatusItem = true }
        // A file written before the Custom design existed has no record of one, though it may well
        // describe a custom bar. Capturing here gives it its Custom tile back on first launch.
        settings.captureCustomDesign()
        // Write it back on first launch so the file exists and can be hand-edited before there is a
        // preferences window.
        persistence.save(settings)

        systemDock = SystemDockController(backupURL: persistence.dockBackupURL)
        systemDock.recoverIfNeeded(wantsSuppression: settings.suppressSystemDock)
        systemDock.installTerminationHandlers()

        running = RunningAppsService()
        running.accessoryPIDs = { [weak self] in self?.accessoryApps.pids ?? [] }
        model = DockModel(persistence: persistence, running: running, settings: settings)

        recents = RecentAppsService(persistence: persistence)
        launcher = LauncherPanelController(catalog: catalog, recents: recents)
        launcher.favorites = { [weak self] in self?.model.pinnedAppURLs() ?? [] }
        launcher.onShowSettings = { [weak self] in self?.statusItemDidShowPreferences() }
        catalog.refreshIfStale(maxAge: 0)

        trashWatcher = TrashWatcher()
        trashWatcher.onChange = { [weak self] snapshot in
            self?.model.setTrash(snapshot)
        }
        // TrashKit is a module of its own and knows nothing of `Poll`, so it is paused from here.
        // Not stretched in Low Power Mode: its poll is one `stat`.
        trashWatcher.isPaused = PollGate.shared.isPaused
        PollGate.shared.onChange = { [weak self] in
            self?.trashWatcher.isPaused = PollGate.shared.isPaused
        }
        model.setTrash(trashWatcher.snapshot)

        iconOverrides = IconOverrideService(directory: persistence.iconsURL)
        iconOverrides.onChange = { [weak self] in self?.applyIconOverrides() }
        applyIconOverrides()

        persistence.seedBadgeConfigurationIfMissing()
        badgeService = BadgeService(persistence: persistence)
        badgeService.onChange = { [weak self] in
            guard let self else { return }
            self.model.setBadges(self.badgeService.counts)
        }
        applyBadgeTracking()
        model.setBadges(badgeService.counts)

        attention.onChange = { [weak self] in
            guard let self else { return }
            self.model.setAttention(self.attention.pids)
        }

        persistence.seedProgressConfigurationIfMissing()
        progressService = ProgressService(persistence: persistence)
        progressService.runningPlayers = { [weak self] in
            Set(self?.running.apps.compactMap(\.bundleIdentifier) ?? [])
        }
        fileProgress.onChange = { [weak self] in
            guard let self else { return }
            self.progressService.fileReports = self.fileProgress.reports
        }

        fullScreen = FullScreenMonitor(windows: windows)
        fullScreen.onChange = { [weak self] in self?.refresh() }

        windowInfo = WindowInfoService(windows: windows)
        windowInfo.onChange = { [weak self] in
            guard let self else { return }
            self.model.setWindows(self.windowInfo.windowsByPID)
            self.model.setUnresponsive(self.windowInfo.unresponsivePIDs)
            self.attention.setDialogPIDs(self.windowInfo.dialogPIDs)
            self.fullScreen.setSweepDisplays(self.windowInfo.fullScreenDisplays)
        }
        windowInfo.onSheet = { [weak self] pid in self?.attention.noteSheet(pid: pid) }
        windowInfo.offSpacePIDs = { [weak self] in Set(self?.spaceWindows.countsByPID.keys ?? [:].keys) }
        windowInfo.accessoryPIDs = { [weak self] in self?.accessoryApps.pids ?? [] }
        accessoryApps.hasMinimisedWindow = { [weak self] pid in
            self?.windows.hasMinimisedWindow(pid: pid) ?? false
        }
        accessoryApps.onChange = { [weak self] in
            guard let self else { return }
            // The running list decides whether there is a tile; the window sweep fills it in. An
            // agent that has just opened a window is in neither yet, so both are told.
            self.running.refresh()
            self.windowInfo.refresh()
        }
        spaceWindows.onChange = { [weak self] in
            guard let self else { return }
            self.model.setOffSpaceWindows(self.spaceWindows.countsByPID)
            // A window that has just appeared on another Space may be reachable through the app's
            // focused-window attribute, which the sweep only asks about for these apps.
            self.windowInfo.refresh()
        }
        model.setOffSpaceWindows(spaceWindows.countsByPID)
        model.setWindows(windowInfo.windowsByPID)
        model.cycleWindows = { [weak self] pid in self?.windows.cycleWindow(pid: pid) ?? false }
        model.raiseWindow = { [weak self] reference in self?.windows.raiseWindow(reference) ?? false }
        model.closeWindow = { [weak self] reference in self?.windows.closeWindow(reference) ?? false }
        model.hasWindowInformation = { [weak self] in self?.windows.isTrusted ?? false }

        coordinator = ScreenCoordinator(settings: settings, delegate: self)
        // After the coordinator, not before: this is the one callback that reaches it directly.
        progressService.onChange = { [weak self] in
            guard let self else { return }
            self.coordinator.setProgress(self.settings.showProgress ? self.progressService.reports : [:])
        }
        model.onChange = { [weak self] in self?.refresh() }
        modifiers.onChange = { [weak self] held in
            guard let self else { return }
            // Sampling starts with the chord and stops with it, so nothing is measured while
            // nobody is looking.
            self.activity.setEnabled(held == .activity, pids: self.model.items.compactMap(\.pid))
            self.coordinator.setActivity(self.activity.samples)
            self.coordinator.setOverlay(held)
        }
        activity.onChange = { [weak self] in
            guard let self else { return }
            self.coordinator.setActivity(self.activity.samples)
        }

        store = SettingsStore(settings)
        store.onChange = { [weak self] updated in self?.apply(updated) }

        services.pin = { [weak self] url in self?.model.pin(url: url, atVisualIndex: nil) ?? false }
        NSApp.servicesProvider = services
        // Tells the pasteboard server to re-read our `NSServices` now, rather than whenever it next
        // gets round to scanning. Without it a fresh build's service can take minutes to appear.
        NSUpdateDynamicServices()

        statusItem = StatusItemController(delegate: self, updates: updates)

        applyStatusItem()
        applyDockRequest()
        applyHotKeys()
        applyWindowTracking()
        applyProgressTracking()
        applyAccessoryTracking()
        refresh()
        updates.start()

        if !settings.hasCompletedOnboarding { presentOnboarding() }
    }

    private func presentOnboarding() {
        onboardingWindow.show { [weak self] hideDock, reserveSpace in
            guard let self else { return }
            var updated = self.settings
            updated.hasCompletedOnboarding = true
            updated.suppressSystemDock = hideDock
            updated.reserveScreenSpace = reserveSpace
            self.apply(updated)
        }
    }

    /// Someone has re-opened us. Most often that is a click on our own cell: an agent has no Dock
    /// tile, so `Settings.showAccessoryApps` giving us one is the only way this gets sent by a user
    /// — and `NSWorkspace.openApplication` on an already-running agent otherwise does nothing
    /// visible. Answering it here rather than in the model keeps one implementation for every
    /// sender, including `open` from a shell.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        windows.raiseOwnFrontWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemDock.restoreNow()
        trashWatcher.stop()
        running.stop()
        badgeService.stop()
        iconOverrides.stop()
        progressService.stop()
        fileProgress.stop()
        spaceWindows.stop()
        accessoryApps.stop()
        windowInfo.stopObserving()
        hotKey.unregisterAll()
        modifiers.setChords([:])
        activity.setEnabled(false)
        coordinator.closeAll()
    }

    private func refresh() {
        launcher.source = settings.appsMenuSource
        launcher.showsSystemItems = settings.showSystemItems
        // Only the folders actually on the bar are watched: a folder with no cell has nowhere to
        // draw a bar, so watching it would be work for nothing. See `FileProgressService`.
        fileProgress.folders = settings.showProgress
            ? model.items.compactMap { item in
                guard case .folder(let url) = item.kind else { return nil }
                return url
            }
            : []
        coordinator.setProgress(settings.showProgress ? progressService.reports : [:])
        coordinator.settings = settings
        coordinator.items = model.items
        coordinator.fullScreenDisplays = fullScreen.fullScreenDisplays
        coordinator.sync()
    }

    private func apply(_ newSettings: Settings) {
        settings = newSettings
        // Before saving: a bar that is none of the shipped designs *is* the Custom one, and this is
        // the single funnel every change comes through, so it is the one place that has to notice.
        settings.captureCustomDesign()
        persistence.save(settings)
        store?.sync(settings)
        // Before the rebuild: switching the feature on has to put the agents into the running list
        // first, or the rebuild it triggers would draw the bar as it was and wait for the next scan.
        applyAccessoryTracking()
        model.settings = settings          // triggers a rebuild, which calls refresh()
        applyStatusItem()
        applyDockRequest()
        applyHotKeys()
        applyWindowTracking()
        applyProgressTracking()
        applyBadgeTracking()
        refresh()
    }

    private func applyStatusItem() {
        statusItem.setVisible(settings.showStatusItem)
    }

    private func applyHotKeys() {
        // Nothing to watch for unless at least one overlay is switched on, so the poll stops with
        // the last of them. Outside the suspension: holding the chord while recording should still
        // show which number is which.
        modifiers.setChords(BarOverlay.chords(for: settings))

        guard !hotKeysSuspended else {
            hotKey.unregisterAll()
            rightCommand.isEnabled = false
            return
        }
        hotKey.setReveal(settings.hotKeys(for: .reveal).first) { [weak self] in
            self?.coordinator.toggleReveal()
        }
        hotKey.setSlots(settings.slotHotKeysEnabled ? settings.slotChord.modifiers : nil) { [weak self] slot in
            self?.model.activateSlot(slot)
        }
        hotKey.setFocus(settings.hotKeys(for: .focus).first) { [weak self] in self?.toggleBarKeyboard() }
        // The registerable combinations go to Carbon; the lone right ⌘ is watched for instead.
        // Setting both every time is what makes switching between them a single assignment: each
        // clears itself when the other is chosen.
        hotKey.setAppsMenu(settings.hotKeys(for: .appsMenu).first) { [weak self] in self?.toggleAppsMenu() }
        rightCommand.isEnabled = settings.appsMenuHotKey == .rightCommand
        rightCommand.onTap = { [weak self] in self?.toggleAppsMenu() }
        store?.unavailableHotKeys = hotKey.unavailable
    }

    /// Opens the Apps Menu from the keyboard, or closes it if it is already open.
    ///
    /// The same panel the Apps Menu cell opens, anchored the same way, so the key and the click are
    /// the same affordance — and the panel already takes focus into its search field, which is what
    /// makes "press it and start typing" work.
    private func toggleAppsMenu() {
        guard !launcher.isVisible else {
            launcher.close()
            return
        }
        // Read before the launcher opens: taking the keyboard from the bar is what makes the bar
        // forget where it came from.
        let returnTo = coordinator.keyboardReturnApp
        guard let (anchor, screen, bar) = coordinator.appsMenuAnchor() else { return }
        // Held open exactly as a click holds it: an auto-hiding bar must not slide away underneath
        // the panel it is anchored to while the user is still typing into it.
        bar.beginInteraction()
        let opened = launcher.toggle(
            anchor: anchor, edge: settings.edge, screen: screen, returningTo: returnTo,
            onDismiss: { [weak bar] in bar?.endInteraction() })
        if !opened { bar.endInteraction() }
    }

    /// Moves focus to the bar, or gives it back to the app it came from (§5.27).
    private func toggleBarKeyboard() {
        // From inside the launcher, Eskele is already in front: the app to go back to is the one the
        // launcher took the keyboard from, and closing it must not hand the keyboard back on the way.
        let returnTo = launcher.isVisible ? launcher.relinquishKeyboard() : nil
        coordinator.toggleKeyboard(returningTo: returnTo)
    }

    /// A file appearing in `Icons/` has to reach the cells, and the cells are rebuilt from the
    /// model — so the icons are pushed to the renderer and the bar is told to lay out again.
    private func applyIconOverrides() {
        IconService.shared.setOverrides(iconOverrides.files)
        coordinator?.rebuildIcons()
    }

    private func applyProgressTracking() {
        progressService.tracksMedia = settings.tracksMediaProgress
        if !settings.showProgress { fileProgress.stop() }
    }

    /// The Dock's tiles are only worth reading while the bar is drawing badges. Configured
    /// commands are not gated the same way: their poll is the file's own business, and turning the
    /// badges back on should not mean waiting out a source's interval before its number returns.
    private func applyBadgeTracking() {
        badgeService.readsDockBadges = settings.showBadges
    }

    /// Only one mode needs to know which display each window is on, and it costs an Accessibility
    /// read per window to find out. Setting it re-sweeps, so it is applied alongside the other
    /// settings rather than from `refresh`, which also runs on every window change.
    private func applyWindowTracking() {
        windowInfo.tracksDisplays = settings.screenMode == .perDisplay
    }

    /// Menu-bar apps are scanned for, and admitted to the bar, only while the feature is on.
    ///
    /// Both switches are set from the same expression so they can never disagree: a pid in the
    /// running list that the window sweep does not track would be a tile that never learns how many
    /// windows it has.
    private func applyAccessoryTracking() {
        // The flag before the scan: the scan announces its result, and an announcement that arrived
        // while the running list was still refusing agents would be a rebuild that drew nothing.
        running.includesAccessory = settings.tracksAccessoryApps
        accessoryApps.isEnabled = settings.tracksAccessoryApps
    }

    /// The reservation is a system-wide setting, sized to the bar, which is the same thickness on
    /// every display.
    ///
    /// It is dropped while the bar auto-hides. The parked Dock is out of sight only while the bar
    /// covers it, and a bar that slides away has no business holding space open anyway — the system
    /// Dock gives its space back when it auto-hides, too.
    private func applyDockRequest() {
        systemDock.apply(SystemDockController.Request(
            enabled: settings.suppressSystemDock,
            reserveSpace: settings.reserveScreenSpace && !settings.autohide,
            edge: settings.edge,
            thickness: settings.totalThickness
        ))
    }
}

// MARK: - Bar interaction

extension AppDelegate: BarContentViewDelegate {
    func barContent(_ view: BarContentView, perform action: ClickAction, on item: DockItem) {
        switch action {
        case .activate: model.activate(item)
        case .revealInFinder: model.revealInFinder(item)
        case .toggleHide: model.hide(item)
        case .showOnly: model.showOnly(item)
        case .quit: model.quit(item)
        case .forceRelaunch: model.forceRelaunch(item)
        case .closeWindow: model.close(item)
        }
    }

    func barContent(_ view: BarContentView, stackMenuFor item: DockItem) -> NSMenu? {
        guard case .folder(let url) = item.kind else { return nil }
        return stacks.menu(for: url)
    }

    func barContent(
        _ view: BarContentView, showLauncherAt anchor: NSRect, onDismiss: @escaping () -> Void
    ) -> Bool {
        launcher.toggle(
            anchor: anchor, edge: settings.edge, screen: view.window?.screen,
            returningTo: coordinator.keyboardReturnApp, onDismiss: onDismiss)
    }

    func barContent(_ view: BarContentView, didMove item: DockItem, toVisualIndex index: Int) {
        // Arranging something by hand is a statement that you want it arranged by hand. Without
        // this the drop would be saved to disk and then immediately sorted away, which looks like
        // the bar refusing to move.
        if settings.sortOrder != .manual {
            var updated = settings
            updated.sortOrder = .manual
            apply(updated)
        }
        model.move(item, toVisualIndex: modelIndex(of: index, on: view))
    }

    func barContent(_ view: BarContentView, didDropFiles urls: [URL], on item: DockItem) {
        model.open(urls, with: item)
    }

    func barContent(_ view: BarContentView, didDropFiles urls: [URL], atVisualIndex index: Int) {
        var offset = 0
        let start = modelIndex(of: index, on: view)
        for url in urls where model.pin(url: url, atVisualIndex: start + offset) {
            offset += 1
        }
    }

    /// Translates a drop position on one bar into a position in the model's strip.
    ///
    /// They are the same list in every mode but `ScreenMode.perDisplay`, where a bar shows only the
    /// tasks whose windows are on its display and so numbers its cells differently to the model.
    /// Dropping before a cell means dropping before that same cell in the strip; past the last one
    /// means the end, which is where the unfiltered trailing group already is.
    private func modelIndex(of index: Int, on view: BarContentView) -> Int {
        guard settings.screenMode == .perDisplay, view.items.count != model.items.count else {
            return index
        }
        guard index < view.items.count else { return model.items.count }
        let id = view.items[index].id
        return model.items.firstIndex { $0.id == id } ?? model.items.count
    }

    /// The window a cell stands for: the one it *is* for a window button, or the app's focused
    /// window for an app — the one the user would name if asked what the app is showing, which is
    /// the same window the hover title already describes.
    func barContent(_ view: BarContentView, previewFor item: DockItem) async -> NSImage? {
        guard settings.windowPreviews else { return nil }
        guard let reference = previewTarget(for: item) else { return nil }
        return await previews.preview(for: reference)
    }

    private func previewTarget(for item: DockItem) -> WindowRef? {
        if let window = item.windowReference { return window }
        guard let pid = item.pid else { return nil }
        let windows = windowInfo.windows(for: pid)
        // Unreachable stand-ins name a window we hold nothing for; there is nothing to capture.
        return (windows.first(where: \.isFocused) ?? windows.first).flatMap {
            $0.isReachable ? $0 : nil
        }
    }

    func barContent(_ view: BarContentView, didDragOutOfBar item: DockItem, at screenPoint: NSPoint) {
        _ = screenPoint
        guard item.isPinned else { return }
        model.unpin(item)
    }

    func barContent(_ view: BarContentView, menuFor item: DockItem) -> NSMenu {
        let menu = NSMenu()
        // Left to itself AppKit enables any item whose target answers the selector, which is every
        // item here — the greyed-out states below have to be ours to hold.
        menu.autoenablesItems = false

        switch item.kind {
        case .app:
            let options = NSMenu()
            options.autoenablesItems = false
            options.addItem(action(
                String(localized: "Keep in Bar", comment: "Menu item: pin this app so it stays when it quits"),
                item, #selector(togglePin(_:)), state: item.isPinned))
            addRenameItems(to: options, for: item)
            options.addItem(action(
                String(localized: "Show in Finder", comment: "Menu item: reveal this item in Finder"),
                item, #selector(revealInFinder(_:))))
            options.addItem(.separator())
            options.addItem(addSeparatorItem(before: item))
            let optionsItem = NSMenuItem(
                title: String(localized: "Options", comment: "Submenu holding the less-used item actions"),
                action: nil, keyEquivalent: "")
            optionsItem.submenu = options
            menu.addItem(optionsItem)

            if item.isRunning {
                addWindowSection(to: menu, for: item)
                menu.addItem(.separator())
                menu.addItem(action(
                    item.isHidden
                        ? String(localized: "Show", comment: "Menu item: unhide this app's windows")
                        : String(localized: "Hide", comment: "Menu item: hide this app's windows"),
                    item, #selector(toggleHide(_:))))
                menu.addItem(action(
                    String(localized: "Quit", comment: "Menu item: quit this app"),
                    item, #selector(quitApp(_:))))
            }

        case .window(_, let window):
            let toggle = window.isMinimized
                ? String(localized: "Restore", comment: "Menu item: un-minimise this window")
                : String(localized: "Minimise", comment: "Menu item: minimise this window")
            let minimise = action(toggle, item, #selector(toggleWindowMinimised(_:)))
            menu.addItem(minimise)
            let close = action(
                String(localized: "Close", comment: "Menu item: close this window"),
                item, #selector(closeWindow(_:)))
            // A window on another Space is reached through its entry in the app's Window menu,
            // which is a menu item and has no close button to press.
            close.isEnabled = window.isReachable && !window.isOffSpace
            menu.addItem(close)
            menu.addItem(.separator())
            menu.addItem(action(
                String(localized: "Show in Finder", comment: "Menu item: reveal this item in Finder"),
                item, #selector(revealInFinder(_:))))
            menu.addItem(action(
                String(localized: "Quit \(appName(for: item))", comment: "Menu item: quit the named app"),
                item, #selector(quitApp(_:))))

        case .folder(let url):
            let stack = NSMenuItem(
                title: String(localized: "Contents", comment: "Submenu listing what is inside a pinned folder"),
                action: nil, keyEquivalent: "")
            stack.submenu = stacks.menu(for: url)
            menu.addItem(stack)
            menu.addItem(action(
                String(localized: "Show in Finder", comment: "Menu item: reveal this item in Finder"),
                item, #selector(revealInFinder(_:))))
            addRenameItems(to: menu, for: item)
            menu.addItem(.separator())
            menu.addItem(addSeparatorItem(before: item))
            menu.addItem(action(
                String(localized: "Remove from Bar", comment: "Menu item: unpin this item"),
                item, #selector(togglePin(_:))))

        case .file:
            menu.addItem(action(
                String(localized: "Show in Finder", comment: "Menu item: reveal this item in Finder"),
                item, #selector(revealInFinder(_:))))
            addRenameItems(to: menu, for: item)
            menu.addItem(.separator())
            menu.addItem(addSeparatorItem(before: item))
            menu.addItem(action(
                String(localized: "Remove from Bar", comment: "Menu item: unpin this item"),
                item, #selector(togglePin(_:))))

        case .separator:
            // The divider between the pin group and the tasks is ours, not the user's; it has no
            // stored counterpart to remove.
            guard !item.isImplicitSeparator else { break }
            menu.addItem(action(
                String(localized: "Remove Separator", comment: "Menu item: delete a separator from the bar"),
                item, #selector(togglePin(_:))))

        case .appsMenu:
            for source in AppsMenuSource.allCases {
                let entry = NSMenuItem(
                    title: String(
                        localized: "Show \(source.title)",
                        comment: "Menu item: switch the Apps Menu to the named source, e.g. 'Show All Apps'"),
                    action: #selector(selectAppsMenuSource(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = source.rawValue
                entry.state = settings.appsMenuSource == source ? .on : .off
                menu.addItem(entry)
            }
            menu.addItem(.separator())
            let hide = NSMenuItem(
                title: String(localized: "Hide Apps Menu", comment: "Menu item: take the launcher cell off the bar"),
                action: #selector(hideAppsMenu), keyEquivalent: "")
            hide.target = self
            // Hiding this while the menu-bar icon is gone would take the last route to Settings.
            hide.isEnabled = settings.showStatusItem
            hide.toolTip = settings.showStatusItem
                ? nil
                : String(
                    localized: "Show the menu bar icon first — this menu is the only way back to Settings.",
                    comment: "Why Hide Apps Menu is greyed out")
            menu.addItem(hide)

        case .clock:
            for style in ClockStyle.allCases {
                let entry = NSMenuItem(
                    title: style.title, action: #selector(selectClockStyle(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = style.rawValue
                entry.state = settings.clockStyle == style ? .on : .off
                menu.addItem(entry)
            }
            menu.addItem(.separator())
            menu.addItem(action(
                String(localized: "Open Calendar", comment: "Menu item: open the Calendar app"),
                item, #selector(openCalendarItem(_:))))
            let hideClock = NSMenuItem(
                title: String(localized: "Hide Clock", comment: "Menu item: take the clock off the bar"),
                action: #selector(hideClock), keyEquivalent: "")
            hideClock.target = self
            menu.addItem(hideClock)

        case .trash(let isEmpty):
            menu.addItem(action(
                String(localized: "Open Trash", comment: "Menu item: open the Trash in Finder"),
                item, #selector(openTrash(_:))))
            let empty = action(
                String(localized: "Empty Trash…", comment: "Menu item: empty the Trash, asks first"),
                item, #selector(emptyTrash(_:)))
            empty.isEnabled = !isEmpty
            menu.addItem(empty)
            if let count = item.badge, count > 0 {
                // Pluralised in Localizable.stringsdict — see TrashPrompt for why the rule cannot
                // live in Swift.
                let note = NSMenuItem(
                    title: String(
                        localized: "\(count) items",
                        comment: "How many things are in the Trash, shown greyed out under its menu"),
                    action: nil, keyEquivalent: "")
                note.isEnabled = false
                menu.addItem(.separator())
                menu.addItem(note)
            }
        }

        return menu
    }

    /// Window list, or the single affordance that leads to granting Accessibility.
    private func addWindowSection(to menu: NSMenu, for item: DockItem) {
        guard let pid = item.pid else { return }

        guard windows.isTrusted else {
            menu.addItem(.separator())
            let grant = NSMenuItem(
                title: String(
                    localized: "Enable Window List…",
                    comment: "Menu item: ask for the Accessibility permission the window list needs"),
                action: #selector(requestAccessibility(_:)), keyEquivalent: "")
            grant.target = self
            grant.toolTip = String(
                localized: "Listing an app's windows needs Accessibility access.",
                comment: "Tooltip on the Enable Window List menu item")
            menu.addItem(grant)
            return
        }

        let list = windows.listableWindows(for: pid)
        guard !list.isEmpty else { return }
        let fallback = item.displayName
        menu.addItem(.separator())
        for (index, window) in list.enumerated() {
            var title = window.title.isEmpty ? fallback : window.title
            // A full-screen window has a space to itself, which is worth saying: picking it here
            // switches spaces rather than raising a window in front of you.
            if window.isFullScreen {
                title = String(
                    localized: "\(title) (Full Screen)",
                    comment: "Window menu entry for a window that has a Space to itself")
            }
            let entry = NSMenuItem(title: title, action: #selector(raiseWindow(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = WindowChoice(pid: pid, index: index)
            // Minimised windows are indented, the way the Dock's own window menu marks them.
            entry.indentationLevel = window.isMinimized ? 1 : 0
            menu.addItem(entry)
        }
    }

    private final class WindowChoice: NSObject {
        let pid: pid_t
        let index: Int
        init(pid: pid_t, index: Int) { self.pid = pid; self.index = index }
    }

    @objc private func requestAccessibility(_ sender: NSMenuItem) {
        windows.requestTrust()
        // The prompt only ever appears once per app; send repeat askers straight to the settings pane.
        if !windows.isTrusted { windows.openAccessibilitySettings() }
    }

    @objc private func raiseWindow(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? WindowChoice else { return }
        // Re-read rather than caching AXUIElements: windows close while a menu is open.
        let list = windows.listableWindows(for: choice.pid)
        guard choice.index < list.count else { return }
        windows.raise(list[choice.index], pid: choice.pid)
    }

    /// Rename, and — only once there is one to undo — the way back to the real name.
    ///
    /// Not offered on a window button: the name belongs to the app, and that cell is showing a
    /// window title. Right-clicking one and renaming "the app" from there would be a menu item that
    /// changes something the user is not looking at.
    /// The menu for the empty run beside the cells: the bar itself, rather than anything on it.
    func barContent(_ view: BarContentView, menuForBackgroundAt index: Int) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(addSeparatorItem(atVisualIndex: modelIndex(of: index, on: view)))

        let autohide = NSMenuItem(
            title: String(
                localized: "Auto-hide the Bar",
                comment: "Menu item: let the bar slide away until the pointer reaches the edge"),
            action: #selector(toggleAutohide), keyEquivalent: "")
        autohide.target = self
        autohide.state = settings.autohide ? .on : .off
        menu.addItem(autohide)

        menu.addItem(.separator())
        let about = NSMenuItem(
            title: String(localized: "About Eskele", comment: "Menu item: open the About window"),
            action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(
            title: String(localized: "Quit Eskele", comment: "Menu item: quit this app"),
            action: #selector(quitEskele), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func toggleAutohide() {
        var updated = settings
        updated.autohide.toggle()
        if !updated.autohide { updated.revealHotKeyEnabled = false }
        apply(updated)
    }

    @objc private func quitEskele() {
        NSApp.terminate(nil)
    }

    private func addRenameItems(to menu: NSMenu, for item: DockItem) {
        menu.addItem(action(
            String(localized: "Rename…", comment: "Menu item: give this item a name of your own"),
            item, #selector(renameItem(_:))))
        guard model.customName(of: item) != nil else { return }
        menu.addItem(action(
            String(localized: "Reset Name", comment: "Menu item: drop a custom name and use the real one"),
            item, #selector(resetItemName(_:))))
    }

    @objc private func renameItem(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        guard let name = askForName(current: model.customName(of: item), placeholder: item.displayName)
        else { return }
        model.rename(item, to: name)
    }

    @objc private func resetItemName(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        model.rename(item, to: nil)
    }

    /// Nil when the user cancels; an empty string is a real answer meaning "use the real name".
    private func askForName(current: String?, placeholder: String) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(
            localized: "Rename “\(placeholder)”",
            comment: "Rename dialog title; the placeholder is the item's current name")
        alert.informativeText = String(
            localized: """
                This changes the label on the bar and in the hover title. \
                Leave it empty to go back to the real name.
                """,
            comment: "Rename dialog body")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current ?? ""
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: String(
            localized: "Rename", comment: "Button that confirms the rename dialog"))
        alert.addButton(withTitle: String(
            localized: "Cancel", comment: "Button that dismisses a confirmation without acting"))
        // Otherwise the sheet opens with the buttons focused and the first keystroke is a shortcut.
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func action(
        _ title: String,
        _ item: DockItem,
        _ selector: Selector,
        state: Bool? = nil
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = item.id
        if let state { menuItem.state = state ? .on : .off }
        return menuItem
    }

    /// "Add Separator" for the cell the user pointed at, which is the only thing that gives a
    /// divider a position: it goes on that cell's leading side, the same slot a drop there lands in.
    private func addSeparatorItem(before item: DockItem) -> NSMenuItem {
        let menuItem = action(
            String(localized: "Add Separator", comment: "Menu item: put a divider on the bar"),
            item, #selector(addSeparator(_:)))
        greyOutSeparatorItemWhenSorted(menuItem)
        return menuItem
    }

    /// The same command from the background, where the position is a gap rather than a cell.
    private func addSeparatorItem(atVisualIndex index: Int) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: String(localized: "Add Separator", comment: "Menu item: put a divider on the bar"),
            action: #selector(addSeparatorAtIndex(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = index
        greyOutSeparatorItemWhenSorted(menuItem)
        return menuItem
    }

    /// A sorted bar drops separators rather than ordering them, so one added now would not appear
    /// until the order is the user's again.
    private func greyOutSeparatorItemWhenSorted(_ menuItem: NSMenuItem) {
        menuItem.isEnabled = settings.sortOrder == .manual
        menuItem.toolTip = settings.sortOrder == .manual
            ? nil
            : String(
                localized: "Separators only show while the order is As Arranged.",
                comment: "Why Add Separator is greyed out")
    }

    @objc private func addSeparator(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        model.addSeparator(atVisualIndex: model.items.firstIndex { $0.id == item.id })
    }

    @objc private func addSeparatorAtIndex(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        model.addSeparator(atVisualIndex: index)
    }

    private func item(from sender: Any?) -> DockItem? {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String else { return nil }
        return model.items.first { $0.id == id }
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        model.togglePin(item)
    }

    private func appName(for item: DockItem) -> String {
        if case .window(let ref, _) = item.kind { return ref.name }
        return item.displayName
    }

    @objc private func selectClockStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ClockStyle(rawValue: raw) else { return }
        var updated = settings
        updated.clockStyle = style
        apply(updated)
    }

    @objc private func hideClock() {
        var updated = settings
        updated.showClock = false
        apply(updated)
    }

    @objc private func openCalendarItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        model.activate(item)
    }

    @objc private func closeWindow(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        model.close(item)
    }

    @objc private func toggleWindowMinimised(_ sender: NSMenuItem) {
        guard let item = item(from: sender), let window = item.windowReference else { return }
        windows.setMinimized(window, !window.isMinimized)
        windowInfo.refresh()
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        model.revealInFinder(item)
    }

    @objc private func toggleHide(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        model.hide(item)
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        model.quit(item)
    }

    @objc private func selectAppsMenuSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let source = AppsMenuSource(rawValue: raw) else { return }
        var updated = settings
        updated.appsMenuSource = source
        apply(updated)
    }

    @objc private func hideAppsMenu() {
        var updated = settings
        updated.showAppsMenu = false
        apply(updated)
    }

    @objc private func openTrash(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(Trash.url)
    }

    @objc private func emptyTrash(_ sender: NSMenuItem) {
        guard confirmEmptyTrash() else { return }
        do {
            try Trash.empty()
        } catch TrashError.notPermitted {
            presentAutomationPermissionAlert()
        } catch {
            NSSound.beep()
            NSLog("Eskele: empty trash failed — \(error.localizedDescription)")
        }
    }

    /// The one irreversible thing in the app, so it asks first — the menu item's ellipsis has been
    /// promising this dialog all along.
    ///
    /// The count is stated only when `TrashSnapshot` says it is exact; without Full Disk Access it is
    /// inferred from directory metadata, and a confirmation must not present a guess as a fact.
    private func confirmEmptyTrash() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = TrashPrompt.message(for: trashWatcher.snapshot)
        alert.informativeText = TrashPrompt.detail
        alert.addButton(withTitle: TrashPrompt.confirmTitle).hasDestructiveAction = true
        // Second button picks up Escape, so the safe way out is the one the keyboard falls back to.
        alert.addButton(withTitle: TrashPrompt.cancelTitle)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Emptying the Trash is the one feature that needs a permission, so failing at it has to
    /// explain itself rather than beeping.
    private func presentAutomationPermissionAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(
            localized: "Eskele needs permission to control Finder",
            comment: "Alert title when emptying the Trash is refused by Automation")
        alert.informativeText = String(
            localized: """
                Emptying the Trash has no public API, so Eskele asks Finder to do it.

                Grant access under Privacy & Security ▸ Automation, then try again.
                """,
            comment: "Alert body explaining why the Finder permission is needed")
        alert.addButton(withTitle: String(
            localized: "Open Privacy Settings",
            comment: "Button that opens the Automation pane of System Settings"))
        alert.addButton(withTitle: String(
            localized: "Open Trash Instead",
            comment: "Button that opens the Trash in Finder rather than emptying it here"))
        alert.addButton(withTitle: String(
            localized: "Cancel", comment: "Button that dismisses a confirmation without acting"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
            NSWorkspace.shared.open(url)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(Trash.url)
        default:
            break
        }
    }
}

// MARK: - Preferences

extension AppDelegate: PreferencesActions {
    /// Restores directly rather than through `apply`, which would find nothing to do when the
    /// settings already say the Dock is not hidden — and this button is the rescue for exactly the
    /// case where they say so and the Dock is hidden anyway.
    func restoreSystemDock() {
        systemDock.restoreNow()
        var updated = settings
        updated.suppressSystemDock = false
        updated.reserveScreenSpace = false
        settings = updated
        persistence.save(settings)
        // The panes edit a copy of the settings. Left stale, the next change to any of them would
        // send `suppressSystemDock = true` back through `apply` and hide the Dock again — and
        // `restoreNow` has cleared the controller's last request, so nothing would deduplicate it.
        store?.sync(settings)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItemService.setEnabled(enabled)
    }

    func requestAccessibility() {
        windows.requestTrust()
        if !windows.isTrusted { windows.openAccessibilitySettings() }
        windowInfo.refresh()
    }

    func revealBadgeConfiguration() {
        persistence.seedBadgeConfigurationIfMissing()
        NSWorkspace.shared.activateFileViewerSelecting([persistence.badgesURL])
    }

    func revealProgressConfiguration() {
        persistence.seedProgressConfigurationIfMissing()
        NSWorkspace.shared.activateFileViewerSelecting([persistence.progressURL])
    }

    func setHotKeysSuspended(_ suspended: Bool) {
        guard suspended != hotKeysSuspended else { return }
        hotKeysSuspended = suspended
        applyHotKeys()
    }

    func revealIconOverrides() {
        iconOverrides.seedIfMissing()
        iconOverrides.rescan()
        NSWorkspace.shared.open(persistence.iconsURL)
    }

    /// Writes what is in memory rather than copying `settings.json`: the same bytes, without
    /// depending on the last save having reached the disk.
    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = SettingsFile.suggestedName
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Persistence.encode(settings).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// No confirmation: choosing a file in the open panel is the confirmation, and the settings it
    /// replaces are one Export away from being kept.
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        do {
            apply(settings.adopting(try SettingsFile.read(data)))
        } catch {
            NSLog("Eskele: refused to import \(url.lastPathComponent) (\(error))")
            let alert = NSAlert()
            alert.messageText = SettingsFile.refusal(filename: url.lastPathComponent)
            alert.informativeText = SettingsFile.refusalDetail
            alert.runModal()
        }
    }

    func restoreDefaultSettings() {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = SettingsFile.resetMessage
        alert.informativeText = SettingsFile.resetDetail(keepsCustomDesign: settings.customDesign != nil)
        alert.addButton(withTitle: SettingsFile.resetConfirmTitle).hasDestructiveAction = true
        // Second button picks up Escape, as in the Empty Trash confirmation.
        alert.addButton(withTitle: SettingsFile.cancelTitle)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        apply(settings.adopting(Settings()))
    }
}

// MARK: - Status item

extension AppDelegate: StatusItemControllerDelegate {
    var currentSettings: Settings { settings }

    func statusItemDidChangeSettings(_ newSettings: Settings) {
        apply(newSettings)
    }

    func statusItemDidShowPreferences() {
        preferencesWindow.show(store: store, actions: self, updates: updates)
    }

    func statusItemDidRequestQuit() {
        NSApp.terminate(nil)
    }
}
