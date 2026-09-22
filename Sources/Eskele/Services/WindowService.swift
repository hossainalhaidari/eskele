import AppKit
import ApplicationServices

struct AppWindow {
    let element: AXUIElement
    let title: String
    /// `AXStandardWindow`, `AXDialog`, `AXSystemDialog`, `AXFloatingWindow`… or empty when the app
    /// does not say. This is what separates a real window from the toolbars and panels that share
    /// the same attribute.
    let subrole: String
    let isMinimized: Bool
    let isFullScreen: Bool
    /// The element is this window's item in the app's Window menu rather than the window itself.
    ///
    /// Accessibility will not enumerate a window on another Space, but the app's own Window menu
    /// lists it — and pressing that item, with the app frontmost, is a route to the window that
    /// needs no element obtained in advance. Measured: pressing it *before* activating does not
    /// cross the Space; activating first does.
    var isMenuProxy: Bool = false
    /// This window is not on the Space we are looking at.
    ///
    /// `AXWindows` lists the active Space and nothing else, so an entry that had to be recovered
    /// some other way — the focused/main attributes, or the element cache — is by construction one
    /// that `AXWindows` declined to return, which is to say one on another Space.
    var isOffSpace: Bool = false
    /// The display this window's origin sits on, when anyone asked. Only `ScreenMode.perDisplay`
    /// does, and only on a machine with more than one display — see `WindowInfoService`.
    var display: CGDirectDisplayID?

    /// A modal the app has put up. Combined with "and the app is not frontmost", this is the one
    /// attention signal macOS actually lets another process see.
    var isDialog: Bool {
        subrole == "AXDialog" || subrole == "AXSystemDialog"
    }

    /// Evidence that the display this window is on is *currently* showing a full-screen Space.
    ///
    /// A full-screen window on some other Space is emphatically not that, and treating it as such
    /// makes the bar behave, on an ordinary desktop, as though it were in full screen.
    var showsActiveSpaceFullScreen: Bool { isFullScreen && !isOffSpace }

    /// Whether this deserves a button and a place in the window list.
    ///
    /// Windowless AX entries — toolbars, palettes, the ghost windows some apps keep around — arrive
    /// in the same array and would otherwise become buttons for nothing. A title used to be the only
    /// filter, but a full-screen window frequently reports none, which is how full-screen windows
    /// went missing from the bar; a standard subrole vouches for those.
    var isListable: Bool {
        !title.isEmpty || subrole == (kAXStandardWindowSubrole as String)
    }
}

/// A window reduced to what fixes its place in the cycle: what the bar calls it, and where it is.
struct CycleKey: Equatable {
    var title: String
    /// The window's screen origin, or zero for one that will not say — a menu-listed window on
    /// another Space, mostly, which has no geometry to report.
    var origin: CGPoint
}

/// A window as the bar models it — no `AXUIElement`, so it can be compared, stored and diffed.
///
/// Identified by title rather than by any window id: the only stable identifier macOS exposes is
/// behind a private symbol, and a title is good enough to re-find the window at click time.
struct WindowRef: Equatable {
    var pid: pid_t
    var title: String
    var isMinimized: Bool
    /// In a native full-screen space of its own.
    var isFullScreen: Bool = false
    /// Not on the Space we are looking at, so Accessibility would not enumerate it.
    var isOffSpace: Bool = false
    /// False for a window we know exists but cannot address: Accessibility only exposes the active
    /// Space, so a full-screen window elsewhere has no element to raise. Clicking one activates its
    /// app instead, which is the same thing the system Dock's own icon can offer.
    var isReachable: Bool = true
    /// The app's focused window. Without this every window of the active app would draw as active.
    var isFocused: Bool = false
    /// Distinguishes two windows of one app that happen to share a title.
    var duplicateIndex: Int = 0
    /// Which display the window is on, or `nil` when nobody asked — which is every mode but
    /// `ScreenMode.perDisplay`. A window with no display is shown on every bar rather than none.
    var display: CGDirectDisplayID?

    var id: String { "window:\(pid):\(title)#\(duplicateIndex)" }
}

/// Per-application window lists, via the Accessibility API.
///
/// Entirely optional: everything else in Eskele works without any permission, and this degrades to
/// a single "grant access" menu item when Accessibility has not been granted.
@MainActor
final class WindowService {
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Raises the system prompt. There is no way to grant this programmatically, and no way to
    /// re-prompt once the user has answered — after that they must use System Settings.
    func requestTrust() {
        // The SDK exposes the key as a mutable global, which Swift 6 will not let us touch; its
        // value is a documented constant string.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Elements for full-screen windows we have seen, kept per app.
    ///
    /// A window in a full-screen Space drops out of `AXWindows` the moment you leave that Space, but
    /// the element you already hold stays valid for as long as the window lives — and `AXRaise` on
    /// it is what makes the app's *front* window the full-screen one, which is the difference
    /// between activating the app and actually getting there. Without this, an app holding both an
    /// ordinary and a full-screen window always activates onto the ordinary one.
    private var fullScreenCache: [pid_t: [AXUIElement]] = [:]

    /// Whether each app's last Accessibility read timed out. `nil` for an app never read.
    private var didTimeOut: [pid_t: Bool] = [:]

    /// Whether the app failed to answer its last Accessibility read.
    ///
    /// Only ever true with Accessibility granted — without it every read fails as `apiDisabled`
    /// long before any timeout, which is a fact about us rather than about the app.
    func didFailToAnswer(pid: pid_t) -> Bool { didTimeOut[pid] ?? false }

    /// AX calls are synchronous IPC into another process. A hung app would otherwise block the bar
    /// for the default six seconds; a quarter of a second is far longer than a healthy app needs.
    private static let messagingTimeout: Float = 0.12
    /// Long enough for the activation to land before the menu item is pressed.
    private static let menuPressDelay: TimeInterval = 0.2

    /// Every AX window the app exposes, including the ones that are not worth a button.
    ///
    /// Unfiltered on purpose: `isDialog` has to be evaluated over the whole set, and an alert panel
    /// is exactly the kind of entry a listable-only sweep would throw away.
    /// - Parameter includingOffSpace: also ask for the focused and main windows and fold in
    ///   anything `AXWindows` left out. Two extra round trips per app, so it is off by default and
    ///   asked for only where the window server says there is something to find — §5.16's whole
    ///   point is that a per-app AX call on every sweep is what made the bar lag.
    /// - Parameter includingDisplays: also read each window's position, so it can be told which
    ///   display it is on. One more round trip *per window*, against four the sweep already makes,
    ///   so it is asked for only by the one mode that filters bars by display.
    func windows(
        for pid: pid_t, includingOffSpace: Bool = false, includingDisplays: Bool = false
    ) -> [AppWindow] {
        guard isTrusted else { return [] }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, WindowService.messagingTimeout)

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        // An AX read is a synchronous message to the app's own event loop, so an app that does not
        // answer inside the timeout is an app that is not pumping it — which is exactly what "not
        // responding" means. Recorded here rather than probed separately: the sweep is already
        // asking, and a second round trip per app is the cost this service exists to avoid.
        didTimeOut[pid] = status == .cannotComplete
        guard status == .success, let elements = value as? [AXUIElement] else { return [] }

        // `AXWindows` only ever lists the active Space's windows, but `AXFocusedWindow` and
        // `AXMainWindow` happily hand back an element for one on another Space — measured: VS Code
        // enumerated one window while its focused window was a different, full-screen one. Folding
        // them in recovers that window with its real title and a raisable element, which a count
        // from the window server could never give us.
        var offSpace: [AXUIElement] = []
        for attribute in includingOffSpace ? [kAXFocusedWindowAttribute, kAXMainWindowAttribute] : [] {
            var found: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                application, attribute as CFString, &found) == .success,
                let found
            else { continue }
            let window = found as! AXUIElement
            // Anything `AXWindows` already returned is on this Space; only what it left out is not.
            guard !elements.contains(where: { CFEqual($0, window) }),
                  !offSpace.contains(where: { CFEqual($0, window) })
            else { continue }
            offSpace.append(window)
        }

        var windows = elements.map { describe($0, isOffSpace: false, wantsDisplay: includingDisplays) }
        guard includingOffSpace else {
            remember(windows, for: pid)
            return windows
        }

        windows += offSpace.map { describe($0, isOffSpace: true, wantsDisplay: includingDisplays) }
        // Remembered *after* the fold-in and *before* the recovery: an element reached through the
        // focused-window attribute is often the only time we ever see that window, so dropping it
        // here is what leaves the cache empty and the button unable to target anything. Recovered
        // windows come out of the cache and have no business going back into it.
        remember(windows, for: pid)
        windows += recoveredFullScreenWindows(
            for: pid, excluding: windows, wantsDisplay: includingDisplays)
        windows += menuListedWindows(pid: pid, application: application, known: windows)
        return windows
    }

    /// Windows the app lists in its Window menu that Accessibility will not enumerate.
    ///
    /// The menu is found without knowing its name — localisation would make that unreliable — by
    /// looking for the run of items at the end of a menu that contains a window we already know
    /// about. That match is also the proof it is the window list rather than some other trailing
    /// group, so an app laid out differently yields nothing rather than nonsense.
    private func menuListedWindows(
        pid: pid_t, application: AXUIElement, known: [AppWindow]
    ) -> [AppWindow] {
        let knownTitles = Set(known.map(\.title).filter { !$0.isEmpty })
        guard !knownTitles.isEmpty, let bar = element(application, kAXMenuBarAttribute) else { return [] }

        // The Window menu sits near the end, so searching backwards usually stops on the second try.
        for menu in (children(bar) ?? []).reversed() {
            guard let contents = children(menu)?.first, let items = children(contents) else { continue }
            let titled = items.map { ($0, string(of: $0, kAXTitleAttribute) ?? "") }
            // Separators come through as untitled items; the window list is the run after the last.
            guard let separator = titled.lastIndex(where: { $0.1.isEmpty }) else { continue }
            let group = titled[(separator + 1)...]
            guard group.contains(where: { knownTitles.contains($0.1) }) else { continue }

            return group
                .filter { !$0.1.isEmpty && !knownTitles.contains($0.1) }
                .map { item, title in
                    AppWindow(
                        element: item,
                        title: title,
                        subrole: kAXStandardWindowSubrole as String,
                        isMinimized: false,
                        isFullScreen: false,
                        isMenuProxy: true,
                        isOffSpace: true)
                }
        }
        return []
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

    private func describe(
        _ element: AXUIElement, isOffSpace: Bool, wantsDisplay: Bool = false
    ) -> AppWindow {
        AppWindow(
            element: element,
            title: string(of: element, kAXTitleAttribute) ?? "",
            subrole: string(of: element, kAXSubroleAttribute) ?? "",
            isMinimized: bool(of: element, kAXMinimizedAttribute) ?? false,
            isFullScreen: bool(of: element, "AXFullScreen") ?? false,
            isOffSpace: isOffSpace,
            display: wantsDisplay ? display(of: element) : nil)
    }

    /// The display a window belongs to, judged by its origin.
    ///
    /// The origin rather than the centre because the centre costs a second read for its size, and a
    /// window straddling two displays has no right answer anyway — only a consistent one. This is
    /// the same rule `fullScreenDisplays` has always used.
    private func display(of element: AXUIElement) -> CGDirectDisplayID? {
        guard let origin = point(of: element, kAXPositionAttribute) else { return nil }
        return displayContaining(origin)
    }

    private func remember(_ windows: [AppWindow], for pid: pid_t) {
        let seen = windows.filter(\.isFullScreen).map(\.element)
        guard !seen.isEmpty else { return }
        var known = fullScreenCache[pid] ?? []
        for element in seen where !known.contains(where: { CFEqual($0, element) }) {
            known.append(element)
        }
        fullScreenCache[pid] = known
    }

    /// Full-screen windows we hold an element for that the current AX list no longer contains —
    /// which is exactly a window that has moved out of the Space we are on.
    ///
    /// Each is validated by reading its title: a closed window's element answers nothing, which is
    /// also how the cache is pruned.
    private func recoveredFullScreenWindows(
        for pid: pid_t, excluding current: [AppWindow], wantsDisplay: Bool = false
    ) -> [AppWindow] {
        guard let cached = fullScreenCache[pid], !cached.isEmpty else { return [] }
        var alive: [AXUIElement] = []
        var recovered: [AppWindow] = []

        for element in cached {
            guard let title = string(of: element, kAXTitleAttribute) else { continue }
            alive.append(element)
            guard !current.contains(where: { CFEqual($0.element, element) }) else { continue }
            recovered.append(AppWindow(
                element: element,
                title: title,
                subrole: string(of: element, kAXSubroleAttribute) ?? (kAXStandardWindowSubrole as String),
                isMinimized: false,
                isFullScreen: true,
                isOffSpace: true,
                // The Space is elsewhere but the element is live, so it still knows its display —
                // and a full-screen Space belongs to exactly one.
                display: wantsDisplay ? display(of: element) : nil))
        }

        fullScreenCache[pid] = alive.isEmpty ? nil : alive
        return recovered
    }

    /// The windows the user can actually pick out of a list.
    func listableWindows(for pid: pid_t) -> [AppWindow] {
        // A menu or a click is a one-off, so it can always afford to look everywhere.
        windows(for: pid, includingOffSpace: true).filter(\.isListable)
    }

    /// Displays whose *current* Space is a full-screen one, judged from these windows.
    ///
    /// Deliberately not every full-screen window: an app can hold one on a Space nobody is looking
    /// at, and counting that would tell the bar it is in full screen while the user is on an
    /// ordinary desktop — which, with "Reveal on Hover", makes an un-auto-hidden bar auto-hide.
    ///
    /// Only the full-screen windows are asked for their position, so this costs nothing on the
    /// overwhelmingly common path where an app has none.
    func fullScreenDisplays(among windows: [AppWindow]) -> Set<CGDirectDisplayID> {
        var displays: Set<CGDirectDisplayID> = []
        for window in windows where window.showsActiveSpaceFullScreen {
            guard let origin = point(of: window.element, kAXPositionAttribute),
                  let display = displayContaining(origin) else { continue }
            displays.insert(display)
        }
        return displays
    }

    /// Whether the frontmost app's focused window is natively full-screen, and which display it is
    /// on. Authoritative, unlike the geometric guess in `FullScreenMonitor` — but only available
    /// once the user has granted Accessibility.
    func focusedWindowFullScreen(pid: pid_t) -> (display: CGDirectDisplayID, isFullScreen: Bool)? {
        guard isTrusted else { return nil }
        let application = AXUIElementCreateApplication(pid)
        // Runs on every activation, so a hung frontmost app must not hold the bar up for AX's
        // default six seconds. Timing out reads as "not full-screen", which shows the bar.
        AXUIElementSetMessagingTimeout(application, WindowService.messagingTimeout)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
            let focused
        else { return nil }
        // CFTypeRef carries no static type; this is the documented shape of the attribute.
        let window = focused as! AXUIElement

        // `AXFocusedWindow` is not bound by the Space, and an app's focused window is quite often a
        // full-screen one the user is not currently looking at. Only a window this Space actually
        // contains says anything about this Space — and `AXWindows` is exactly the list of those.
        var listed: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &listed) == .success,
            let onThisSpace = listed as? [AXUIElement],
            onThisSpace.contains(where: { CFEqual($0, window) })
        else { return nil }

        let isFullScreen = bool(of: window, "AXFullScreen") ?? false
        guard let origin = point(of: window, kAXPositionAttribute) else { return nil }
        guard let display = displayContaining(origin) else { return nil }
        return (display, isFullScreen)
    }

    private func point(of element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    /// AX reports positions in Core Graphics coordinates (top-left origin), which is also what
    /// `CGDisplayBounds` uses — so no flipping is needed here.
    private func displayContaining(_ point: CGPoint) -> CGDirectDisplayID? {
        NSScreen.screens
            .compactMap { ScreenMetrics.displayID(of: $0) }
            .first { CGDisplayBounds($0).contains(point) }
    }

    /// Raises the window after the focused one, wrapping around.
    ///
    /// What clicking an already-frontmost app with several windows should do: step through them,
    /// the way ⌘` does, rather than hiding an app the user is plainly still working in.
    func cycleWindow(pid: pid_t) -> Bool {
        if pid == WindowService.ownPID { return cycleOwn() }
        let list = listableWindows(for: pid)
        guard list.count > 1 else { return false }

        let ordered = WindowService.cycleOrder(list.map {
            CycleKey(title: $0.title, origin: point(of: $0.element, kAXPositionAttribute) ?? .zero)
        }).map { list[$0] }

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, WindowService.messagingTimeout)
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused)

        var index = 0
        if let focused {
            let current = focused as! AXUIElement
            if let found = ordered.firstIndex(where: { CFEqual($0.element, current) }) {
                index = (found + 1) % ordered.count
            }
        }
        raise(ordered[index], pid: pid)
        return true
    }

    /// The order to step through an app's windows in: the title order the bar already lays its
    /// window buttons out in, and pointedly *not* the z-order `AXWindows` hands back.
    ///
    /// Cycling by z-order is what stopped an app at two windows however many it had. Raising a
    /// window makes it the front one, so the list the next click sees has the window just raised
    /// at the head and the one before it immediately after — "the window after the focused one"
    /// is forever the window the last click came from, and the other three never come up.
    ///
    /// Position breaks ties between windows sharing a title, since unlike the array order it
    /// stays put when focus moves; the index behind it settles the rest, so the sequence is fully
    /// determined and does not lean on `sorted` being stable, which it is not.
    ///
    /// - Returns: indices into `keys`, in cycle order.
    nonisolated static func cycleOrder(_ keys: [CycleKey]) -> [Int] {
        keys.indices.sorted { left, right in
            let (a, b) = (keys[left], keys[right])
            switch a.title.localizedStandardCompare(b.title) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: break
            }
            if a.origin.x != b.origin.x { return a.origin.x < b.origin.x }
            if a.origin.y != b.origin.y { return a.origin.y < b.origin.y }
            return left < right
        }
    }

    /// Value-type snapshot of an app's windows, ordered by title so buttons keep their positions.
    ///
    /// AX returns windows in z-order, which changes every time the user switches between them —
    /// laying buttons out in that order would make them shuffle as you work.
    func windowRefs(for pid: pid_t) -> [WindowRef] {
        windowRefs(for: pid, from: windows(for: pid), includeFocus: true)
    }

    /// Whether the app has a minimised window the bar would list, read live rather than from the
    /// last sweep: the sweep may not have caught the minimise yet, and for our own process nothing
    /// prompts one. Our own windows need no permission; anyone else's need Accessibility, and
    /// without it the answer is no.
    ///
    /// **Measured on macOS 27.0**, with an AppKit window: it leaves the screen 3–7ms before
    /// `isMiniaturized` turns true, and the app's main thread is busy with the animation until
    /// about then. So a scan that finds it gone cannot land in that gap for our own windows. For
    /// anyone else's, the AX read is answered by that same busy main thread, so it should wait out
    /// the gap well inside `messagingTimeout` — inferred from the stall, not measured through AX.
    func hasMinimisedWindow(pid: pid_t) -> Bool {
        if pid == WindowService.ownPID { return ownWindowRefs().contains(where: \.isMinimized) }
        return windows(for: pid).contains { $0.isMinimized && $0.isListable }
    }

    /// - Parameter includeFocus: only the frontmost app needs its focused window identified — for
    ///   any other app no window draws as active, and the lookup is a wasted round trip into a
    ///   process that may be slow to answer.
    func windowRefs(for pid: pid_t, from windows: [AppWindow], includeFocus: Bool) -> [WindowRef] {
        let focusedTitle = includeFocus ? focusedWindowTitle(pid: pid) : nil
        // A full-screen window often has no title of its own; falling back to the app's name keeps
        // it identifiable rather than dropping it, which is what used to happen.
        let fallback = NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? String(localized: "Window", comment: "Stand-in name for a window that has no title and no app name")
        var seen: [String: Int] = [:]
        return windows
            .filter(\.isListable)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { window in
                let title = window.title.isEmpty ? fallback : window.title
                let count = seen[title, default: 0]
                seen[title] = count + 1
                return WindowRef(
                    pid: pid,
                    title: title,
                    isMinimized: window.isMinimized,
                    isFullScreen: window.isFullScreen,
                    isOffSpace: window.isOffSpace,
                    // Matched by title: with duplicate titles only the first is marked, which is
                    // the best that can be done without a stable window identifier.
                    isFocused: !window.title.isEmpty && window.title == focusedTitle && count == 0,
                    duplicateIndex: count,
                    display: window.display)
            }
    }

    private func focusedWindowTitle(pid: pid_t) -> String? {
        guard isTrusted else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, WindowService.messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
            let focused
        else { return nil }
        return string(of: focused as! AXUIElement, kAXTitleAttribute)
    }

    /// Re-resolves the window by title at the moment of the click, because the element captured
    /// when the bar was built may since have gone.
    @discardableResult
    func raiseWindow(_ reference: WindowRef) -> Bool {
        if reference.pid == WindowService.ownPID { return raiseOwn(reference) }
        guard let window = resolve(reference) else { return false }
        raise(window, pid: reference.pid)
        return true
    }

    @discardableResult
    func setMinimized(_ reference: WindowRef, _ minimized: Bool) -> Bool {
        if reference.pid == WindowService.ownPID {
            guard let window = resolveOwn(reference) else { return false }
            minimized ? window.miniaturize(nil) : window.deminiaturize(nil)
            if !minimized { activateOwn(window) }
            return true
        }
        guard let window = resolve(reference) else { return false }
        AXUIElementSetAttributeValue(
            window.element, kAXMinimizedAttribute as CFString,
            minimized ? kCFBooleanTrue : kCFBooleanFalse)
        if !minimized { NSRunningApplication(processIdentifier: reference.pid)?.activate() }
        return true
    }

    /// Closes one window, leaving the rest of its app alone.
    ///
    /// Accessibility exposes no close *action*, so this presses the window's own close button —
    /// which is also why it goes through the app's normal path: a document with unsaved changes
    /// still gets to put its sheet up, exactly as if the user had clicked the red dot.
    @discardableResult
    func closeWindow(_ reference: WindowRef) -> Bool {
        if reference.pid == WindowService.ownPID {
            guard let window = resolveOwn(reference) else { return false }
            // `performClose` rather than `close`: it goes through the close button and the window's
            // delegate, which is the same path the AX branch below takes for everyone else.
            window.performClose(nil)
            return true
        }
        guard let window = resolve(reference), !window.isMenuProxy else { return false }
        guard let button = element(window.element, kAXCloseButtonAttribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// The live window a reference names, at the moment it is asked for.
    ///
    /// A reference is a value type built when the bar was last laid out; by the time the user acts
    /// on it the element behind it may be gone, so every mutation re-finds its target rather than
    /// holding one.
    // MARK: - Our own windows

    /// Our own process, which Accessibility declines to describe.
    nonisolated static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Our own windows, read from AppKit because Accessibility will not report them.
    ///
    /// **Measured on macOS 26.6:** `AXUIElementCopyAttributeValue` aimed at our own process returns
    /// `kAXErrorNotImplemented` (-25208) — immediately, not as a timeout — and
    /// `AXObserverAddNotification` on our own pid is refused the same way. macOS does not let a
    /// process inspect itself through Accessibility. Without this the one app whose settings window
    /// prompted the whole feature would be the one app the feature could not describe: it would get
    /// a cell reporting no windows, and a click that had nothing to raise.
    ///
    /// Nothing is lost by not using AX here — we hold these windows already. Only `.normal`-level
    /// windows are listed, which is the same cut `AccessoryAppsService` makes from outside at layer
    /// 0: the bar, the launcher, the tooltip and the edge trigger all sit above it, so this yields
    /// the settings and onboarding windows and nothing else.
    func ownWindowRefs() -> [WindowRef] {
        var seen: [String: Int] = [:]
        return sortedOwnWindows().map { window in
            let title = ownTitle(of: window)
            let count = seen[title, default: 0]
            seen[title] = count + 1
            return WindowRef(
                pid: WindowService.ownPID,
                title: title,
                isMinimized: window.isMiniaturized,
                isFocused: window.isKeyWindow && count == 0,
                duplicateIndex: count,
                display: window.screen.flatMap(ScreenMetrics.displayID(of:)))
        }
    }

    /// A window with no title of its own falls back to the app's name, exactly as the AX path does.
    private func ownTitle(of window: NSWindow) -> String {
        window.title.isEmpty ? (NSRunningApplication.current.localizedName
            ?? String(localized: "Window", comment: "Stand-in name for a window that has no title and no app name")) : window.title
    }

    /// Sorted by title for the same reason the AX list is: z-order changes as the user works, and
    /// laying buttons out in it would make them shuffle.
    private func sortedOwnWindows() -> [NSWindow] {
        NSApplication.shared.windows
            .filter { $0.level == .normal && ($0.isVisible || $0.isMiniaturized) }
            .sorted { ownTitle(of: $0).localizedStandardCompare(ownTitle(of: $1)) == .orderedAscending }
    }

    /// The window a reference names, matched the way `resolve` matches an AX one.
    private func resolveOwn(_ reference: WindowRef) -> NSWindow? {
        let matches = sortedOwnWindows().filter { ownTitle(of: $0) == reference.title }
        let index = min(reference.duplicateIndex, max(0, matches.count - 1))
        return matches.indices.contains(index) ? matches[index] : nil
    }

    /// Brings our own front window back, whichever it is.
    ///
    /// This is what a click on our own cell ends up meaning. `ActivationPolicy` answers `.reopen`
    /// for any app that is running but not frontmost, and reopening an agent that is already running
    /// does nothing on its own — so without this the one cell the feature was asked for would be the
    /// one cell that did nothing when clicked. Never creates a window: the cell exists because a
    /// window does.
    @discardableResult
    func raiseOwnFrontWindow() -> Bool {
        let windows = sortedOwnWindows()
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        activateOwn(window)
        return true
    }

    private func raiseOwn(_ reference: WindowRef) -> Bool {
        guard let window = resolveOwn(reference) else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        activateOwn(window)
        return true
    }

    /// An agent has to ask for activation explicitly; ordering the window front on its own would
    /// leave it behind whatever the user was last in.
    private func activateOwn(_ window: NSWindow) {
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func cycleOwn() -> Bool {
        let windows = sortedOwnWindows().filter { !$0.isMiniaturized }
        guard windows.count > 1 else { return false }
        let ordered = WindowService.cycleOrder(
            windows.map { CycleKey(title: ownTitle(of: $0), origin: $0.frame.origin) }
        ).map { windows[$0] }

        var index = 0
        if let found = ordered.firstIndex(where: \.isKeyWindow) {
            index = (found + 1) % ordered.count
        }
        activateOwn(ordered[index])
        return true
    }

    private func resolve(_ reference: WindowRef) -> AppWindow? {
        let matches = matchingWindows(for: reference)
        let index = min(reference.duplicateIndex, max(0, matches.count - 1))
        guard matches.indices.contains(index) else { return nil }
        return matches[index]
    }

    /// Re-finds the windows a reference could name. Untitled windows were given the app's name when
    /// the reference was built, so they have to be matched on that same substitution.
    private func matchingWindows(for reference: WindowRef) -> [AppWindow] {
        let fallback = NSRunningApplication(processIdentifier: reference.pid)?.localizedName
            ?? String(localized: "Window", comment: "Stand-in name for a window that has no title and no app name")
        return listableWindows(for: reference.pid).filter {
            ($0.title.isEmpty ? fallback : $0.title) == reference.title
        }
    }

    func raise(_ window: AppWindow, pid: pid_t) {
        if window.isMenuProxy {
            // Measured: the app has to be frontmost before its menu item will carry us across the
            // Space, so the activation leads and the press follows a beat later.
            NSRunningApplication(processIdentifier: pid)?.activate()
            let item = window.element
            DispatchQueue.main.asyncAfter(deadline: .now() + WindowService.menuPressDelay) {
                AXUIElementPerformAction(item, kAXPressAction as CFString)
            }
            return
        }
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        // Raising makes it the app's front window; activating is then what follows it into its
        // Space. Order matters — activate first and macOS goes to whichever window was already
        // frontmost, which for a full-screen window elsewhere is the wrong one.
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    private func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func bool(of element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        // Comes back as a CFBoolean; NSNumber is handled too in case an app answers with one.
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return CFBooleanGetValue((value as! CFBoolean)) }
        return (value as? NSNumber)?.boolValue
    }
}
