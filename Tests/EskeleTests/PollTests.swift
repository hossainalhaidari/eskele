import Foundation
import Testing
@testable import Eskele

/// Long enough that no timer fires while a test runs, so every run counted here is one the gate
/// asked for rather than one the clock happened to deliver.
private let hour: TimeInterval = 3600

@MainActor
private final class Counter {
    var runs = 0
}

@MainActor
private func poll(
    on gate: PollGate, stretches: Bool = true, counting counter: Counter
) -> Poll {
    Poll(every: hour, tolerance: 1, stretchesInLowPowerMode: stretches, gate: gate) {
        counter.runs += 1
    }
}

@MainActor
@Test func aPollRunsWhileTheBarCanBeSeen() {
    let gate = PollGate(observingSystem: false)
    let counter = Counter()
    let running = poll(on: gate, counting: counter)
    #expect(running.isRunning)
    // Scheduling is not running: the first run is a whole interval away, as with a plain timer.
    #expect(counter.runs == 0)
}

/// The bug: five timers ran for as long as the app did, displays asleep or not.
@MainActor
@Test func displaySleepStopsEveryPollAndWakingRunsEachOnce() {
    let gate = PollGate(observingSystem: false)
    let first = Counter(), second = Counter()
    let a = poll(on: gate, counting: first)
    let b = poll(on: gate, stretches: false, counting: second)

    gate.noteScreens(asleep: true)
    #expect(gate.isPaused)
    #expect(!a.isRunning && !b.isRunning)
    #expect(first.runs == 0 && second.runs == 0)

    // Once each on the way back, so the bar is current by the time anyone looks at it.
    gate.noteScreens(asleep: false)
    #expect(a.isRunning && b.isRunning)
    #expect(first.runs == 1 && second.runs == 1)
}

/// Fast user switching leaves the bar on a console nobody is sitting at.
@MainActor
@Test func switchingUserStopsPollsLikeDisplaySleep() {
    let gate = PollGate(observingSystem: false)
    let counter = Counter()
    let running = poll(on: gate, counting: counter)

    gate.noteSession(active: false)
    #expect(!running.isRunning)

    gate.noteSession(active: true)
    #expect(running.isRunning)
    #expect(counter.runs == 1)
}

/// Either reason is enough to stay stopped, so clearing one of them must not resume.
@MainActor
@Test func wakingTheDisplaysWhileSwitchedAwayDoesNotResume() {
    let gate = PollGate(observingSystem: false)
    let counter = Counter()
    let running = poll(on: gate, counting: counter)

    gate.noteScreens(asleep: true)
    gate.noteSession(active: false)
    gate.noteScreens(asleep: false)
    #expect(gate.isPaused)
    #expect(!running.isRunning)
    #expect(counter.runs == 0)

    gate.noteSession(active: true)
    #expect(running.isRunning)
    #expect(counter.runs == 1)
}

/// Low Power Mode slows the background polls and leaves alone the ones someone is watching as
/// they run. It stops nothing and runs nothing early: the bar is still on screen.
@MainActor
@Test func lowPowerModeStretchesOnlyBackgroundPolls() {
    let gate = PollGate(observingSystem: false)
    let background = Counter(), watched = Counter()
    let slow = poll(on: gate, counting: background)
    let prompt = poll(on: gate, stretches: false, counting: watched)

    gate.noteLowPower(true)
    #expect(slow.currentInterval == hour * PollGate.lowPowerStretch)
    #expect(prompt.currentInterval == hour)
    #expect(slow.isRunning && prompt.isRunning)
    #expect(background.runs == 0 && watched.runs == 0)

    gate.noteLowPower(false)
    #expect(slow.currentInterval == hour)
}

/// A poll that starts while the displays are asleep — the pulse for an app that asks for attention
/// overnight — waits for the wake like the rest.
@MainActor
@Test func aPollStartedWhileAsleepWaitsForTheWake() {
    let gate = PollGate(observingSystem: false)
    gate.noteScreens(asleep: true)
    let counter = Counter()
    let late = poll(on: gate, counting: counter)
    #expect(!late.isRunning)

    gate.noteScreens(asleep: false)
    #expect(late.isRunning)
    #expect(counter.runs == 1)
}

/// A service that switched its poll off must not have it switched back on by the next wake.
@MainActor
@Test func anInvalidatedPollStaysStoppedThroughAWake() {
    let gate = PollGate(observingSystem: false)
    let counter = Counter()
    let stopped = poll(on: gate, counting: counter)
    stopped.invalidate()

    gate.noteScreens(asleep: true)
    gate.noteScreens(asleep: false)
    #expect(!stopped.isRunning)
    #expect(counter.runs == 0)
}

/// The Trash watcher is told through `onChange`, and only about real changes — a repeated notice
/// must not run every poll again.
@MainActor
@Test func onlyARealChangeIsPassedOn() {
    let gate = PollGate(observingSystem: false)
    var changes = 0
    gate.onChange = { changes += 1 }
    let counter = Counter()
    let running = poll(on: gate, counting: counter)

    gate.noteScreens(asleep: false)
    #expect(changes == 0)
    #expect(counter.runs == 0)

    gate.noteScreens(asleep: true)
    gate.noteScreens(asleep: true)
    #expect(changes == 1)

    gate.noteScreens(asleep: false)
    #expect(changes == 2)
    #expect(counter.runs == 1)
    #expect(running.isRunning)
}

/// The gate holds polls weakly, so a service that lets go of its poll has stopped it — nothing is
/// left firing into an owner that has gone.
@MainActor
@Test func aPollNobodyHoldsIsGone() {
    let gate = PollGate(observingSystem: false)
    let counter = Counter()
    _ = poll(on: gate, counting: counter)

    gate.noteScreens(asleep: true)
    gate.noteScreens(asleep: false)
    #expect(counter.runs == 0)
}
