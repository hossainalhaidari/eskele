import Testing
@testable import Eskele

private func decide(running: Bool = true, active: Bool = false, windows: Int? = nil)
    -> ActivationPolicy.Decision {
    ActivationPolicy.decide(isRunning: running, isActive: active, visibleWindows: windows)
}

@Test func anAppThatIsNotRunningLaunches() {
    #expect(decide(running: false) == .launch)
    #expect(decide(running: false, active: false, windows: 0) == .launch)
}

@Test func anAppThatIsNotFrontmostIsBroughtForward() {
    #expect(decide(active: false, windows: 3) == .reopen)
}

/// The bug: an app that is running with nothing on screen. `activate()` moves the menu bar and
/// opens no window, and hiding it is invisible — either way the click looks dead. Both directions
/// have to reach the reopen event instead.
@Test func aRunningAppWithNoWindowsAlwaysReopens() {
    #expect(decide(active: false, windows: 0) == .reopen)
    #expect(decide(active: true, windows: 0) == .reopen)
}

/// All windows minimised is the same situation from the user's point of view: nothing is on screen.
@Test func anAppWhoseWindowsAreAllMinimisedReopens() {
    // The caller counts only un-minimised windows, so "all minimised" arrives here as zero.
    #expect(decide(active: true, windows: 0) == .reopen)
}

@Test func theFrontmostAppWithWindowsStillCyclesOrHides() {
    #expect(decide(active: true, windows: 1) == .cycleOrHide)
    #expect(decide(active: true, windows: 4) == .cycleOrHide)
}

/// Without Accessibility every window count is zero. Reading that as "nothing open" would turn
/// click-to-hide into click-to-reopen for everyone who has not granted the permission, so an
/// unknown count keeps the behaviour they already have.
@Test func anUnknownWindowCountChangesNothing() {
    #expect(decide(active: true, windows: nil) == .cycleOrHide)
    #expect(decide(active: false, windows: nil) == .reopen)
}
