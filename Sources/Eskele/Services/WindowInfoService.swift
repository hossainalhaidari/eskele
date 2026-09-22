import AppKit

/// Caches each running app's windows — how many there are, and their titles.
///
/// Counts come from Accessibility because the permission-free alternative does not work: counting
/// `CGWindowList` entries includes helper and panel windows, and measured against AX it over-reported
/// consistently — Mail 2 windows against 0, Steam 2 against 0. Without Accessibility this reports
/// nothing and the bar falls back to a single dash, which is the pre-existing behaviour.
@MainActor
final class WindowInfoService {
    private(set) var windowsByPID: [pid_t: [WindowRef]] = [:]
    /// Apps currently showing a modal dialog. Recomputed by every sweep, so it clears itself as
    /// soon as the dialog goes away.
    private(set) var dialogPIDs: Set<pid_t> = []
    /// Apps that have missed their last few Accessibility reads — see `unresponsiveStreak`.
    private(set) var unresponsivePIDs: Set<pid_t> = []
    var onChange: (() -> Void)?
    /// A sheet appeared. Sheets are children of a window rather than entries in the window list, so
    /// the notification is all we ever see of one — hence a callback rather than a derived set.
    var onSheet: ((pid_t) -> Void)?
    /// Apps the window server says have a window on another Space. Only those pay for the extra AX
    /// round trips that can recover it.
    var offSpacePIDs: (() -> Set<pid_t>)?
    /// Accessory apps the window server says have a window — see `AccessoryAppsService`. Empty
    /// unless `Settings.showAccessoryApps` is on, which is what keeps the sweep the size it has
    /// always been for everyone else: a machine runs dozens of agents and this admits only the ones
    /// with something on screen.
    var accessoryPIDs: (() -> Set<pid_t>)?
    /// Whether each window has to be asked which display it is on — an extra Accessibility read per
    /// window, so only `ScreenMode.perDisplay` turns it on.
    var tracksDisplays = false {
        didSet {
            guard tracksDisplays != oldValue else { return }
            refresh()
        }
    }

    /// And only when there is more than one display, since on a single display the answer is the
    /// same for every window and the filter it feeds has nothing to do.
    private var wantsDisplays: Bool { tracksDisplays && NSScreen.screens.count > 1 }

    /// Displays showing a native full-screen window, from the sweep we already do. Unlike
    /// `FullScreenMonitor`'s frontmost-only check this notices an app sitting full-screen on a
    /// second display while the user works on the first.
    var fullScreenDisplays: Set<CGDirectDisplayID> {
        fullScreenByPID.values.reduce(into: Set<CGDirectDisplayID>()) { $0.formUnion($1) }
    }

    private var fullScreenByPID: [pid_t: Set<CGDirectDisplayID>] = [:]

    private let service: WindowService
    private let observer = WindowObserver()
    private var pending: DispatchWorkItem?
    private var pendingPIDs: Set<pid_t> = []
    private var pendingFullSweep = false
    /// Apps that answered slowly, and how many safety sweeps to skip them for.
    private var sweepsToSkip: [pid_t: Int] = [:]
    /// Consecutive reads each app has failed to answer.
    private var timeoutStreak: [pid_t: Int] = [:]
    /// Suspects that have also failed the long probe: the apps actually reported as unresponsive.
    private var confirmedStalls: Set<pid_t> = []
    /// Suspects with a probe still out, so a slow app is never asked twice at once.
    private var probing: Set<pid_t> = []
    private var poll: Poll?
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?

    /// Window changes arrive as AX notifications (see `WindowObserver`), so this poll is only a
    /// safety net for apps whose Accessibility support does not deliver them. It used to be the
    /// primary mechanism at 2s, which is where the visible lag came from.
    private static let pollInterval: TimeInterval = 5.0
    /// Short enough to feel immediate, long enough to coalesce the burst of notifications that
    /// arrives when a window opens.
    private static let debounce: TimeInterval = 0.03
    /// An app slower than this is one badly behaved application away from making the safety sweep
    /// cost real CPU. Measured on this machine: every native app answered in 0–4ms, while one
    /// non-native app took 280–330ms on its own.
    private static let slowApp: TimeInterval = 0.1
    /// How many safety sweeps a slow app is skipped for. Its own AX notifications still update it
    /// immediately, so this only affects how often we re-read it speculatively.
    private static let slowAppSkips = 5
    /// How many reads in a row an app must miss before it is suspected of not responding. One is
    /// not evidence — a machine under load can starve a healthy app of a 120ms window — and a tile
    /// that flickers "not responding" at every hiccup is one nobody would believe.
    private static let unresponsiveStreak = 2
    /// How long a suspect is given to answer one question before it is called unresponsive.
    ///
    /// The sweep's 120ms is a budget for the bar, not a verdict on the app. An app that paces its
    /// own main loop — a game engine's editor sleeping between frames while it is in the
    /// background — can miss it on every sweep while being perfectly healthy, and two misses were
    /// all it took to be striped red for as long as it ran. Two seconds is a stall of the kind that
    /// earns an app the spinning cursor, and the question is asked off the main thread, so the bar
    /// never waits for the answer.
    private static let probeTimeout: Float = 2

    init(windows: WindowService) {
        self.service = windows
        // The observer knows *which* app changed, so only that app needs re-reading. This is what
        // keeps one slow application from delaying every other app's updates.
        observer.onChange = { [weak self] pid, notification in
            guard let self else { return }
            if notification == kAXSheetCreatedNotification { self.onSheet?(pid) }
            self.scheduleRefresh(pid: pid)
        }

        let center = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        // Rearranging the displays moves windows between them, and can change whether there is more
        // than one display to tell apart at all.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }

        poll = Poll(every: WindowInfoService.pollInterval, tolerance: 0.5) { [weak self] in
            self?.refresh()
        }

        refresh()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func stopObserving() {
        observer.stopAll()
    }

    func windows(for pid: pid_t?) -> [WindowRef] {
        guard let pid else { return [] }
        return windowsByPID[pid] ?? []
    }

    func count(for pid: pid_t?) -> Int { windows(for: pid).count }

    /// - Parameter pid: the one app to re-read. `nil` means the set of running apps may itself
    ///   have changed, so everything is swept.
    private func scheduleRefresh(pid: pid_t? = nil) {
        if let pid { pendingPIDs.insert(pid) } else { pendingFullSweep = true }

        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushPending() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + WindowInfoService.debounce, execute: work)
    }

    private func flushPending() {
        let pids = pendingPIDs
        let full = pendingFullSweep
        pendingPIDs = []
        pendingFullSweep = false
        if full { refresh() } else { refresh(pids: pids) }
    }

    /// Re-reads just these apps, leaving every other app's cached windows alone.
    func refresh(pids: Set<pid_t>) {
        guard service.isTrusted, !pids.isEmpty else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier

        var next = windowsByPID
        var dialogs = dialogPIDs
        var fullScreen = fullScreenByPID
        let elsewhere = offSpacePIDs?() ?? []
        let accessory = accessoryPIDs?() ?? []
        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  WindowInfoService.isTracked(
                    policy: app.activationPolicy, pid: pid, accessory: accessory)
            else {
                next.removeValue(forKey: pid)
                dialogs.remove(pid)
                fullScreen.removeValue(forKey: pid)
                continue
            }
            if pid == WindowService.ownPID {
                next[pid] = service.ownWindowRefs()
                dialogs.remove(pid)
                fullScreen.removeValue(forKey: pid)
                continue
            }

            let windows = service.windows(
                for: pid,
                includingOffSpace: elsewhere.contains(pid),
                includingDisplays: wantsDisplays)
            next[pid] = service.windowRefs(for: pid, from: windows, includeFocus: pid == frontmost)
            record(
                windows, for: pid, tracksDialogs: app.activationPolicy == .regular,
                dialogs: &dialogs, fullScreen: &fullScreen)
            observer.observe(windows: windows, for: pid)
        }

        publish(next, dialogs: dialogs, fullScreen: fullScreen)
    }

    /// Whether this app's windows are swept at all.
    ///
    /// An AX read is a synchronous message into another process, so the set of apps swept is the set
    /// of processes this service can be delayed by. Regular apps are unconditional; an accessory app
    /// joins only while the window server says it has something on screen.
    nonisolated static func isTracked(
        policy: NSApplication.ActivationPolicy, pid: pid_t, accessory: Set<pid_t>
    ) -> Bool {
        switch policy {
        case .regular: true
        case .accessory: accessory.contains(pid)
        default: false
        }
    }

    func refresh() {
        guard service.isTrusted else {
            guard !windowsByPID.isEmpty || !dialogPIDs.isEmpty || !fullScreenByPID.isEmpty
                || !unresponsivePIDs.isEmpty
            else { return }
            windowsByPID = [:]
            dialogPIDs = []
            fullScreenByPID = [:]
            // Without the permission every read fails, which says nothing about the apps.
            unresponsivePIDs = []
            timeoutStreak = [:]
            confirmedStalls = []
            onChange?()
            return
        }

        let accessory = accessoryPIDs?() ?? []
        let running = NSWorkspace.shared.runningApplications.filter {
            WindowInfoService.isTracked(
                policy: $0.activationPolicy, pid: $0.processIdentifier, accessory: accessory)
        }
        // Observers first: `observe(windows:for:)` needs the app's observer to already exist, so a
        // newly launched app would otherwise go one whole refresh without per-window notifications.
        // Never ourselves: measured, `AXObserverAddNotification` on our own pid is refused with
        // `kAXErrorNotImplemented`, and we do not need it — AppKit tells us about our own windows.
        observer.sync(pids: Set(running.map(\.processIdentifier)).subtracting([WindowService.ownPID]))

        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let elsewhere = offSpacePIDs?() ?? []
        var next: [pid_t: [WindowRef]] = [:]
        var dialogs: Set<pid_t> = []
        var fullScreen: [pid_t: Set<CGDirectDisplayID>] = [:]
        for app in running {
            let pid = app.processIdentifier

            // Accessibility will not describe our own process — see `WindowService.ownWindowRefs()`.
            // Nothing below this line would work for us, and none of it needs to.
            if pid == WindowService.ownPID {
                next[pid] = service.ownWindowRefs()
                continue
            }

            if let remaining = sweepsToSkip[pid], remaining > 0 {
                sweepsToSkip[pid] = remaining - 1
                next[pid] = windowsByPID[pid] ?? []
                if dialogPIDs.contains(pid) { dialogs.insert(pid) }
                fullScreen[pid] = fullScreenByPID[pid]
                continue
            }

            let started = Date()
            // Fetch once and reuse: the refs are derived from the same list the observer needs to
            // register against, and an AX sweep is the expensive part of this.
            let windows = service.windows(
                for: pid,
                includingOffSpace: elsewhere.contains(pid),
                includingDisplays: wantsDisplays)
            next[pid] = service.windowRefs(for: pid, from: windows, includeFocus: pid == frontmost)
            record(
                windows, for: pid, tracksDialogs: app.activationPolicy == .regular,
                dialogs: &dialogs, fullScreen: &fullScreen)
            observer.observe(windows: windows, for: pid)

            // A timeout is slow by definition, but throttling it would mean five skipped sweeps —
            // half a minute — before the second failed read that confirms it. The cost of not
            // throttling is bounded by the messaging timeout itself, which is the point of having one.
            if Date().timeIntervalSince(started) > WindowInfoService.slowApp,
               !service.didFailToAnswer(pid: pid) {
                sweepsToSkip[pid] = WindowInfoService.slowAppSkips
            }
        }

        publish(next, dialogs: dialogs, fullScreen: fullScreen)
    }

    /// - Parameter tracksDialogs: whether this app may raise the attention highlight.
    ///
    ///   False for accessory apps, and the reason is a measurement: an `NSPanel` at `.floating`
    ///   level reports its AX subrole as `AXDialog`, which is indistinguishable here from a real
    ///   modal. Floating panels are what menu-bar agents are made of, so admitting them to the sweep
    ///   without this guard would light up half the bar the moment the feature was switched on —
    ///   and `AttentionService` reads "a dialog, while the app is not frontmost" as a summons.
    ///
    ///   Regular apps keep the behaviour they have always had. They have floating panels too, so the
    ///   same false positive exists there in principle, but it is pre-existing, rarer, and not this
    ///   feature's to change.
    private func record(
        _ windows: [AppWindow],
        for pid: pid_t,
        tracksDialogs: Bool,
        dialogs: inout Set<pid_t>,
        fullScreen: inout [pid_t: Set<CGDirectDisplayID>]
    ) {
        if tracksDialogs, windows.contains(where: \.isDialog) {
            dialogs.insert(pid)
        } else {
            dialogs.remove(pid)
        }
        let displays = service.fullScreenDisplays(among: windows)
        if displays.isEmpty { fullScreen.removeValue(forKey: pid) } else { fullScreen[pid] = displays }

        if service.didFailToAnswer(pid: pid) {
            timeoutStreak[pid, default: 0] += 1
        } else {
            timeoutStreak.removeValue(forKey: pid)
        }
    }

    private func suspects(among pids: some Collection<pid_t>) -> Set<pid_t> {
        Set(pids.filter { timeoutStreak[$0, default: 0] >= WindowInfoService.unresponsiveStreak })
    }

    private func publish(
        _ windows: [pid_t: [WindowRef]],
        dialogs: Set<pid_t>,
        fullScreen: [pid_t: Set<CGDirectDisplayID>]
    ) {
        // Apps that have gone take their streak with them.
        timeoutStreak = timeoutStreak.filter { windows.keys.contains($0.key) }
        let suspected = suspects(among: windows.keys)
        // An app that answers any read stops being a suspect, and with that stops being reported.
        confirmedStalls.formIntersection(suspected)
        for pid in suspected where !confirmedStalls.contains(pid) && !probing.contains(pid) {
            probe(pid)
        }
        let stalled = confirmedStalls
        guard windows != windowsByPID || dialogs != dialogPIDs || fullScreen != fullScreenByPID
            || stalled != unresponsivePIDs
        else { return }
        windowsByPID = windows
        dialogPIDs = dialogs
        fullScreenByPID = fullScreen
        unresponsivePIDs = stalled
        onChange?()
    }

    /// Asks a suspect one question, with long enough to answer that only a stuck app will not.
    private func probe(_ pid: pid_t) {
        probing.insert(pid)
        let timeout = WindowInfoService.probeTimeout
        DispatchQueue.global(qos: .utility).async {
            let answered = WindowInfoService.answers(pid: pid, within: timeout)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.settleProbe(pid, answered: answered) }
            }
        }
    }

    private func settleProbe(_ pid: pid_t, answered: Bool) {
        probing.remove(pid)
        // The sweep may have moved on while the question was out: an app that has answered since,
        // or quit, is no longer a suspect and must not be striped on the strength of an old miss.
        guard !answered,
              suspects(among: windowsByPID.keys).contains(pid),
              confirmedStalls.insert(pid).inserted
        else { return }
        unresponsivePIDs = confirmedStalls
        onChange?()
    }

    /// One trivial question with a generous timeout. Off the main thread, so a stuck app costs the
    /// bar nothing however long it takes not to answer.
    nonisolated private static func answers(pid: pid_t, within timeout: Float) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &value)
        return status != .cannotComplete
    }
}
