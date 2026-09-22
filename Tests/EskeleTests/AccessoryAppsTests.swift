import Foundation
import AppKit
import Testing
@testable import Eskele

// MARK: - Which window server entries count as a window

/// The layers measured on macOS 26.6, and what lives at each. Only one of them is a window the user
/// would want a cell for; the rest are the chrome a menu-bar app hangs off the menu bar, which is
/// what every agent on the machine has and what would make the feature noise if it counted.
private let ordinaryWindow = 0
private let systemDock = 20
private let eskeleBar = 21          // CGWindowLevelForKey(.dockWindow) + 1
private let eskeleTooltip = 22      // ... + 2, shared with the edge trigger
private let menuBar = 24
private let statusItem = 25
private let popUpMenu = 101

@Test func anOrdinaryWindowCounts() {
    #expect(AccessoryAppsService.qualifies(layer: ordinaryWindow, alpha: 1, width: 520, height: 400))
}

/// The measurement the whole pre-filter rests on: an accessory app's ordinary windows are reported
/// at layer 0 exactly like a regular app's, so the layer separates "a window" from "menu-bar
/// chrome" with nothing left over.
@Test func nothingAboveTheOrdinaryWindowLayerCounts() {
    for layer in [systemDock, eskeleBar, eskeleTooltip, menuBar, statusItem, popUpMenu] {
        #expect(!AccessoryAppsService.qualifies(layer: layer, alpha: 1, width: 520, height: 400))
    }
}

/// Eskele is itself an accessory app, so it is scanned like any other. Its bar must never earn it a
/// cell on its own bar; its settings window must.
@Test func eskelesOwnBarIsNotAWindowButItsSettingsWindowIs() {
    #expect(!AccessoryAppsService.qualifies(layer: eskeleBar, alpha: 1, width: 1470, height: 40))
    #expect(AccessoryAppsService.qualifies(layer: ordinaryWindow, alpha: 1, width: 520, height: 400))
}

/// On screen in the window server's sense, invisible in every sense the user has.
@Test func aFullyTransparentWindowDoesNotCount() {
    #expect(!AccessoryAppsService.qualifies(layer: ordinaryWindow, alpha: 0, width: 520, height: 400))
    #expect(AccessoryAppsService.qualifies(layer: ordinaryWindow, alpha: 0.05, width: 520, height: 400))
}

/// The small layer-0 windows agents keep around for event capture and drag feedback.
@Test func aWindowTooSmallToBeRealDoesNotCount() {
    #expect(!AccessoryAppsService.qualifies(layer: ordinaryWindow, alpha: 1, width: 1, height: 1))
    #expect(!AccessoryAppsService.qualifies(layer: ordinaryWindow, alpha: 1, width: 520, height: 20))
    #expect(!AccessoryAppsService.qualifies(layer: ordinaryWindow, alpha: 1, width: 40, height: 400))
}

/// The floor sits well below the smallest plausible settings window, so the boundary itself is what
/// needs pinning down rather than any particular real window.
@Test func theSizeFloorIsInclusive() {
    let size = AccessoryAppsService.minimumSize
    #expect(AccessoryAppsService.qualifies(
        layer: ordinaryWindow, alpha: 1, width: size.width, height: size.height))
    #expect(!AccessoryAppsService.qualifies(
        layer: ordinaryWindow, alpha: 1, width: size.width - 1, height: size.height))
}

/// A missing `kCGWindowBounds` arrives as zero, which must read as "not a window" rather than
/// falling through the floor untested.
@Test func anEntryWithNoBoundsDoesNotCount() {
    #expect(!AccessoryAppsService.qualifies(layer: ordinaryWindow, alpha: 1, width: 0, height: 0))
}

/// A real scan of this machine. Regular apps are on the bar under their own rules, so admitting one
/// here would produce a second, competing source of truth for the same cell.
@Test func aLiveScanOnlyEverReportsAppsItWasAskedAbout() {
    let accessory = Set(
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .accessory }
            .map(\.processIdentifier))
    #expect(AccessoryAppsService.scan(accessory: accessory).isSubset(of: accessory))
    #expect(AccessoryAppsService.scan(accessory: []).isEmpty)
}

// MARK: - Minimised windows

/// Runs `keeping` and records which apps it asked about, since asking is an Accessibility round trip
/// into that app and who gets asked is as much the rule as who is kept.
private func keeping(
    onScreen: Set<pid_t>, previous: Set<pid_t>, accessory: Set<pid_t>, minimised: Set<pid_t>
) -> (kept: Set<pid_t>, asked: Set<pid_t>) {
    var asked: Set<pid_t> = []
    let kept = AccessoryAppsService.keeping(
        onScreen, previous: previous, accessory: accessory,
        hasMinimisedWindow: { pid in
            asked.insert(pid)
            return minimised.contains(pid)
        })
    return (kept, asked)
}

/// The bug this exists for: minimising the settings window took its cell away, and with it the
/// only route back from the bar.
@Test func minimisingAWindowKeepsItsCell() {
    let result = keeping(onScreen: [], previous: [7], accessory: [7], minimised: [7])
    #expect(result.kept == [7])
}

/// Closing is still what takes the cell away — the cell is transient, it just outlives a minimise.
@Test func closingTheWindowStillTakesTheCellAway() {
    let result = keeping(onScreen: [], previous: [7], accessory: [7], minimised: [])
    #expect(result.kept.isEmpty)
}

/// The window server already answered for these, so asking again is a round trip for nothing.
@Test func anAppWithAWindowOnScreenIsNotAskedAboutMinimisedOnes() {
    let result = keeping(onScreen: [7], previous: [7], accessory: [7], minimised: [])
    #expect(result.kept == [7])
    #expect(result.asked.isEmpty)
}

/// Only apps that already have a cell are asked. Every other agent on the machine stays out of it,
/// which is what keeps this from being an Accessibility sweep of dozens of processes — and the
/// price is that a window minimised before any scan saw it earns no cell.
@Test func onlyAppsThatAlreadyHaveACellAreAsked() {
    let result = keeping(onScreen: [], previous: [7], accessory: [7, 8, 9], minimised: [7, 8, 9])
    #expect(result.kept == [7])
    #expect(result.asked == [7])
}

/// A cell whose app has quit, or stopped being an accessory app, goes without asking: there is
/// nobody to ask, or the app is on the bar under the regular rules instead.
@Test func anAppThatIsNoLongerAnAccessoryAppIsDroppedWithoutAsking() {
    let result = keeping(onScreen: [], previous: [7], accessory: [], minimised: [7])
    #expect(result.kept.isEmpty)
    #expect(result.asked.isEmpty)
}

/// With nothing to ask — the default — minimising behaves as it always did.
@Test func withNoWayToAskAMinimisedWindowTakesItsCellAway() {
    let kept = AccessoryAppsService.keeping(
        [], previous: [7], accessory: [7], hasMinimisedWindow: { _ in false })
    #expect(kept.isEmpty)
}

// MARK: - Which apps get a cell

private let own = "de.alhaidari.Eskele"

private func listed(
    _ policy: NSApplication.ActivationPolicy,
    pid: pid_t = 1,
    bundleID: String? = "com.example.app",
    windowed: Set<pid_t> = []
) -> Bool {
    RunningAppsService.isListed(
        policy: policy, pid: pid, bundleID: bundleID, ownBundleID: own, windowed: windowed)
}

@Test func regularAppsAreListedWhateverTheirWindows() {
    #expect(listed(.regular))
    #expect(listed(.regular, windowed: [1]))
}

@Test func theBarNeverShowsACellForItself() {
    #expect(!listed(.regular, bundleID: own))
}

/// The rule that makes the cell transient: an agent earns its place by having a window, and loses
/// it when the window closes.
@Test func aMenuBarAppIsListedOnlyWhileItHasAWindow() {
    #expect(!listed(.accessory, pid: 7))
    #expect(listed(.accessory, pid: 7, windowed: [7]))
    #expect(!listed(.accessory, pid: 7, windowed: [9]))
}

/// Eskele is an accessory app, so the self-exclusion above cannot be what keeps it off the bar —
/// the layer filter is. Once its settings window is open it is a menu-bar app like any other, which
/// is the case the feature was asked for.
@Test func eskelesOwnSettingsWindowEarnsItACell() {
    #expect(listed(.accessory, pid: 7, bundleID: own, windowed: [7]))
    #expect(!listed(.accessory, pid: 7, bundleID: own, windowed: []))
}

/// A prohibited process cannot be activated, so its cell would be a button that does nothing.
@Test func prohibitedAppsAreNeverListed() {
    #expect(!listed(.prohibited, pid: 7, windowed: [7]))
}

// MARK: - Which apps are swept for windows

private func tracked(_ policy: NSApplication.ActivationPolicy, accessory: Set<pid_t> = []) -> Bool {
    WindowInfoService.isTracked(policy: policy, pid: 7, accessory: accessory)
}

/// An AX read is a synchronous message into another process, so the set swept is the set this can
/// be delayed by. It must track the set of cells exactly: a cell whose app is not swept would never
/// learn how many windows it has, and an app swept with no cell is a round trip for nothing.
@Test func theSweptSetMatchesTheListedSet() {
    #expect(tracked(.regular))
    #expect(!tracked(.accessory))
    #expect(tracked(.accessory, accessory: [7]))
    #expect(!tracked(.prohibited, accessory: [7]))
}

// MARK: - The setting

/// The cell is by definition an unpinned running app, so it has nowhere to appear while the run of
/// running apps is off — and scanning for one would be work for a cell that could not be drawn.
@Test func menuBarAppsAreOnlyTrackedWhereTheyCouldBeDrawn() {
    var settings = Settings()
    settings.showAccessoryApps = true
    settings.showRunningUnpinned = true
    #expect(settings.tracksAccessoryApps)

    settings.showRunningUnpinned = false
    #expect(!settings.tracksAccessoryApps)

    settings.showRunningUnpinned = true
    settings.showAccessoryApps = false
    #expect(!settings.tracksAccessoryApps)
}

/// Off by default: it changes what the bar shows, so it is opted into rather than discovered.
@Test func menuBarAppsAreOffByDefault() {
    #expect(!Settings().showAccessoryApps)
    #expect(!Settings().tracksAccessoryApps)
}

/// `Settings` decodes by hand, one assignment per field, so a field added to the struct and
/// forgotten in `init(from:)` would be silently dropped on every load — the setting would appear to
/// work until the app was restarted. Encode and decode is what catches that.
@Test func theSettingSurvivesBeingSavedAndLoaded() throws {
    var settings = Settings()
    settings.showAccessoryApps = true

    let data = try JSONEncoder().encode(settings)
    let loaded = try JSONDecoder().decode(Settings.self, from: data)
    #expect(loaded.showAccessoryApps)

    // And a file written before the setting existed still loads, with it off.
    let old = try #require(try? JSONDecoder().decode(Settings.self, from: Data("{}".utf8)))
    #expect(!old.showAccessoryApps)
}

// MARK: - Our own windows

/// Measured on macOS 26.6: `AXUIElementCopyAttributeValue` aimed at our own process returns
/// `kAXErrorNotImplemented` (-25208) immediately, and `AXObserverAddNotification` on our own pid is
/// refused the same way. macOS does not let a process inspect itself through Accessibility.
///
/// This is the measurement `WindowService.ownWindowRefs()` exists for, so it is pinned here: if a
/// future macOS started answering, the AppKit path would become redundant rather than wrong — but
/// if this test fails the other way, something has changed that the comments no longer describe.
@MainActor
@Test func accessibilityRefusesToDescribeOurOwnProcess() {
    let me = AXUIElementCreateApplication(WindowService.ownPID)
    AXUIElementSetMessagingTimeout(me, 2)
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(me, kAXWindowsAttribute as CFString, &value)
    #expect(status != .success)
    // Not a timeout — a refusal. The difference matters: a timeout would mark us "not responding".
    #expect(status != .cannotComplete)
}

/// The self path must never be confused with another app's, in either direction.
@MainActor
@Test func ourOwnWindowsAreTaggedWithOurOwnProcess() {
    #expect(WindowService.ownPID == ProcessInfo.processInfo.processIdentifier)
    let refs = WindowService().ownWindowRefs()
    #expect(refs.allSatisfy { $0.pid == WindowService.ownPID })
    // A window with no title of its own still has to be nameable, or its cell has no label.
    #expect(refs.allSatisfy { !$0.title.isEmpty })
    // Titles are what a reference is matched by, so duplicates must be indexed apart.
    #expect(Set(refs.map(\.id)).count == refs.count)
}
