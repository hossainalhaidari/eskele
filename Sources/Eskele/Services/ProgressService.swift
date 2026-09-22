import AppKit

/// One user-configured progress source, from `progress.json`.
struct ProgressCommand: Codable, Equatable, Sendable {
    /// The cell the number belongs to: an application's bundle identifier, or the absolute path of a
    /// folder or file on the bar.
    var bundleID: String
    /// A shell command whose output is read as a fraction — see `ProgressReport.fraction(from:)`.
    /// Output with no number in it means "nothing in progress" rather than zero.
    var command: String
    var interval: Double?
    var enabled: Bool?

    var isEnabled: Bool { enabled ?? true }
    /// Shorter floor than a badge's: a progress bar that only moves every half minute is a
    /// still picture. Still a floor, because this shells out.
    var period: TimeInterval { min(3600, max(2, interval ?? 5)) }
}

struct ProgressConfiguration: Codable, Equatable, Sendable {
    var sources: [ProgressCommand] = []
}

/// Supplies the bars Eskele draws across its cells, from three sources that have nothing in common
/// but their shape.
///
/// **Media players are asked, because nothing tells us.** `MPNowPlayingInfoCenter` publishes *your
/// own* process's now-playing information; there is no public reader for anybody else's. The private
/// route, `MRMediaRemoteGetNowPlayingInfo`, still exports its symbols on macOS 26.6 but has been
/// entitlement-gated since 15.4 and answers an unentitled process with nothing — measured here, it
/// returns a nil info dictionary and then stops calling back at all. What is left is the players'
/// own scripting interfaces, which are public, documented, and exact. They cost an Automation
/// consent per player, so this is off until asked for.
///
/// **Asked rarely, drawn smoothly.** An Apple event into another process is far too expensive to
/// send at the frame rate a progress bar wants. Eskele samples every few seconds and extrapolates
/// between samples — a playing track advances one second per second — resnapping on every sample.
/// See `MediaPosition`.
///
/// **Commands are the catch-all**, exactly as they are for badges: a build, a render, a backup, a
/// long download in something that is not scriptable. Nothing runs until you put something in
/// `progress.json`, and it runs as you, on your machine.
@MainActor
final class ProgressService {
    /// Everything the bar should draw, keyed by `DockItem.progressKey`.
    private(set) var reports: [String: ProgressReport] = [:]
    var onChange: (() -> Void)?

    /// Whether media players are asked at all. Off costs nothing and asks nobody for consent.
    var tracksMedia = false {
        didSet {
            guard tracksMedia != oldValue else { return }
            if !tracksMedia {
                positions.removeAll()
                lastRun.removeAll()
            }
            tick()
        }
    }

    /// Which of the players Eskele knows are running right now. Supplied rather than looked up so
    /// the service has no opinion about where the list of running apps comes from.
    var runningPlayers: (() -> Set<String>)?

    /// Progress for folder cells, from `FileProgressService`. Merged here so the bar has one source
    /// of truth and one notification to listen to.
    var fileReports: [String: ProgressReport] = [:] {
        didSet {
            guard fileReports != oldValue else { return }
            publish()
        }
    }

    private let persistence: Persistence
    private var configuration = ProgressConfiguration()
    private var configurationStamp: Double?
    private var positions: [String: MediaPosition] = [:]
    private var commandFractions: [String: Double] = [:]
    private var lastRun: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private var pollTimer: Poll?
    private var drawTimer: Poll?

    /// How often sources are asked. Individual commands have their own, longer, periods; the media
    /// players are asked on every tick.
    private static let pollInterval: TimeInterval = 4
    /// How often the extrapolated media position is turned back into a bar. A three-minute track
    /// moves 0.5% a second, which on a 27pt cell is a sixth of a point — so this is about keeping
    /// the bar honest rather than about smoothness.
    private static let drawInterval: TimeInterval = 1
    /// A script that has not answered by now is one whose app is wedged, or whose Automation prompt
    /// is sitting unanswered behind another window. `nonisolated` because it is read by the work
    /// that runs off the main thread, which is the only place it is any use.
    nonisolated private static let scriptTimeout: TimeInterval = 5
    /// Below this a redraw changes no pixel anyone can see.
    private static let meaningfulChange = 0.004

    init(persistence: Persistence) {
        self.persistence = persistence
        reloadConfiguration(force: true)

        pollTimer = Poll(every: ProgressService.pollInterval, tolerance: 1) { [weak self] in
            self?.tick()
        }
        tick()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopDrawing()
    }

    var hasCommandSources: Bool { configuration.sources.contains(where: \.isEnabled) }

    // MARK: - Configuration

    func reloadConfiguration(force: Bool = false) {
        var info = stat()
        let stamp: Double? = stat(persistence.progressURL.path, &info) == 0
            ? Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
            : nil
        guard force || stamp != configurationStamp else { return }
        configurationStamp = stamp

        let next = persistence.loadProgressConfiguration()
        guard next != configuration else { return }
        configuration = next
        // Removing a source clears its bar rather than freezing it at whatever it last reported.
        let known = Set(next.sources.filter(\.isEnabled).map(\.bundleID))
        commandFractions = commandFractions.filter { known.contains($0.key) }
        lastRun = lastRun.filter { known.contains($0.key) || MediaPlayer.known(bundleID: $0.key) != nil }
        publish()
    }

    // MARK: - Sampling

    private func tick() {
        reloadConfiguration()
        sampleMedia()
        runCommands()
        publish()
    }

    private func sampleMedia() {
        guard tracksMedia else { return }
        let running = runningPlayers?() ?? []
        // A player that has quit takes its bar with it, rather than leaving the last track it was
        // half way through painted on a tile for the rest of the session.
        for id in Array(positions.keys) where !running.contains(id) {
            positions.removeValue(forKey: id)
        }
        for player in MediaPlayer.known where running.contains(player.bundleID) {
            ask(player)
        }
    }

    private func ask(_ player: MediaPlayer) {
        let id = player.bundleID
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)

        let script = player.script
        DispatchQueue.global(qos: .utility).async {
            let output = ProgressService.runScript(script, timeout: ProgressService.scriptTimeout)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.inFlight.remove(id) != nil, self.tracksMedia else { return }
                    let sample = output.flatMap { player.parse($0, now: Date()) }
                    if self.positions[id] != sample { self.positions[id] = sample }
                    self.syncDrawing()
                    self.publish()
                }
            }
        }
    }

    private func runCommands() {
        let now = Date()
        for source in configuration.sources where source.isEnabled {
            guard !inFlight.contains(source.bundleID) else { continue }
            if let last = lastRun[source.bundleID], now.timeIntervalSince(last) < source.period {
                continue
            }
            run(source)
        }
    }

    private func run(_ source: ProgressCommand) {
        inFlight.insert(source.bundleID)
        lastRun[source.bundleID] = Date()
        let command = source.command
        let id = source.bundleID

        DispatchQueue.global(qos: .utility).async {
            let output = ProgressService.runShell(command, timeout: ProgressService.scriptTimeout)
            let fraction = output.flatMap { ProgressReport.fraction(fromCommandOutput: $0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.inFlight.remove(id) != nil else { return }
                    if let fraction {
                        self.commandFractions[id] = fraction
                    } else {
                        self.commandFractions.removeValue(forKey: id)
                    }
                    self.publish()
                }
            }
        }
    }

    // MARK: - Drawing clock

    /// Runs only while something is actually playing. A paused player holds its position, so there
    /// is nothing to recompute and no reason to wake up for it.
    private func syncDrawing() {
        let wanted = positions.values.contains { $0.isPlaying }
        if wanted, drawTimer == nil {
            drawTimer = Poll(every: ProgressService.drawInterval, tolerance: 0.2) { [weak self] in
                self?.publish()
            }
        } else if !wanted {
            stopDrawing()
        }
    }

    private func stopDrawing() {
        drawTimer?.invalidate()
        drawTimer = nil
    }

    // MARK: - Publishing

    private func publish() {
        let now = Date()
        // The file service knows folders by path and nothing about how a cell is addressed, so the
        // keys are put into the bar's own form here rather than there.
        var next: [String: ProgressReport] = [:]
        for (path, report) in fileReports {
            next[ProgressService.key(for: path)] = report
        }
        for (id, position) in positions {
            guard let report = position.report(at: now) else { continue }
            next[ProgressService.key(for: id)] = report
        }
        // A command wins over the player's own answer for the same cell: it was written by hand for
        // this app, which is a clearer statement of intent than a table shipped in the binary.
        for (id, fraction) in commandFractions {
            next[ProgressService.key(for: id)] = ProgressReport(kind: .custom, fraction: fraction)
        }

        guard changed(from: reports, to: next) else { return }
        reports = next
        onChange?()
    }

    /// A bundle identifier addresses an app; anything starting with a slash addresses the folder or
    /// file at that path. One field rather than two, because a source only ever means one of them
    /// and the leading slash already says which.
    nonisolated static func key(for target: String) -> String {
        target.hasPrefix("/") ? "path:\(target)" : "app:\(target)"
    }

    /// Equality would republish on every extrapolated tick, which is a redraw of every bar on every
    /// display once a second for a bar that has not visibly moved.
    private func changed(from: [String: ProgressReport], to: [String: ProgressReport]) -> Bool {
        guard from.count == to.count else { return true }
        for (key, report) in to {
            guard let old = from[key] else { return true }
            if old.kind != report.kind || old.detail != report.detail { return true }
            if abs(old.fraction - report.fraction) >= ProgressService.meaningfulChange { return true }
        }
        return false
    }

    // MARK: - Running things

    /// Off the main thread, with a watchdog, for the same reason `BadgeService` does it: an
    /// `osascript` that raises an Automation prompt sits there until somebody answers it, and the
    /// bar must not wait.
    nonisolated private static func runScript(_ script: String, timeout: TimeInterval) -> String? {
        run("/usr/bin/osascript", ["-e", script], timeout: timeout)
    }

    nonisolated private static func runShell(_ command: String, timeout: TimeInterval) -> String? {
        run("/bin/sh", ["-c", command], timeout: timeout)
    }

    nonisolated private static func run(
        _ executable: String, _ arguments: [String], timeout: TimeInterval
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
