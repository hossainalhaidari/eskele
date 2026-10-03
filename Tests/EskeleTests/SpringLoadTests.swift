import Foundation
import Testing
@testable import Eskele

// MARK: - When it springs

/// Plays a drag over the bar: a string is the drag arriving on that cell, nil a gap, and `fire:` a
/// cell's delay running out. Returns what each step answered — whether `hover` started a delay,
/// and whether `fire` opened the cell. `#expect` cannot wrap a mutating call, hence the script.
private enum Step { case hover(String?), fire(String), reset }

private func play(_ steps: [Step], on spring: inout SpringLoad) -> [Bool] {
    steps.map { step in
        switch step {
        case .hover(let id): return spring.hover(id)
        case .fire(let id): return spring.fire(id)
        case .reset:
            spring.reset()
            return false
        }
    }
}

private func play(_ steps: [Step]) -> [Bool] {
    var spring = SpringLoad()
    return play(steps, on: &spring)
}

@Test func arrivingOnACellStartsTheDelay() {
    #expect(play([.hover("app:com.apple.mail"), .fire("app:com.apple.mail")]) == [true, true])
}

/// A drag that wobbles inside one cell must not keep restarting the delay, or a slightly unsteady
/// hand would never get the cell to open.
@Test func movingWithinTheSameCellDoesNotRestartIt() {
    #expect(play([.hover("folder:/tmp"), .hover("folder:/tmp"), .fire("folder:/tmp")])
        == [true, false, true])
}

/// The timer for a cell the drag has already left finds a different target and does nothing.
@Test func aDelayForACellTheDragHasLeftDoesNothing() {
    #expect(play([
        .hover("app:com.apple.mail"), .hover("app:com.apple.Safari"),
        .fire("app:com.apple.mail"), .fire("app:com.apple.Safari"),
    ]) == [true, true, false, true])
}

@Test func aGapCancelsAndReturningStartsAgain() {
    #expect(play([
        .hover("folder:/tmp"), .hover(nil), .fire("folder:/tmp"),
        .hover("folder:/tmp"), .fire("folder:/tmp"),
    ]) == [true, false, false, true, true])
}

/// Once per visit: resting on a cell after it opened must not keep pulling it back in front of the
/// window the drag is heading for. Leaving and coming back is a new visit.
@Test func aCellSpringsOncePerVisit() {
    #expect(play([
        .hover("app:com.apple.mail"), .fire("app:com.apple.mail"),
        .hover("app:com.apple.mail"), .fire("app:com.apple.mail"),
        .hover(nil), .hover("app:com.apple.mail"), .fire("app:com.apple.mail"),
    ]) == [true, true, false, false, false, true, true])
}

@Test func endingTheDragForgetsEverything() {
    var spring = SpringLoad()
    let answers = play([.hover("folder:/tmp"), .reset, .fire("folder:/tmp")], on: &spring)
    #expect(answers == [true, false, false])
    #expect(spring == SpringLoad())
}

// MARK: - What springs

@Test func onlyCellsWithSomethingToDragIntoSpring() {
    let mail = AppRef(
        bundleID: "com.apple.mail", url: URL(fileURLWithPath: "/System/Applications/Mail.app"),
        name: "Mail")
    var running = DockItem(kind: .app(mail))
    running.isRunning = true
    #expect(running.springsOpen)
    // Launching an app because a drag passed over it slowly is too heavy an accident; dropping on
    // the cell already launches it with the files.
    #expect(!DockItem(kind: .app(mail)).springsOpen)

    #expect(DockItem(kind: .folder(URL(fileURLWithPath: "/tmp"))).springsOpen)
    #expect(!DockItem(kind: .file(URL(fileURLWithPath: "/tmp/a.txt"))).springsOpen)
    #expect(!DockItem(kind: .trash(isEmpty: true)).springsOpen)
    #expect(!DockItem(kind: .appsMenu).springsOpen)
    #expect(!DockItem(kind: .clock).springsOpen)
    #expect(!DockItem(kind: .separator("x")).springsOpen)
}

// MARK: - The system's delay

@Test func theDelayFollowsTheSystemSetting() {
    // Absent until somebody moves the slider.
    #expect(SpringLoad.delay(enabled: nil, seconds: nil) == 0.5)
    #expect(SpringLoad.delay(enabled: nil, seconds: 1.25) == 1.25)
    #expect(SpringLoad.delay(enabled: true, seconds: 0.75) == 0.75)
}

@Test func switchedOffInTheSystemMeansNever() {
    #expect(SpringLoad.delay(enabled: false, seconds: nil) == nil)
    #expect(SpringLoad.delay(enabled: false, seconds: 0.5) == nil)
}

/// Only reachable by hand-editing the setting, and neither end is any use.
@Test func anOutlandishDelayIsClamped() {
    #expect(SpringLoad.delay(enabled: nil, seconds: 0) == 0.1)
    #expect(SpringLoad.delay(enabled: nil, seconds: 30) == 2)
}
