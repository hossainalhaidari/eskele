import Testing
@testable import Eskele

/// `Settings.onlyMarkAppsWithWindows`: which running apps lose their indicator.
@Suite struct UnmarkedAppsTests {
    private func nothingOpen(
        hidden: Bool = false, frontmost: Bool = false, launching: Bool = false,
        windows: Int, known: Bool = true
    ) -> Bool {
        DockItem.hasNothingOpen(
            isHidden: hidden, isFrontmost: frontmost, isLaunching: launching,
            windows: windows, windowsKnown: known)
    }

    /// Finder with no Finder window, Mail with its viewer closed.
    @Test func anAppWithEveryWindowClosedIsUnmarked() {
        #expect(nothingOpen(windows: 0))
        #expect(!nothingOpen(windows: 1))
    }

    @Test func aHiddenAppIsUnmarkedWhateverItHasOpen() {
        #expect(nothingOpen(hidden: true, windows: 3))
    }

    /// It owns the menu bar, so leaving it unmarked would leave nothing on the bar saying which app
    /// the keyboard is talking to.
    @Test func theAppInFrontIsAlwaysMarked() {
        #expect(!nothingOpen(frontmost: true, windows: 0))
    }

    /// Its window is on the way; unmarking it in between would make the tile flicker.
    @Test func anAppStillStartingIsMarked() {
        #expect(!nothingOpen(launching: true, windows: 0))
    }

    /// Without Accessibility every app reports no windows, which says nothing about the apps.
    @Test func unknownWindowsDoNotReadAsClosed() {
        #expect(!nothingOpen(windows: 0, known: false))
        #expect(nothingOpen(hidden: true, windows: 0, known: false))
    }
}
