import AppKit
import TrashKit

/// The ordered contents of the bar, and every mutation the user can make to it.
///
/// Order follows the plan: pinned apps and separators in the order the user arranged them, then any
/// running app that is not pinned, then pinned folders and files, then the Trash. In labelled mode
/// the pinned launchers that are *not* running are lifted out of that run into a compact group at
/// the leading end — see `Settings.groupsPins`.
@MainActor
final class DockModel {
    private(set) var items: [DockItem] = []
    var onChange: (() -> Void)?

    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            persistence.save(settings)
            rebuild()
        }
    }

    private var pinned: [PersistedItem]
    private let persistence: Persistence
    private let running: RunningAppsService
    private var trash: TrashSnapshot = .empty
    private var windowsByPID: [pid_t: [WindowRef]] = [:]
    private var attentionPIDs: Set<pid_t> = []
    private var unresponsivePIDs: Set<pid_t> = []
    /// Full-screen windows on other Spaces, which Accessibility cannot report. See
    /// `SpaceWindowService`.
    private var offSpaceWindows: [pid_t: Int] = [:]
    private var badges: [String: Int] = [:]
    /// Read once per rebuild rather than once per item. A process rather than a bundle ID, so that
    /// of two copies of one app only the one actually in front draws as frontmost.
    private var frontmostPID: pid_t?
    /// Likewise: this is derived work, and `decorate` runs for every cell on the bar.
    private var launchingPIDs: Set<pid_t> = []

    /// Where the user has dragged running apps that have no stored slot, by bundle ID.
    ///
    /// Deliberately not persisted: an app that is not pinned has no place on the bar once it quits,
    /// so an arrangement of them cannot outlive the session that made it — the same bargain the
    /// Windows taskbar strikes.
    private var runningOrder: [String] = []
    /// Where the user has dragged an app's window buttons, by window id. Same bargain.
    private var windowOrder: [pid_t: [String]] = [:]

    /// Supplied by the app delegate; returns true when it actually moved to another window.
    var cycleWindows: ((pid_t) -> Bool)?
    var raiseWindow: ((WindowRef) -> Bool)?
    var closeWindow: ((WindowRef) -> Bool)?
    /// Whether the window lists mean anything. Without Accessibility every app reports zero
    /// windows, which must not be mistaken for "this app has nothing open".
    var hasWindowInformation: (() -> Bool)?

    /// Bundle ID reserved for badging the Trash from `badges.json`.
    static let trashBadgeKey = "trash"

    init(persistence: Persistence, running: RunningAppsService, settings: Settings) {
        self.persistence = persistence
        self.running = running
        self.settings = settings

        let stored = persistence.loadLayout()
        if stored.isEmpty {
            pinned = persistence.defaultLayout()
            persistence.saveLayout(pinned)
        } else {
            pinned = stored
        }

        running.onChange = { [weak self] in self?.rebuild() }
        rebuild()
    }

    // MARK: - Inputs

    func setWindows(_ windows: [pid_t: [WindowRef]]) {
        guard windowsByPID != windows else { return }
        windowsByPID = windows
        rebuild()
    }

    func setTrash(_ snapshot: TrashSnapshot) {
        guard trash != snapshot else { return }
        trash = snapshot
        rebuild()
    }

    func setOffSpaceWindows(_ counts: [pid_t: Int]) {
        guard offSpaceWindows != counts else { return }
        offSpaceWindows = counts
        rebuild()
    }

    func setUnresponsive(_ pids: Set<pid_t>) {
        guard unresponsivePIDs != pids else { return }
        unresponsivePIDs = pids
        rebuild()
    }

    func setAttention(_ pids: Set<pid_t>) {
        guard attentionPIDs != pids else { return }
        attentionPIDs = pids
        rebuild()
    }

    func setBadges(_ counts: [String: Int]) {
        guard badges != counts else { return }
        badges = counts
        rebuild()
    }

    // MARK: - Building

    func rebuild() {
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        launchingPIDs = running.launchingPIDs
        var resolved: [(PersistedItem, DockItem)] = []
        var dropped = false

        for entry in pinned {
            if entry.kind == .separator {
                resolved.append((entry, DockItem(kind: .separator(entry.token ?? UUID().uuidString), isPinned: true)))
                continue
            }
            guard let url = entry.resolveURL() else {
                dropped = true
                continue
            }
            switch entry.kind {
            case .app:
                let ref = AppRef(
                    bundleID: entry.bundleID ?? Bundle(url: url)?.bundleIdentifier ?? url.path,
                    url: url,
                    // Into the ref as well as onto the item: the ref is what a window button, the
                    // Quit menu item and the launcher all read, so a renamed app has to carry its
                    // name in the thing that travels with it.
                    name: entry.customName ?? entry.name
                        ?? url.deletingPathExtension().lastPathComponent
                )
                resolved.append((entry, named(entry, DockItem(kind: .app(ref), isPinned: true))))
            case .folder:
                resolved.append((entry, named(entry, DockItem(kind: .folder(url), isPinned: true))))
            case .file:
                resolved.append((entry, named(entry, DockItem(kind: .file(url), isPinned: true))))
            case .separator:
                break
            }
        }

        if dropped {
            // An app the user pinned has been uninstalled; forget it rather than showing a hole.
            pinned = resolved.map(\.0)
            persistence.saveLayout(pinned)
        }

        var groups = BarComposition.groups(
            for: resolved.map { decorated($0.1) }, groupsPins: settings.groupsPins)

        if settings.showRunningUnpinned {
            let pinnedIDs = Set(resolved.compactMap { pair -> String? in
                if case .app(let ref) = pair.1.kind { return ref.bundleID }
                return nil
            })
            for app in orderedRunningApps(excluding: pinnedIDs) {
                // The URL LaunchServices will launch, not merely the bundle the process was started
                // from — see `ApplicationURL`. This is the cell a click, a pin, a file drop and
                // Reveal in Finder all read their URL from, so getting it right here fixes all four.
                guard let id = app.bundleIdentifier,
                      let url = ApplicationURL.launchable(for: app) else { continue }
                let ref = AppRef(
                    bundleID: id,
                    url: url,
                    name: app.localizedName ?? url.deletingPathExtension().lastPathComponent
                )
                var item = DockItem(kind: .app(ref), isPinned: false)
                // Every copy after the first is its own cell, keyed by its own process — see
                // `DockItem.instance`.
                if running.app(withBundleID: id)?.processIdentifier != app.processIdentifier {
                    item.instance = app.processIdentifier
                }
                groups.tasks.append(decorated(item))
            }
        }

        // Sorted before the split, so an app's windows stay together under its own name rather than
        // scattering themselves through the bar by window title.
        groups.pins = BarComposition.sorted(groups.pins, by: settings.sortOrder)
        groups.tasks = BarComposition.sorted(groups.tasks, by: settings.sortOrder)

        // Splitting into per-window buttons comes last, so an app is one entry everywhere the
        // grouping rules are applied and several only where they are drawn.
        groups.tasks = groups.tasks.flatMap(expand)

        var trash: [DockItem] = []
        if settings.showTrash { trash.append(trashItem()) }
        // After the Trash, so the clock is the very last thing on the bar — the end of the strip is
        // where every taskbar has put one, and it is the corner the eye goes to for the time.
        if settings.showClock { trash.append(DockItem(kind: .clock)) }

        items = BarComposition.strip(
            leading: settings.showAppsMenu ? [DockItem(kind: .appsMenu)] : [],
            groups: groups,
            trailing: trash)
        // Numbered here rather than by each bar: `activateSlot` counts the whole strip, and a bar
        // that shows only some of it has to draw those same numbers or the overlay is a lie.
        for (index, slot) in BarComposition
            .slotNumbers(for: items, limit: GlobalHotKey.slotCount).enumerated() {
            items[index].slotNumber = slot
        }
        onChange?()
    }

    private func named(_ entry: PersistedItem, _ item: DockItem) -> DockItem {
        var copy = item
        copy.customName = entry.customName
        return copy
    }

    private func decorated(_ item: DockItem) -> DockItem {
        var copy = item
        decorate(&copy)
        return copy
    }

    /// Fills in everything that comes from outside the stored layout: whether the app is running,
    /// its windows, its badge, whether it is asking to be looked at.
    private func decorate(_ item: inout DockItem) {
        guard case .app(let ref) = item.kind else { return }
        if settings.showBadges { item.badge = badges[ref.bundleID] }
        guard let app = runningApp(ref, instance: item.instance) else { return }
        let pid = app.processIdentifier
        let windows = windowsByPID[pid] ?? []
        item.isRunning = true
        item.isFrontmost = pid == frontmostPID
        item.isHidden = app.isHidden
        item.pid = pid
        item.launchDate = app.launchDate
        item.isLaunching = launchingPIDs.contains(pid)
        item.isUnresponsive = unresponsivePIDs.contains(pid)
        // Counted, not just listed: without this an app whose second window is full-screen on
        // another Space shows one dash and looks like it has one window.
        let elsewhere = unreachableCount(pid: pid, windows: windows)
        item.windowCount = windows.count + elsewhere
        item.isFullScreen = elsewhere > 0 || windows.contains(where: \.isFullScreen)
        item.needsAttention = settings.highlightAttention && attentionPIDs.contains(pid)
        // Empty unless the displays are being tracked at all, which is what makes every other mode
        // — and this one without Accessibility — fall through the filter unchanged.
        item.displays = Set(windows.compactMap(\.display))
        // The focused window is the one the user would name if asked what the app is showing.
        item.windowTitle = (windows.first(where: \.isFocused) ?? windows.first)?.title
    }

    private func trashItem() -> DockItem {
        var item = DockItem(kind: .trash(isEmpty: trash.isEmpty))
        if settings.showBadges {
            // A badge source can claim the Trash cell by bundle ID; otherwise it counts itself.
            item.badge = badges[DockModel.trashBadgeKey] ?? (trash.count > 0 ? trash.count : nil)
        }
        return item
    }

    /// Running apps the user has not pinned, in the order they have dragged them into.
    private func orderedRunningApps(excluding pinnedIDs: Set<String>) -> [NSRunningApplication] {
        let candidates = running.apps.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return !pinnedIDs.contains(id) && app.bundleURL != nil
        }
        // Apps the user has never moved keep the order the workspace reports, after the ones they
        // have — appending is the only placement that does not disturb an arrangement.
        let rank = Dictionary(uniqueKeysWithValues: runningOrder.enumerated().map { ($0.element, $0.offset) })
        return candidates.enumerated().sorted { left, right in
            let l = rank[left.element.bundleIdentifier ?? ""] ?? (runningOrder.count + left.offset)
            let r = rank[right.element.bundleIdentifier ?? ""] ?? (runningOrder.count + right.offset)
            return l < r
        }.map(\.element)
    }

    /// Splits a running app into one item per window, when the settings call for it.
    ///
    /// Only in full-width labelled mode: anywhere else there is no room for a title, and a row of
    /// identical icons would say nothing about which window is which.
    private func expand(_ item: DockItem) -> [DockItem] {
        guard settings.splitsWindows,
              case .app(let ref) = item.kind,
              item.isRunning,
              let pid = item.pid
        else { return [item] }

        let known = ordered(windowsByPID[pid] ?? [], for: pid)
        let windows = known + offSpaceRefs(for: pid, named: ref.name, known: known)
        guard !windows.isEmpty else { return [item] }

        return windows.map { window in
            DockItem(
                kind: .window(ref, window),
                isPinned: false,
                isRunning: true,
                // Only the app's focused window counts as frontmost, or every window of the active
                // app would light up at once.
                isFrontmost: item.isFrontmost && window.isFocused,
                isHidden: item.isHidden,
                windowCount: 1,
                pid: pid,
                instance: item.instance,
                badge: nil,
                needsAttention: item.needsAttention,
                isFullScreen: window.isFullScreen,
                displays: window.display.map { [$0] } ?? [])
        }
    }

    /// Stand-ins for the full-screen windows on other Spaces. They carry no AX element, so they are
    /// named after their app and marked unreachable; the alternative is leaving a window the user
    /// plainly has open off the bar entirely.
    private func offSpaceRefs(for pid: pid_t, named name: String, known: [WindowRef]) -> [WindowRef] {
        (0..<unreachableCount(pid: pid, windows: known)).map { index in
            WindowRef(
                pid: pid,
                title: String(
                    localized: "\(name) — Full Screen",
                    comment: "Stand-in name for an app's full-screen window on another Space"),
                isMinimized: false,
                isFullScreen: true,
                isOffSpace: true,
                isReachable: false,
                isFocused: false,
                duplicateIndex: index)
        }
    }

    /// Full-screen windows the window server can see but that we hold no handle for at all.
    ///
    /// Everything reachable another way — the focused/main attributes, the element cache, the app's
    /// Window menu — already appears in `windows` with a real title, so subtracting those is what
    /// stops the same window being counted twice, once properly and once as a nameless stand-in.
    private func unreachableCount(pid: pid_t, windows: [WindowRef]) -> Int {
        max(0, (offSpaceWindows[pid] ?? 0) - windows.count { $0.isOffSpace })
    }

    private func ordered(_ windows: [WindowRef], for pid: pid_t) -> [WindowRef] {
        guard let order = windowOrder[pid], !order.isEmpty else { return windows }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return windows.enumerated().sorted { left, right in
            let l = rank[left.element.id] ?? (order.count + left.offset)
            let r = rank[right.element.id] ?? (order.count + right.offset)
            return l < r
        }.map(\.element)
    }

    // MARK: - Mutation

    func isPinned(_ item: DockItem) -> Bool {
        pinned.contains { $0.identity == persistedIdentity(for: item) }
    }

    @discardableResult
    func pin(url: URL, atVisualIndex index: Int?) -> Bool {
        guard let entry = PersistedItem.make(for: url) else { return false }
        guard !pinned.contains(where: { $0.identity == entry.identity }) else { return false }
        let insertion = index.map { pinnedInsertionIndex(forVisualIndex: $0) } ?? pinned.count
        pinned.insert(entry, at: min(max(0, insertion), pinned.count))
        persistence.saveLayout(pinned)
        rebuild()
        return true
    }

    func unpin(_ item: DockItem) {
        let identity = persistedIdentity(for: item)
        guard pinned.contains(where: { $0.identity == identity }) else { return }
        pinned.removeAll { $0.identity == identity }
        persistence.saveLayout(pinned)
        rebuild()
    }

    /// The name a cell has been given, if any — what "Reset Name" is offered for.
    func customName(of item: DockItem) -> String? {
        let identity = persistedIdentity(for: item)
        return pinned.first { $0.identity == identity }?.customName
    }

    /// Renames a cell, or clears the name when given nil or nothing but spaces.
    ///
    /// An app that is not pinned is pinned first, in the place it already occupies. A name is a
    /// deliberate statement that you want this thing to stay — the same reading `move` gives to
    /// dragging a running app into the pinned run — and the alternative is a rename that silently
    /// evaporates when the app quits.
    func rename(_ item: DockItem, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed

        var identity = persistedIdentity(for: item)
        if !pinned.contains(where: { $0.identity == identity }) {
            guard let url = item.url,
                  pin(url: url, atVisualIndex: items.firstIndex { $0.id == item.id })
            else { return }
            identity = persistedIdentity(for: item)
        }
        guard let index = pinned.firstIndex(where: { $0.identity == identity }),
              pinned[index].customName != value
        else { return }

        pinned[index].customName = value
        persistence.saveLayout(pinned)
        rebuild()
    }

    func togglePin(_ item: DockItem) {
        if isPinned(item) {
            unpin(item)
        } else if let url = item.url {
            pin(url: url, atVisualIndex: nil)
        }
    }

    func addSeparator(atVisualIndex index: Int?) {
        let insertion = index.map { pinnedInsertionIndex(forVisualIndex: $0) } ?? pinned.count
        pinned.insert(.separator(), at: min(max(0, insertion), pinned.count))
        persistence.saveLayout(pinned)
        rebuild()
    }

    /// Moves an item to a new place in the strip.
    ///
    /// Three kinds of thing can be dragged, and each has its own notion of "position":
    ///
    /// - A **pinned** item has a stored slot, so this rewrites the layout on disk.
    /// - A **running app with no stored slot** has only a session order. Dropped among the other
    ///   running apps it is reordered there; dropped anywhere else — into the pinned run, or into
    ///   the pin group — the user plainly means to pin it, which is what used to happen to every
    ///   such drag whether they meant it or not.
    /// - A **window button** is reordered within its own app. Dragged clear of its app's run it
    ///   moves the whole app instead, since a window cannot outrank the app it belongs to.
    func move(_ item: DockItem, toVisualIndex index: Int) {
        if item.isWindow {
            moveWindow(item, toVisualIndex: index)
            return
        }

        let identity = persistedIdentity(for: item)
        if let current = pinned.firstIndex(where: { $0.identity == identity }) {
            var target = pinnedInsertionIndex(forVisualIndex: index)
            let entry = pinned.remove(at: current)
            if target > current { target -= 1 }
            pinned.insert(entry, at: min(max(0, target), pinned.count))
            persistence.saveLayout(pinned)
            rebuild()
            return
        }

        if case .app(let ref) = item.kind, isWithinRunningGroup(index) {
            reorderRunning(ref.bundleID, toVisualIndex: index)
            return
        }
        if let url = item.url { pin(url: url, atVisualIndex: index) }
    }

    /// Visual positions occupied by running apps with no stored slot, plus the slot just past the
    /// last of them — dropping at the far end of the group has to count as inside it.
    private func isWithinRunningGroup(_ index: Int) -> Bool {
        ReorderSolver.contains(items.indices.filter { runningGroupBundleID(at: $0) != nil }, index: index)
    }

    private func runningGroupBundleID(at index: Int) -> String? {
        guard items.indices.contains(index) else { return nil }
        let item = items[index]
        guard item.isTask, item.isRunning, !item.isPinned else { return nil }
        switch item.kind {
        case .app(let ref), .window(let ref, _): return ref.bundleID
        default: return nil
        }
    }

    private func reorderRunning(_ bundleID: String, toVisualIndex index: Int) {
        // The group in visual order, one entry per app — an app split into window buttons still
        // moves as a unit — remembering where each one starts.
        var group: [ReorderSolver.Entry] = []
        for position in items.indices {
            guard let id = runningGroupBundleID(at: position) else { continue }
            if !group.contains(where: { $0.id == id }) {
                group.append(ReorderSolver.Entry(id: id, start: position))
            }
        }
        runningOrder = ReorderSolver.reordered(group, moving: bundleID, to: index)
        rebuild()
    }

    /// Reorders one window inside its own app, or hands the drag to the app when it left the run.
    private func moveWindow(_ item: DockItem, toVisualIndex index: Int) {
        guard let pid = item.pid, let reference = item.windowReference else { return }
        let span = items.indices.filter { items[$0].pid == pid && items[$0].isWindow }
        guard let first = span.first else { return }

        guard ReorderSolver.contains(span, index: index) else {
            // Out of its app's run: move the app, keeping its windows together.
            if case .window(let ref, _) = item.kind {
                let base = DockItem(kind: .app(ref), isPinned: isPinned(DockItem(kind: .app(ref))))
                move(decorated(base), toVisualIndex: index)
            }
            return
        }

        let order = span.map { items[$0].id }
        windowOrder[pid] = ReorderSolver.moved(order, id: reference.id, toOffset: index - first)
        rebuild()
    }

    private func persistedIdentity(for item: DockItem) -> String {
        switch item.kind {
        case .app(let ref): "app:\(ref.bundleID)"
        case .folder(let url): "folder:\(url.path)"
        case .file(let url): "file:\(url.path)"
        case .separator(let token): "sep:\(token)"
        case .trash: "trash"
        case .appsMenu: "apps-menu"
        case .clock: "clock"
        // A window button stands for its app. Anything else and a split app would be invisible to
        // the layout arithmetic below, even though it occupies cells the user drags past.
        case .window(let ref, _): "app:\(ref.bundleID)"
        }
    }

    private func pinnedInsertionIndex(forVisualIndex index: Int) -> Int {
        ReorderSolver.storedInsertionIndex(
            visualIdentities: items.map(persistedIdentity),
            stored: pinned.map(\.identity),
            index: index)
    }

    /// The pinned applications, in bar order — what the Apps Menu calls "Favourites".
    func pinnedAppURLs() -> [URL] {
        pinned.compactMap { entry in
            guard entry.kind == .app else { return nil }
            return entry.resolveURL()
        }
    }

    // MARK: - Actions

    /// Activates the cell a positional hot key names, counting from zero.
    ///
    /// Out of range does nothing: a bar with four apps on it has no seventh cell, and ⌃⌥7 is then
    /// a key press about nothing rather than an error.
    func activateSlot(_ index: Int) {
        let addressable = BarComposition.addressable(items)
        guard addressable.indices.contains(index) else { return }
        activate(addressable[index])
    }

    func activate(_ item: DockItem) {
        switch item.kind {
        case .app(let ref):
            activateApp(ref, instance: item.instance)
        case .folder(let url), .file(let url):
            NSWorkspace.shared.open(url)
        case .window(let ref, let window):
            // An unreachable window has no element to raise — activating its app is all macOS
            // offers, and is what the Dock's own icon does. Otherwise the window is re-found by
            // title at click time, and a title that has moved on since the button was drawn finds
            // nothing: falling back to the app is the difference between a stale button and a dead
            // one.
            if !window.isReachable || raiseWindow?(window) != true {
                activateApp(ref, instance: item.instance)
            }
        case .trash:
            NSWorkspace.shared.open(Trash.url)
        case .clock:
            openCalendar()
        case .separator, .appsMenu:
            break
        }
    }

    /// Whatever handles calendar links, which is the user's calendar application whether or not
    /// that is Apple's. Falling back to the bundled one only if nothing claims the scheme.
    private func openCalendar() {
        if let handler = URL(string: "webcal://"),
           let app = NSWorkspace.shared.urlForApplication(toOpen: handler) {
            open(app)
            return
        }
        open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    private func activateApp(_ ref: AppRef, instance: pid_t? = nil) {
        let app = runningApp(ref, instance: instance)
        if app?.isHidden == true { app?.unhide() }

        let decision = ActivationPolicy.decide(
            isRunning: app != nil,
            isActive: app?.isActive ?? false,
            visibleWindows: visibleWindowCount(for: app))

        switch decision {
        case .launch, .reopen:
            bringForward(ref, copy: instance == nil ? nil : app)
        case .cycleOrHide:
            guard let app else { return }
            // Several windows open: step to the next one rather than hiding an app the user is
            // clearly still working in. One window: hide, as before.
            if cycleWindows?(app.processIdentifier) != true { app.hide() }
        }
    }

    /// Windows that are actually on screen, or nil when we cannot tell.
    private func visibleWindowCount(for app: NSRunningApplication?) -> Int? {
        guard let app, hasWindowInformation?() == true else { return nil }
        return (windowsByPID[app.processIdentifier] ?? []).count { !$0.isMinimized }
    }

    /// `open(_:)` for an app's first copy, and the process itself for any other.
    ///
    /// LaunchServices names an app by its bundle and picks which copy to bring forward on its own,
    /// so a second copy can only be reached through its process — at the cost of the reopen event,
    /// which is the one thing `open` carries that `activate` does not.
    private func bringForward(_ ref: AppRef, copy: NSRunningApplication?) {
        if let copy { copy.activate() } else { open(ref.url) }
    }

    /// Launch, or bring forward and reopen.
    ///
    /// Deliberately LaunchServices rather than `NSRunningApplication.activate()`, even for an app
    /// that is already running: this is the call the Dock makes, it carries the reopen event that
    /// gives a windowless app a window back, and it is not subject to the cooperative-activation
    /// rules that can quietly drop an activation requested by a background agent like this one.
    private func open(_ url: URL) {
        // Last line of defence rather than the fix: a URL macOS will not launch is opened as a
        // document instead, which for a bundle means Finder — reported as success, with no error to
        // log. See `ApplicationURL`.
        let url = ApplicationURL.normalised(url)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard let error else { return }
            NSLog("Eskele: could not open \(url.lastPathComponent) — \(error.localizedDescription)")
        }
    }

    func open(_ urls: [URL], with item: DockItem) {
        switch item.kind {
        case .app(let ref), .window(let ref, _):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: ref.url, configuration: configuration)
        case .trash:
            let failures = Trash.moveToTrash(urls)
            if !failures.isEmpty {
                NSSound.beep()
                NSLog("Eskele: could not trash \(failures.count) item(s)")
            }
        default:
            break
        }
    }

    /// The owning application, whether the item is an app or one of its windows.
    private func runningApp(for item: DockItem) -> NSRunningApplication? {
        switch item.kind {
        case .app(let ref), .window(let ref, _): runningApp(ref, instance: item.instance)
        default: nil
        }
    }

    /// The copy of an app a cell stands for.
    ///
    /// By process for any copy after the first. The bundle ID names whichever copy the workspace
    /// lists first, so looking a second copy up by it is how its cell came to show the first one's
    /// windows and state — and how Quit on it would have closed the other one.
    private func runningApp(_ ref: AppRef, instance: pid_t?) -> NSRunningApplication? {
        if let instance { return running.app(withPID: instance) }
        return running.app(withBundleID: ref.bundleID)
    }

    func quit(_ item: DockItem) {
        runningApp(for: item)?.terminate()
    }

    func hide(_ item: DockItem) {
        guard let app = runningApp(for: item) else { return }
        if app.isHidden { app.unhide() } else { app.hide() }
    }

    /// Brings one app forward and hides every other one.
    ///
    /// An app that is not running yet is launched and nothing is hidden: "show only this" reads as a
    /// request to end up looking at one thing, and clearing the screen around an app that then fails
    /// to start would leave the user with neither.
    func showOnly(_ item: DockItem) {
        guard let target = runningApp(for: item) else {
            activate(item)
            return
        }
        if target.isHidden { target.unhide() }

        // Deliberately not `activate`: a plain click on the app you are already in hides it, and
        // "show only this" asking for the one thing on screen to go away is the opposite of what
        // the gesture says. This brings it forward and stops there.
        let copy = item.instance == nil ? nil : target
        switch item.kind {
        case .app(let ref):
            bringForward(ref, copy: copy)
        case .window(let ref, let window):
            if !window.isReachable || raiseWindow?(window) != true { bringForward(ref, copy: copy) }
        default:
            return
        }

        for app in running.apps where app.processIdentifier != target.processIdentifier {
            app.hide()
        }
    }

    /// Kills the app and starts it again.
    ///
    /// `forceTerminate`, unlike `quit`: this is the gesture you reach for when an app has stopped
    /// answering, and a polite request is exactly what such an app cannot honour. Unsaved work goes
    /// with it, which is why it is behind two modifiers rather than one.
    func forceRelaunch(_ item: DockItem) {
        guard let app = runningApp(for: item),
              let url = ApplicationURL.launchable(for: app) else { return }
        let pid = app.processIdentifier
        app.forceTerminate()
        relaunch(pid: pid, url: url)
    }

    /// Reopens once the old process is actually gone. Opening while it is still dying just hands
    /// back the instance that is on its way out.
    private func relaunch(pid: pid_t, url: URL, attempt: Int = 0) {
        if NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true {
            open(url)
            return
        }
        // A process that has been force-killed and is still here after this long is not going to
        // leave because we waited longer; relaunching over it would only produce a second copy.
        guard attempt < DockModel.relaunchAttempts else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.relaunch(pid: pid, url: url, attempt: attempt + 1)
        }
    }

    /// Four seconds, in 100ms steps.
    private static let relaunchAttempts = 40

    /// Closes one window, leaving the rest of its app open.
    func close(_ item: DockItem) {
        guard let window = item.windowReference else { return }
        _ = closeWindow?(window)
    }

    func revealInFinder(_ item: DockItem) {
        guard let url = item.url else {
            NSWorkspace.shared.open(Trash.url)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
