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

    /// Removing apps from the bar unmarks too: a pinned app keeps its cell and has to look closed.
    @Test func bothChoicesBeyondMarkingUnmark() {
        #expect(!Settings().onlyMarkAppsWithWindows)
        for choice in [WindowlessApps.unmarked, .hidden] {
            var settings = Settings()
            settings.windowlessApps = choice
            #expect(settings.onlyMarkAppsWithWindows)
        }
    }
}

/// `WindowlessApps.hidden`: which running apps leave the bar.
@Suite struct WindowlessAppsTests {
    private func leaves(
        hidden: Bool = false, launching: Bool = false, windows: Int, known: Bool = true
    ) -> Bool {
        DockItem.isWindowless(
            isHidden: hidden, isLaunching: launching, windows: windows, windowsKnown: known)
    }

    /// Notes after its window's close button: still running, nothing to show.
    @Test func anAppWithEveryWindowClosedLeaves() {
        #expect(leaves(windows: 0))
        #expect(!leaves(windows: 1))
    }

    /// Its cell is the only way back to the windows it is keeping out of sight.
    @Test func aHiddenAppStays() {
        #expect(!leaves(hidden: true, windows: 0))
        #expect(!leaves(hidden: true, windows: 2))
    }

    /// Its window is on the way; dropping it in between would make the cell blink in and out.
    @Test func anAppStillStartingStays() {
        #expect(!leaves(launching: true, windows: 0))
    }

    /// Without Accessibility every app reports no windows; taking that at its word would empty the bar.
    @Test func unknownWindowsDoNotEmptyTheBar() {
        #expect(!leaves(windows: 0, known: false))
    }
}
