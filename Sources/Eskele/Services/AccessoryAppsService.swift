import AppKit

/// Accessory apps — menu-bar agents, and Eskele itself — that have an ordinary window open.
///
/// **The problem this solves.** An app with `LSUIElement` set has no Dock tile, so a window it puts
/// up has no representation anywhere: not in the Dock, not in its window list, nowhere. Eskele's own
/// settings window is the reference case. The window is plainly on screen and there is no way back
/// to it but to find it with the mouse.
///
/// These apps cannot simply be added to `RunningAppsService` wholesale. A typical machine runs
/// dozens of agents — login items, helpers, the Dock itself — and almost none of them ever show a
/// window. A permanent tile for each would be worse than no feature at all, so the rule is *"an
/// accessory app that has a window right now"*, which makes the tile transient: it arrives with the
/// window and leaves with it.
///
/// **Why the window server rather than Accessibility.** Answering "does this app have a window?"
/// with AX would mean an AX round trip into every agent on the machine on every sweep — the exact
/// cost `WindowInfoService` exists to avoid. `CGWindowList` answers it for every process at once,
/// needs no permission, and is already the pre-filter pattern used for off-Space windows. AX is then
/// asked only about the handful of agents that turned out to have something.
///
/// **Measured on macOS 26.6.** An accessory app's ordinary windows are reported at layer 0, exactly
/// like a regular app's — the activation policy changes the Dock's behaviour, not the window
/// server's. The things an agent puts *above* layer 0 are precisely the things that must not earn a
/// tile: status items sit at 25, the system Dock at 20, Eskele's own bar at 21 (`dockWindow` + 1),
/// its tooltip and edge trigger at 22, its launcher at `popUpMenu`. So layer 0 separates "a window
/// the user is looking at" from "chrome the agent hangs off the menu bar" with nothing left over —
/// and for Eskele itself it admits the settings and onboarding windows and nothing else.
///
/// **Minimised windows.** The window server cannot answer for these: a minimised window is off
/// screen, and off screen is where the template ghosts live too. So minimising is answered from the
/// other side — see `keeping(_:previous:accessory:hasMinimisedWindow:)`.
@MainActor
final class AccessoryAppsService {
    /// Accessory apps that have a window right now, on screen or minimised.
    private(set) var pids: Set<pid_t> = []
    var onChange: (() -> Void)?
    /// Whether an app has a minimised window, asked at the moment it matters. Unset, a minimised
    /// window takes its tile away with it.
    var hasMinimisedWindow: ((pid_t) -> Bool)?

    /// Nothing is scanned, and nothing is reported, while the feature is off — see
    /// `Settings.showAccessoryApps`. This is the switch that makes the whole feature cost zero for
    /// the users who do not want it.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    private var poll: Poll?
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    /// An agent opening a window posts nothing anyone else can hear: there is no workspace
    /// notification for "a window appeared", and the app is not in the AX sweep set yet — that is
    /// what this scan decides. So a poll is the primary signal here rather than a safety net, and it
    /// is faster than `SpaceWindowService`'s accordingly.
    ///
    /// The common case does not wait for it. Showing an agent's settings window nearly always
    /// activates the agent, and `didActivateApplication` is heard, so the tile is usually there by
    /// the time the window has finished opening.
    private static let interval: TimeInterval = 2

    /// The floor a window has to clear to count as something the user can see and want back.
    ///
    /// Agents keep small layer-0 windows around for event capture and drag feedback. A real settings
    /// window is an order of magnitude bigger than those, so the floor can sit well below the
    /// smallest plausible one and still reject them.
    nonisolated static let minimumSize = CGSize(width: 120, height: 60)

    init() {}

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
    }

    private func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }

        poll = Poll(
            every: AccessoryAppsService.interval, tolerance: AccessoryAppsService.interval / 2
        ) { [weak self] in self?.refresh() }

        refresh()
    }

    /// Deliberately silent. Switching the feature off already takes the cells away through
    /// `RunningAppsService.includesAccessory`, which is set from the same expression, so announcing
    /// the cleared set would only ask for the same rebuild twice — and at quit, when this also runs,
    /// it would buy an Accessibility sweep on the way out.
    func stop() {
        poll?.invalidate()
        poll = nil
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
        observers = []
        pids = []
    }

    func refresh() {
        guard isEnabled else { return }
        let accessory = AccessoryAppsService.accessoryPIDs()
        let next = AccessoryAppsService.keeping(
            AccessoryAppsService.scan(accessory: accessory),
            previous: pids,
            accessory: accessory,
            hasMinimisedWindow: hasMinimisedWindow ?? { _ in false })
        guard next != pids else { return }
        pids = next
        onChange?()
    }

    /// The apps with a tile after this scan: every one with a window on screen, and every one that
    /// already had a tile and has since minimised its window rather than closed it.
    ///
    /// Without the second half, minimising a window took its tile away — and with it the route
    /// back, which is the one thing the tile is for. Only apps that already had a tile are asked,
    /// because the answer costs an Accessibility round trip into each, and the apps with a tile are
    /// the handful that have shown a window rather than every agent on the machine. The price is an
    /// app whose window was minimised before any scan saw it — at launch, or when the feature is
    /// switched on — which gets no tile until the window comes back, exactly as before.
    nonisolated static func keeping(
        _ onScreen: Set<pid_t>,
        previous: Set<pid_t>,
        accessory: Set<pid_t>,
        hasMinimisedWindow: (pid_t) -> Bool
    ) -> Set<pid_t> {
        // An app that has quit, or stopped being an accessory app, is not asked about.
        let offScreen = previous.subtracting(onScreen).intersection(accessory)
        return onScreen.union(offScreen.filter(hasMinimisedWindow))
    }

    /// Every accessory app on the machine, whether or not it has a window.
    ///
    /// `.prohibited` is deliberately not included: those processes cannot be activated, so a tile
    /// for one would be a button that does nothing.
    private static func accessoryPIDs() -> Set<pid_t> {
        Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .accessory }
                .map(\.processIdentifier))
    }

    /// - Parameter accessory: the apps worth looking at. Regular apps are already on the bar under
    ///   their own rules, so including them here would produce a second, competing source of truth.
    nonisolated static func scan(accessory: Set<pid_t>) -> Set<pid_t> {
        // On-screen only: it is both cheaper and the filter that rejects the cached template windows
        // `CGWindowList` reports for apps that have nothing open — the 500×500 and 800×600 ghosts
        // documented in `SpaceWindowService`. A minimised window is off screen as well, and cannot
        // be told apart from them here; `keeping` is what brings those back.
        let list = (CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var found: Set<pid_t> = []

        for entry in list {
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  accessory.contains(pid),
                  // Cheap first: most entries belong to apps we have already accepted or rejected.
                  !found.contains(pid)
            else { continue }
            let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat]
            guard qualifies(
                layer: entry[kCGWindowLayer as String] as? Int ?? -1,
                alpha: entry[kCGWindowAlpha as String] as? Double ?? 1,
                width: bounds?["Width"] ?? 0,
                height: bounds?["Height"] ?? 0)
            else { continue }
            found.insert(pid)
        }
        return found
    }

    /// Whether one window server entry is an ordinary window a user would want a tile for.
    nonisolated static func qualifies(
        layer: Int, alpha: Double, width: CGFloat, height: CGFloat
    ) -> Bool {
        layer == 0
            // A fully transparent window is on screen in the window server's sense and invisible in
            // every sense the user has.
            && alpha > 0
            && width >= minimumSize.width
            && height >= minimumSize.height
    }
}
