import AppKit

/// Tracks regular (Dock-eligible) running applications, and optionally the menu-bar agents that
/// happen to have a window open.
@MainActor
final class RunningAppsService {
    private(set) var apps: [NSRunningApplication] = []
    var onChange: (() -> Void)?

    /// Accessory apps that have a window right now — see `AccessoryAppsService`. Read through a
    /// closure rather than stored so the two services do not have to be built in a fixed order.
    var accessoryPIDs: (() -> Set<pid_t>)?

    /// Whether those agents get a tile at all. Off by default: it is a visible change to what the
    /// bar shows, so it is `Settings.showAccessoryApps` that turns it on.
    var includesAccessory = false {
        didSet {
            guard includesAccessory != oldValue else { return }
            refresh()
        }
    }

    /// When each app was first seen still launching, so a tile cannot sit striped forever.
    ///
    /// `isFinishedLaunching` is only as good as the app: something that never uses the standard
    /// Cocoa start-up can leave it false for its whole life, and a permanent "opening…" would be a
    /// worse lie than no indicator at all.
    private var launchingSince: [pid_t: Date] = [:]
    private var launchingTimer: Timer?

    /// Longer than any healthy cold start on this hardware, short enough that a misreporting app is
    /// only wrong for a moment.
    private static let launchGracePeriod: TimeInterval = 20
    /// Nothing else changes while an app starts, so the striping needs its own nudge to stop.
    private static let launchPollInterval: TimeInterval = 0.5

    /// Apps that have started but not finished starting.
    var launchingPIDs: Set<pid_t> {
        let now = Date()
        return Set(
            apps.filter { app in
                guard !app.isFinishedLaunching else { return false }
                guard let since = launchingSince[app.processIdentifier] else { return false }
                return now.timeIntervalSince(since) < RunningAppsService.launchGracePeriod
            }.map(\.processIdentifier))
    }

    // Tokens are only ever touched from the main actor except in deinit, which runs after the
    // last reference is gone.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            // `didLaunch` fires when an app has *finished* starting. Without `willLaunch` the tile
            // would not exist until there was nothing left to indicate.
            NSWorkspace.willLaunchApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
    }

    func stop() {
        launchingTimer?.invalidate()
        launchingTimer = nil
    }

    func refresh() {
        // Resolved once rather than per app: the closure walks the whole running-app list.
        let windowed = includesAccessory ? (accessoryPIDs?() ?? []) : []
        apps = NSWorkspace.shared.runningApplications.filter {
            RunningAppsService.isListed(
                policy: $0.activationPolicy,
                pid: $0.processIdentifier,
                bundleID: $0.bundleIdentifier,
                ownBundleID: ownBundleID,
                windowed: windowed)
        }
        noteLaunchProgress()
        // Always notify: activation and hide changes are invisible in the list itself but do change
        // how cells draw, and rebuilding the (tiny) item array is cheaper than diffing it.
        onChange?()
    }

    /// Starts and stops the launch poll, and forgets apps that have gone.
    private func noteLaunchProgress() {
        let live = Set(apps.map(\.processIdentifier))
        launchingSince = launchingSince.filter { live.contains($0.key) }
        for app in apps where !app.isFinishedLaunching {
            launchingSince[app.processIdentifier] = launchingSince[app.processIdentifier] ?? Date()
        }

        // An app finishing its launch usually posts nothing we hear, and the grace period expires on
        // its own schedule; both need a nudge to reach the bar. It runs only while something is
        // actually starting.
        let wanted = !launchingPIDs.isEmpty
        if wanted, launchingTimer == nil {
            let timer = Timer.scheduledTimer(
                withTimeInterval: RunningAppsService.launchPollInterval, repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = RunningAppsService.launchPollInterval / 2
            launchingTimer = timer
        } else if !wanted, launchingTimer != nil {
            stop()
        }
    }

    /// Whether an app belongs on the bar.
    ///
    /// `.regular` is exactly the set the system Dock shows, and is unconditional. An accessory app
    /// earns its place only while it has a window, which is what makes its tile transient.
    ///
    /// Eskele is itself an accessory app, so the `ownBundleID` exclusion only ever bites on the
    /// regular branch — which is the behaviour that matters: the bar must never show a tile for the
    /// bar. Falling through to the accessory branch is deliberate, and is the whole reason the
    /// feature exists: our *settings* window is layer 0 and our bar is not, so we appear exactly
    /// when the user has settings open and vanish again when they close it.
    ///
    /// `.prohibited` apps are excluded by both branches. They cannot be activated, so their tile
    /// would be a button that does nothing.
    nonisolated static func isListed(
        policy: NSApplication.ActivationPolicy,
        pid: pid_t,
        bundleID: String?,
        ownBundleID: String?,
        windowed: Set<pid_t>
    ) -> Bool {
        switch policy {
        case .regular: bundleID != ownBundleID
        case .accessory: windowed.contains(pid)
        default: false
        }
    }

    /// The first copy of an app, in the order the workspace lists them.
    func app(withBundleID id: String) -> NSRunningApplication? {
        apps.first { $0.bundleIdentifier == id }
    }

    /// One particular copy, for an app running as more than one process.
    func app(withPID pid: pid_t) -> NSRunningApplication? {
        apps.first { $0.processIdentifier == pid }
    }
}
