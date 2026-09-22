import AppKit
import Testing
@testable import Eskele

/// The machine this was measured on: a 1470×956 display, whose menu bar is 33pt and whose Dock
/// reservation takes another 49pt.
private let display = CGSize(width: 1470, height: 956)

/// A full-screen window gives up the menu bar's strip and nothing else.
@Test func aFullScreenWindowCountsAsDisplaySized() {
    #expect(SpaceWindowService.isDisplaySized(width: 1470, height: 923, displays: [display]))
    #expect(SpaceWindowService.isDisplaySized(width: 1470, height: 956, displays: [display]))
}

/// The measurement that makes the rule usable: a merely zoomed window stops short of the Dock as
/// well, which puts it clearly out of range. If these two overlapped there would be no rule.
@Test func aZoomedWindowDoesNot() {
    #expect(!SpaceWindowService.isDisplaySized(width: 1470, height: 874, displays: [display]))
    #expect(!SpaceWindowService.isDisplaySized(width: 1470, height: 875, displays: [display]))
}

/// The off-Space entries `CGWindowList` reports are mostly ghosts — cached panels and template
/// windows belonging to apps whose real window count is zero. These are the ones measured on this
/// machine, and none of them may be mistaken for a window.
@Test func theWindowServersGhostWindowsAreRejected() {
    let ghosts: [(CGFloat, CGFloat)] = [(500, 500), (800, 600), (420, 632), (64, 64), (1470, 33)]
    for (width, height) in ghosts {
        #expect(!SpaceWindowService.isDisplaySized(width: width, height: height, displays: [display]))
    }
}

@Test func aWindowNarrowerThanTheDisplayIsNotFullScreen() {
    #expect(!SpaceWindowService.isDisplaySized(width: 1400, height: 956, displays: [display]))
}

/// A floor on its own is not enough: on a two-display setup anything oversized on the large screen
/// would otherwise be read as full-screen on the small one.
@Test func aWindowLargerThanADisplayIsNotFullScreenOnIt() {
    let external = CGSize(width: 2560, height: 1440)
    #expect(!SpaceWindowService.isDisplaySized(width: 1800, height: 1000, displays: [display, external]))
    #expect(!SpaceWindowService.isDisplaySized(width: 1470, height: 1400, displays: [display]))
}

@Test func anySingleDisplayCanMatch() {
    let external = CGSize(width: 2560, height: 1440)
    #expect(SpaceWindowService.isDisplaySized(width: 2560, height: 1415, displays: [display, external]))
    #expect(SpaceWindowService.isDisplaySized(width: 1470, height: 923, displays: [display, external]))
}

@Test func nothingMatchesWithoutADisplay() {
    #expect(!SpaceWindowService.isDisplaySized(width: 1470, height: 923, displays: []))
}

/// A real scan of this machine. It must not invent windows for apps that have none — the whole
/// reason `CGWindowList` was rejected for counting in the first place.
@MainActor
@Test func aLiveScanOnlyEverReportsPlausibleCounts() {
    let counts = SpaceWindowService.scan(
        displays: NSScreen.screens.map(\.frame.size),
        excluding: ProcessInfo.processInfo.processIdentifier)
    #expect(counts.values.allSatisfy { $0 > 0 && $0 < 32 })
    #expect(!counts.keys.contains(ProcessInfo.processInfo.processIdentifier))
}

// MARK: - "This display is in full screen" is not "this app has a full-screen window"

private func window(fullScreen: Bool, offSpace: Bool) -> AppWindow {
    AppWindow(
        element: AXUIElementCreateApplication(0),
        title: "w",
        subrole: kAXStandardWindowSubrole as String,
        isMinimized: false,
        isFullScreen: fullScreen,
        isOffSpace: offSpace)
}

/// The regression this exists to stop: an app holding a full-screen window on a Space nobody is
/// looking at made the bar believe it was in full screen on the ordinary desktop — which, under
/// "Reveal on Hover", auto-hid a bar whose auto-hide setting was off.
@Test func aFullScreenWindowOnAnotherSpaceIsNotAFullScreenSpace() {
    #expect(!window(fullScreen: true, offSpace: true).showsActiveSpaceFullScreen)
}

@Test func aFullScreenWindowOnThisSpaceIs() {
    #expect(window(fullScreen: true, offSpace: false).showsActiveSpaceFullScreen)
}

@Test func anOrdinaryWindowNeverCountsEitherWay() {
    #expect(!window(fullScreen: false, offSpace: false).showsActiveSpaceFullScreen)
    #expect(!window(fullScreen: false, offSpace: true).showsActiveSpaceFullScreen)
}

/// Windows come from `AXWindows` unless something had to go and find them, so on-Space is the
/// default and off-Space is the thing that must be asked for explicitly.
@Test func windowsAreOnThisSpaceUnlessSaidOtherwise() {
    let plain = AppWindow(
        element: AXUIElementCreateApplication(0), title: "w",
        subrole: kAXStandardWindowSubrole as String, isMinimized: false, isFullScreen: true)
    #expect(!plain.isOffSpace)
    #expect(plain.showsActiveSpaceFullScreen)
}

// MARK: - The two features must not read each other's signal

private func menuProxy() -> AppWindow {
    AppWindow(
        element: AXUIElementCreateApplication(0),
        title: "SteamLibrary.md — filedeck",
        subrole: kAXStandardWindowSubrole as String,
        isMinimized: false,
        isFullScreen: false,
        isMenuProxy: true,
        isOffSpace: true)
}

/// The conflict in one assertion. A window recovered from the Window menu has to be *in* the list
/// for its button to work, and has to stay *out* of the full-screen verdict or an ordinary desktop
/// reads as full screen. Off-Space is what separates the two.
@Test func aWindowRecoveredFromTheMenuIsShownButNeverCountsAsAFullScreenSpace() {
    let proxy = menuProxy()
    #expect(proxy.isListable)
    #expect(proxy.isOffSpace)
    #expect(!proxy.showsActiveSpaceFullScreen)
}

/// Even marked full-screen — as a cached element legitimately is — an off-Space window says
/// nothing about the Space we are on.
@Test func aCachedFullScreenElementIsStillNotAFullScreenSpace() {
    let cached = AppWindow(
        element: AXUIElementCreateApplication(0),
        title: "somewhere else",
        subrole: kAXStandardWindowSubrole as String,
        isMinimized: false,
        isFullScreen: true,
        isOffSpace: true)
    #expect(cached.isListable)
    #expect(!cached.showsActiveSpaceFullScreen)
}

/// A menu item is pressed rather than raised, and only the proxy may take that path — pressing a
/// real window element would do nothing at all.
@Test func onlyAMenuProxyIsPressed() {
    #expect(menuProxy().isMenuProxy)
    let real = AppWindow(
        element: AXUIElementCreateApplication(0), title: "here",
        subrole: kAXStandardWindowSubrole as String, isMinimized: false, isFullScreen: true)
    #expect(!real.isMenuProxy)
    #expect(!real.isOffSpace)
}
