import AppKit

/// What each progress source actually answers, next to what it would need to answer.
///
/// `--diagnose` explains permissions in the abstract; this runs the real thing. A progress bar that
/// does not appear has four indistinguishable causes from the outside — the player is not running,
/// it is not one Eskele knows, its Automation consent was never given, or it is playing something
/// with no duration — and the difference between them is the difference between a bug and a setting.
@MainActor
enum ProgressDiagnostics {
    static func report(persistence: Persistence, settings: Settings) -> String {
        var report = """
            Eskele — progress sources

            settings
              show progress:  \(settings.showProgress ? "on" : "OFF — no bar is drawn from any source")
              media progress: \(settings.mediaProgress ? "on" : "OFF — no player is asked")

            media players
            """

        for player in MediaPlayer.known {
            report += "\n  \(player.bundleID)\n"
            let installed = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: player.bundleID) != nil
            let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: player.bundleID).first

            guard installed else {
                report += "    not installed\n"
                continue
            }
            guard let app else {
                report += "    installed, not running — a player that is not running is not asked\n"
                continue
            }
            report += "    running as \(app.localizedName ?? "?"), pid \(app.processIdentifier)\n"
            report += "    automation: \(PermissionsService.automationStatus(bundleID: player.bundleID).summary)\n"

            let result = run(player.script)
            report += "    script exit \(result.status)\n"
            report += "    stdout: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines).debugDescription)\n"
            if !result.error.isEmpty {
                report += "    stderr: \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            }

            guard result.status == 0, let position = player.parse(result.output, now: Date()) else {
                report += "    → no bar. \(explain(result))\n"
                continue
            }
            guard let progress = position.report(at: Date()) else {
                report += "    → no bar: the track reports no duration, so there is no end to draw to\n"
                continue
            }
            report += "    → \(Int(progress.fraction * 100))%  \(progress.detail ?? "")"
            report += position.isPlaying ? "  (playing)\n" : "  (paused)\n"
        }

        let configuration = persistence.loadProgressConfiguration()
        report += "\ncommands (\(persistence.progressURL.path))\n"
        if configuration.sources.isEmpty {
            report += "  none configured\n"
        }
        for source in configuration.sources {
            report += "  \(source.bundleID) → \(ProgressService.key(for: source.bundleID))"
            report += source.isEnabled ? "  every \(Int(source.period))s\n" : "  DISABLED\n"
            guard source.isEnabled else { continue }
            let result = run(shell: source.command)
            let fraction = ProgressReport.fraction(fromCommandOutput: result.output)
            report += "    exit \(result.status), stdout \(result.output.trimmingCharacters(in: .whitespacesAndNewlines).debugDescription)\n"
            report += fraction.map { "    → \(Int($0 * 100))%\n" }
                ?? "    → no bar: no number in the output\n"
        }

        report += """

            file operations
              Watched folders are the folder cells on the bar, so pin a folder to watch it.
              A file operation is reported for the folder it lands in, never for the app doing it:
              macOS publishes the file and the fraction but nothing that names the publisher.

            """
        return report
    }

    /// The common failures, in the words of what to do about them.
    private static func explain(_ result: Result) -> String {
        let error = result.error.lowercased()
        if error.contains("not allowed") || error.contains("-1743") {
            return "Automation was refused. System Settings ▸ Privacy & Security ▸ Automation."
        }
        if error.contains("-600") || error.contains("isn’t running") || error.contains("not running") {
            return "the player quit between being listed and being asked"
        }
        if result.output.hasPrefix("stopped") {
            return "the player is stopped — nothing is loaded to be part-way through"
        }
        return result.error.isEmpty ? "the reply was not the expected state|position|duration"
            : result.error.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Result {
        var status: Int32
        var output: String
        var error: String
    }

    private static func run(_ script: String) -> Result {
        run("/usr/bin/osascript", ["-e", script])
    }

    private static func run(shell command: String) -> Result {
        run("/bin/sh", ["-c", command])
    }

    private static func run(_ executable: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }
        let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: output, error: errors)
    }
}
