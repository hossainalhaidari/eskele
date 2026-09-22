import AppKit

/// One user-configured badge, from `badges.json`.
struct BadgeSource: Codable, Equatable, Sendable {
    /// The app the number belongs to, or `"trash"` for the Trash cell.
    var bundleID: String
    /// A shell command whose output is read as a number. Empty output, or output with no digits in
    /// it, means "no badge" rather than zero.
    var command: String
    /// Seconds between runs. Clamped to something sane, because this shells out.
    var interval: Double?
    var enabled: Bool?

    var isEnabled: Bool { enabled ?? true }
    var period: TimeInterval { min(3600, max(5, interval ?? 30)) }
}

struct BadgeConfiguration: Codable, Equatable, Sendable {
    var sources: [BadgeSource] = []
}

/// Supplies the numbers the bar draws over its icons, from two sources.
///
/// **The real badges.** `DockBadgeReader` reads what macOS is already drawing on the Dock's own
/// tiles, so Mail's unread count arrives without the user configuring anything. That covers the
/// case this feature exists for, and needs only the Accessibility permission the bar already asks
/// for.
///
/// **The commands.** A badge the Dock does not carry — a count from a service with no Dock tile, a
/// number the app itself never badges, or the Trash — still has to come from somewhere, so a
/// command in `badges.json` can supply one. A command also *overrides* the real badge for its app:
/// it is the explicit instruction, and someone who has written one means it. That also means
/// nothing an existing user has configured changes behaviour under them.
///
/// Commands come from a file in Eskele's own support directory and run as you, on your machine —
/// the same trust model as a shell profile. Nothing runs until you put something in that file.
@MainActor
final class BadgeService {
    /// What the bar draws. The Dock's own badges, with any configured command taking precedence
    /// over the tile for the app it names.
    var counts: [String: Int] {
        BadgeService.merged(dock: reader.badges, commands: commandCounts)
    }

    /// A command wins the cell it names, because it is the explicit instruction and someone who
    /// wrote one meant it. A command that yields nothing is absent here rather than zero, so a
    /// recipe that has stopped working — or that reports a different count from the badge and
    /// happens to say zero — falls back to the Dock's own number instead of blanking the cell.
    nonisolated static func merged(dock: [String: Int], commands: [String: Int]) -> [String: Int] {
        dock.merging(commands) { _, configured in configured }
    }

    /// Whether the Dock's own tiles are read at all. Off while the bar is not drawing badges.
    var readsDockBadges: Bool {
        get { reader.isEnabled }
        set { reader.isEnabled = newValue }
    }

    /// Latest number per bundle ID from a configured command. Absent means "no badge".
    private(set) var commandCounts: [String: Int] = [:]
    var onChange: (() -> Void)?

    let reader = DockBadgeReader()
    private let persistence: Persistence
    private var configuration = BadgeConfiguration()
    private var lastRun: [String: Date] = [:]
    /// mtime of `badges.json` when we last read it, so an untouched file costs one `stat` a tick
    /// rather than a file read and a JSON decode.
    private var configurationStamp: Double?
    private var inFlight: Set<String> = []
    private var poll: Poll?

    /// How often we look for work. Individual sources have their own, longer, periods.
    private static let tick: TimeInterval = 5
    /// A command that has not answered by now is not going to be useful.
    nonisolated private static let commandTimeout: TimeInterval = 10

    init(persistence: Persistence) {
        self.persistence = persistence
        reloadConfiguration(force: true)
        reader.onChange = { [weak self] in self?.onChange?() }

        poll = Poll(every: BadgeService.tick, tolerance: 1) { [weak self] in self?.tick() }
        tick()
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        reader.stop()
    }

    var hasSources: Bool { configuration.sources.contains(where: \.isEnabled) }

    func reloadConfiguration(force: Bool = false) {
        var info = stat()
        let stamp: Double? = stat(persistence.badgesURL.path, &info) == 0
            ? Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
            : nil
        guard force || stamp != configurationStamp else { return }
        configurationStamp = stamp

        let next = persistence.loadBadgeConfiguration()
        guard next != configuration else { return }
        configuration = next
        // Drop numbers for sources that have gone away, so removing one clears its badge — and,
        // for an app the Dock badges itself, hands the cell back to the real number.
        let known = Set(next.sources.filter(\.isEnabled).map(\.bundleID))
        commandCounts = commandCounts.filter { known.contains($0.key) }
        lastRun = lastRun.filter { known.contains($0.key) }
        onChange?()
    }

    private func tick() {
        reloadConfiguration()
        let now = Date()
        for source in configuration.sources where source.isEnabled {
            guard !inFlight.contains(source.bundleID) else { continue }
            if let last = lastRun[source.bundleID], now.timeIntervalSince(last) < source.period { continue }
            run(source)
        }
    }

    private func run(_ source: BadgeSource) {
        inFlight.insert(source.bundleID)
        lastRun[source.bundleID] = Date()
        let command = source.command
        let id = source.bundleID

        DispatchQueue.global(qos: .utility).async {
            let value = BadgeService.execute(command, timeout: BadgeService.commandTimeout)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // A source removed while its command was running must not resurrect its badge.
                    guard self.inFlight.remove(id) != nil else { return }
                    self.apply(value, for: id)
                }
            }
        }
    }

    private func apply(_ value: Int?, for bundleID: String) {
        let normalised = (value ?? 0) > 0 ? value : nil
        guard commandCounts[bundleID] != normalised else { return }
        if let normalised {
            commandCounts[bundleID] = normalised
        } else {
            commandCounts.removeValue(forKey: bundleID)
        }
        onChange?()
    }

    /// Runs one command and reads a number out of its output.
    ///
    /// Off the main thread, with a watchdog: an `osascript` that raises an Automation prompt can sit
    /// there indefinitely, and the bar must not.
    nonisolated private static func execute(_ command: String, timeout: TimeInterval) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            NSLog("Eskele: badge command failed to start — \(error.localizedDescription)")
            return nil
        }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return firstNumber(in: String(decoding: data, as: UTF8.self))
    }

    /// The first run of digits in the output, so `"12"`, `"12 unread"` and a chatty script that ends
    /// with a number all work.
    nonisolated static func firstNumber(in output: String) -> Int? {
        var digits = ""
        for character in output {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        return Int(digits)
    }
}
