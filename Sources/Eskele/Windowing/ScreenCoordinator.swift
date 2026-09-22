import AppKit

/// Creates and tears down one bar per target screen, and keeps them correct across display changes.
@MainActor
final class ScreenCoordinator {
    private var controllers: [CGDirectDisplayID: BarWindowController] = [:]
    private weak var delegate: BarContentViewDelegate?
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    var settings: Settings
    var items: [DockItem] = []
    var fullScreenDisplays: Set<CGDirectDisplayID> = []
    /// What the bars are currently annotating their cells with, if anything.
    private(set) var overlay: BarOverlay?
    private(set) var activity: [pid_t: ActivitySample] = [:]
    private(set) var progress: [String: ProgressReport] = [:]

    init(settings: Settings, delegate: BarContentViewDelegate) {
        self.settings = settings
        self.delegate = delegate
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Screens are keyed by display ID rather than array position so a bar survives a monitor being
    /// unplugged and plugged back in.
    private var targetScreens: [NSScreen] {
        switch settings.screenMode {
        case .allScreens, .perDisplay: NSScreen.screens
        case .menuBarScreen: [ScreenMetrics.menuBarScreen].compactMap { $0 }
        }
    }

    /// What one display's bar shows. Every mode but `.perDisplay` mirrors the same strip everywhere,
    /// which is also what `.perDisplay` degrades to when no window can be placed — see
    /// `BarComposition.onDisplay`.
    private func items(for display: CGDirectDisplayID) -> [DockItem] {
        guard settings.screenMode == .perDisplay else { return items }
        return BarComposition.onDisplay(items, display)
    }

    func sync() {
        guard let delegate else { return }
        var seen: Set<CGDirectDisplayID> = []

        for screen in targetScreens {
            guard let id = ScreenMetrics.displayID(of: screen) else { continue }
            seen.insert(id)
            let controller = controllers[id] ?? {
                let new = BarWindowController(screen: screen, settings: settings, delegate: delegate)
                controllers[id] = new
                return new
            }()
            controller.update(
                items: items(for: id),
                settings: settings,
                screen: screen,
                isFullScreen: fullScreenDisplays.contains(id)
            )
            // Also here, not only in `setOverlay`: a display plugged in while the modifiers are
            // held gets its bar built from scratch and would otherwise show nothing.
            controller.content.activity = activity
            controller.content.overlay = overlay
            controller.content.progress = progress
        }

        for (id, controller) in controllers where !seen.contains(id) {
            controller.close()
            controllers.removeValue(forKey: id)
        }
    }

    /// Deliberately not part of `sync`, which relays out every bar: these change nothing but what
    /// the cells draw, and they happen every time the user reaches for the modifiers.
    func setOverlay(_ overlay: BarOverlay?) {
        guard overlay != self.overlay else { return }
        self.overlay = overlay
        for controller in controllers.values { controller.content.overlay = overlay }
    }

    func setActivity(_ activity: [pid_t: ActivitySample]) {
        guard activity != self.activity else { return }
        self.activity = activity
        for controller in controllers.values { controller.content.activity = activity }
    }

    /// Rebuilds every cell's icon in place. The items have not changed — only what they are drawn
    /// with — so this is a redraw rather than a `sync`.
    func rebuildIcons() {
        for controller in controllers.values { controller.content.reloadIcons() }
    }

    func setProgress(_ progress: [String: ProgressReport]) {
        guard progress != self.progress else { return }
        self.progress = progress
        for controller in controllers.values { controller.content.progress = progress }
    }

    /// Reveals every hidden bar, or hides them all if they are already out.
    func toggleReveal() {
        for controller in controllers.values { controller.toggleReveal() }
    }

    /// Where the Apps Menu should open from when a key asked for it rather than a click.
    ///
    /// A hidden bar is revealed first, so the panel does not appear to hang off nothing.
    func appsMenuAnchor() -> (anchor: NSRect, screen: NSScreen, bar: BarContentView)? {
        guard let controller = barsByPreference().first else { return nil }
        controller.reveal()
        return (controller.appsMenuAnchor, controller.screen, controller.content)
    }

    /// Every bar, the one a key should act on first: the bar under the pointer, because with several
    /// displays that is the one the user is looking at; then the bar on the screen with the menu
    /// bar, which is where to go when there is nothing else to go on; then the rest.
    private func barsByPreference() -> [BarWindowController] {
        let pointer = NSEvent.mouseLocation
        let underPointer = controllers.values.first { NSMouseInRect(pointer, $0.screen.frame, false) }
        let menuBar = ScreenMetrics.menuBarScreen.flatMap { screen in
            ScreenMetrics.displayID(of: screen).flatMap { controllers[$0] }
        }
        var ordered: [BarWindowController] = []
        for controller in [underPointer, menuBar].compactMap({ $0 }) + Array(controllers.values)
        where !ordered.contains(where: { $0 === controller }) {
            ordered.append(controller)
        }
        return ordered
    }

    // MARK: - Keyboard

    /// The bar that has the keyboard, if one does.
    private var keyboardBar: BarWindowController? { controllers.values.first(where: \.hasKeyboard) }

    /// The app a bar with the keyboard will give it back to — for the launcher, which takes the
    /// keyboard over when opened from that bar and has to give it back to the same place.
    var keyboardReturnApp: NSRunningApplication? { keyboardBar?.keyboardReturn }

    /// Moves focus to a bar, or gives it back if a bar already has it.
    ///
    /// Tries the bars in order of preference, since the first may be unable to take it — put away
    /// by a full-screen app on its display — while another display's bar is sitting there.
    ///
    /// - Parameter fallback: see `BarWindowController.takeKeyboard(returningTo:)`.
    func toggleKeyboard(returningTo fallback: NSRunningApplication?) {
        if let bar = keyboardBar {
            bar.releaseKeyboard(restoringFocus: true)
            return
        }
        for controller in barsByPreference() where controller.takeKeyboard(returningTo: fallback) {
            return
        }
    }

    func closeAll() {
        for controller in controllers.values { controller.close() }
        controllers.removeAll()
    }
}
