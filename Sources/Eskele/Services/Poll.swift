import AppKit

/// Whether polling is worth doing right now, decided once for every poll in the app.
///
/// Everything Eskele polls for — windows, badges, the Trash, the Dock's preferences — exists to be
/// drawn on the bar, and while the displays are asleep, or another user has the console, there is
/// no bar to look at. So every poll stands down then, and runs once on the way back so the bar is
/// current by the time anyone can see it. Event-driven sources — workspace notifications, the AX
/// observer, file-system sources — cost nothing while nothing happens and are left alone.
///
/// System sleep needs nothing of its own: no timer fires while the machine is asleep. What does run
/// is the time around it with the display off, and Power Nap's dark wakes, which wake the machine
/// and leave the display asleep — both of which the display notifications cover.
///
/// Low Power Mode stretches the polls rather than stopping them: the bar is still on screen and
/// still has to be right, just not as promptly.
@MainActor
final class PollGate {
    static let shared = PollGate(observingSystem: true)

    /// How many times longer a poll waits between runs in Low Power Mode.
    static let lowPowerStretch: Double = 2

    /// Nobody can see the bar: every poll is stopped.
    var isPaused: Bool { screensAsleep || sessionInactive }
    private(set) var isLowPower = false

    /// For a poll that is not a `Poll` — the Trash watcher, which lives in a module of its own.
    var onChange: (() -> Void)?

    private var screensAsleep = false
    private var sessionInactive = false
    private let polls = NSHashTable<Poll>.weakObjects()
    private nonisolated(unsafe) var workspaceObservers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var powerObserver: NSObjectProtocol?

    /// - Parameter observingSystem: false for a gate driven by hand, which is what the tests use.
    init(observingSystem: Bool) {
        guard observingSystem else { return }
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        let workspace = NSWorkspace.shared.notificationCenter
        let changes: [(NSNotification.Name, @MainActor (PollGate) -> Void)] = [
            (NSWorkspace.screensDidSleepNotification, { $0.noteScreens(asleep: true) }),
            (NSWorkspace.screensDidWakeNotification, { $0.noteScreens(asleep: false) }),
            // Fast user switching: the bar is on a console nobody is sitting at.
            (NSWorkspace.sessionDidResignActiveNotification, { $0.noteSession(active: false) }),
            (NSWorkspace.sessionDidBecomeActiveNotification, { $0.noteSession(active: true) }),
        ]
        for (name, change) in changes {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { if let self { change(self) } }
            })
        }
        powerObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.noteLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
        }
    }

    deinit {
        let workspace = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { workspace.removeObserver(token) }
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
    }

    func noteScreens(asleep: Bool) { change { $0.screensAsleep = asleep } }
    func noteSession(active: Bool) { change { $0.sessionInactive = !active } }
    func noteLowPower(_ enabled: Bool) { change { $0.isLowPower = enabled } }

    fileprivate func add(_ poll: Poll) { polls.add(poll) }
    fileprivate func remove(_ poll: Poll) { polls.remove(poll) }

    private func change(_ apply: (PollGate) -> Void) {
        let wasPaused = isPaused
        let wasLowPower = isLowPower
        apply(self)
        guard isPaused != wasPaused || isLowPower != wasLowPower else { return }
        let resuming = wasPaused && !isPaused
        // A copy: a poll run on the way back may start or stop others.
        for poll in polls.allObjects { poll.reschedule(runningNow: resuming) }
        onChange?()
    }
}

/// A repeating timer that stops while `PollGate` says nobody can see the bar, and runs slower in
/// Low Power Mode.
@MainActor
final class Poll {
    private let interval: TimeInterval
    private let tolerance: TimeInterval
    private let stretches: Bool
    private let gate: PollGate
    private let action: @MainActor () -> Void
    private nonisolated(unsafe) var timer: Timer?
    private var isInvalidated = false

    /// Scheduled at once, unless the gate is paused — then on the way back.
    ///
    /// - Parameter stretchesInLowPowerMode: false for a poll someone is watching as it happens — a
    ///   held chord, an animation — where slower means visibly broken rather than a little late.
    init(
        every interval: TimeInterval,
        tolerance: TimeInterval,
        stretchesInLowPowerMode: Bool = true,
        gate: PollGate = .shared,
        action: @escaping @MainActor () -> Void
    ) {
        self.interval = interval
        self.tolerance = tolerance
        self.stretches = stretchesInLowPowerMode
        self.gate = gate
        self.action = action
        gate.add(self)
        schedule()
    }

    deinit {
        timer?.invalidate()
    }

    /// Whether a timer is live right now. False while the gate is paused and after `invalidate`.
    var isRunning: Bool { timer != nil }

    /// The time between runs as things stand, stretched in Low Power Mode.
    var currentInterval: TimeInterval { interval * stretch }

    func invalidate() {
        isInvalidated = true
        timer?.invalidate()
        timer = nil
        gate.remove(self)
    }

    fileprivate func reschedule(runningNow: Bool) {
        timer?.invalidate()
        timer = nil
        guard !isInvalidated else { return }
        schedule()
        if runningNow { action() }
    }

    private var stretch: Double { stretches && gate.isLowPower ? PollGate.lowPowerStretch : 1 }

    private func schedule() {
        guard !gate.isPaused else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.action() }
        }
        timer.tolerance = tolerance * stretch
        self.timer = timer
    }
}
