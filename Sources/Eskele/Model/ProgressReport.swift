import Foundation

/// Something a cell is part-way through: a track playing, a file being written, a number a command
/// reported.
///
/// One shape for all three, because the bar draws one thing. Where it comes from only decides how
/// the hover label reads and how often it is refreshed.
struct ProgressReport: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Where a media player is in the current track.
        case media
        /// A file operation landing in a folder the bar shows.
        case file
        /// A number from a command in `progress.json`.
        case custom
    }

    var kind: Kind
    /// 0…1. Clamped on the way in, so nothing downstream has to defend itself against a source that
    /// reports 130%, a negative remainder, or a NaN from dividing by a duration of zero.
    var fraction: Double
    /// What the hover label adds after the cell's own title — "1:23 of 4:05", "Copying big.zip".
    var detail: String?

    init(kind: Kind, fraction: Double, detail: String? = nil) {
        self.kind = kind
        self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        self.detail = detail
    }

    /// Reads a fraction out of a command's output.
    ///
    /// Both conventions are accepted because both are what people will type: anything above 1 is a
    /// percentage, anything from 0 to 1 is a fraction. That makes `1` mean *finished* rather than
    /// one percent, which is the reading that matches "the command said 1 out of 1"; a trailing `%`
    /// settles it explicitly either way.
    ///
    /// No number at all means "no progress", which is how a command switches the bar off — the same
    /// bargain `badges.json` strikes with an empty line.
    static func fraction(fromCommandOutput output: String) -> Double? {
        var digits = ""
        var sawPercent = false
        for character in output {
            if character.isNumber || (character == "." && !digits.contains(".")) {
                digits.append(character)
            } else if !digits.isEmpty {
                sawPercent = character == "%"
                break
            }
        }
        guard let value = Double(digits), value.isFinite, value >= 0 else { return nil }
        let fraction = (sawPercent || value > 1) ? value / 100 : value
        return min(1, max(0, fraction))
    }
}

/// One reading of where a media player is, and the arithmetic that keeps the bar moving between
/// readings.
///
/// Asking a player its position costs an Apple event into another process, so Eskele asks rarely and
/// works out the rest: a playing track advances one second per second, which is the whole model.
/// Every reading resnaps it, so a seek is wrong for at most one polling interval and nothing
/// accumulates drift.
struct MediaPosition: Equatable, Sendable {
    var position: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
    var sampledAt: Date

    /// Never past the end: a track that finishes between polls would otherwise run the bar off the
    /// scale until the next reading arrived.
    func position(at now: Date) -> TimeInterval {
        guard isPlaying else { return position }
        return min(duration, position + max(0, now.timeIntervalSince(sampledAt)))
    }

    /// `nil` for a player that reports no duration — a live stream, or a track that has not loaded.
    /// A bar needs an end to be a bar.
    func report(at now: Date) -> ProgressReport? {
        guard duration > 0, position >= 0 else { return nil }
        let elapsed = position(at: now)
        return ProgressReport(
            kind: .media,
            fraction: elapsed / duration,
            detail: String(
                localized: "\(MediaPosition.clock(elapsed)) of \(MediaPosition.clock(duration))",
                comment: "Track position, e.g. '2:31 of 4:05'. Both values are already formatted."))
    }

    /// `m:ss`, growing to `h:mm:ss` only once there is an hour to show — a three-minute track
    /// written as `0:03:12` reads as a stopwatch rather than as a track.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}

/// A media player Eskele knows how to ask where it is.
///
/// Each one is a bundle identifier and a script. The script's contract is one line of
/// `state|position|duration`, both numbers **whole milliseconds**, and `stopped` for a player with
/// nothing loaded.
///
/// **Milliseconds, and integers, for one hard-won reason.** AppleScript coerces a real to text using
/// the *system's* decimal separator, so a German-locale Mac answers `268,605987548828` where an
/// English one answers `268.605987548828`. `Double(_:)` reads only the second, so on most of Europe
/// every reply was discarded and no bar was ever drawn — with the player running, Automation granted
/// and the script exiting cleanly, which is as invisible as a bug gets. Integers have no separator to
/// disagree about. Each script therefore does its own unit conversion and truncates with `div 1`,
/// which is also why the per-player unit differences — Spotify reports a position in seconds and a
/// duration in milliseconds — live in the scripts rather than in a table over here.
struct MediaPlayer: Equatable, Sendable {
    var bundleID: String
    var script: String

    static let known: [MediaPlayer] = [
        MediaPlayer(bundleID: "com.apple.Music", script: playerScript(app: "Music")),
        // Spotify's `duration` is already in milliseconds; Music's is in seconds.
        MediaPlayer(
            bundleID: "com.spotify.client",
            script: playerScript(app: "Spotify", durationToMilliseconds: 1)),
        MediaPlayer(bundleID: "org.videolan.vlc", script: vlcScript),
    ]

    static func known(bundleID: String) -> MediaPlayer? {
        known.first { $0.bundleID == bundleID }
    }

    /// Music and Spotify share a vocabulary — `player state`, `player position`, and a
    /// `current track` with a duration — so they share a script.
    private static func playerScript(app: String, durationToMilliseconds: Int = 1000) -> String {
        """
        tell application "\(app)"
            set theState to player state
            if theState is stopped then return "stopped||"
            set thePosition to ((player position) * 1000) div 1
            set theDuration to ((duration of current track) * \(durationToMilliseconds)) div 1
            if theState is playing then
                return "playing|" & thePosition & "|" & theDuration
            else
                return "paused|" & thePosition & "|" & theDuration
            end if
        end tell
        """
    }

    /// VLC names the same three things differently, answers `playing` as a plain boolean, and counts
    /// in whole seconds.
    private static let vlcScript = """
        tell application "VLC"
            if not (exists current item) then return "stopped||"
            set thePosition to ((current time) * 1000) div 1
            set theDuration to ((duration of current item) * 1000) div 1
            if playing then
                return "playing|" & thePosition & "|" & theDuration
            else
                return "paused|" & thePosition & "|" & theDuration
            end if
        end tell
        """

    /// Reads one line of `state|position|duration`.
    ///
    /// Anything that is not the shape above is `nil` rather than a guess: an AppleScript error, a
    /// refused Automation prompt and a player that has just quit all arrive here as noise, and none
    /// of them should put a bar on a tile.
    func parse(_ output: String, now: Date) -> MediaPosition? {
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).split(
            separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        let state = fields[0].trimmingCharacters(in: .whitespaces)
        guard state == "playing" || state == "paused" else { return nil }
        guard let position = MediaPlayer.milliseconds(fields[1]),
              let duration = MediaPlayer.milliseconds(fields[2])
        else { return nil }

        return MediaPosition(
            position: position / 1000,
            duration: duration / 1000,
            isPlaying: state == "playing",
            sampledAt: now)
    }

    /// The scripts emit whole milliseconds, so this should only ever see digits — but it reads a
    /// decimal in either convention too, because the alternative to being lenient here was a feature
    /// that silently did nothing outside the English-speaking world.
    static func milliseconds(_ field: some StringProtocol) -> Double? {
        var text = field.trimmingCharacters(in: .whitespaces)
        if text.contains(",") {
            // Both separators means the comma groups thousands; a comma alone means it is the
            // decimal point, which is what most of Europe answers.
            text = text.contains(".")
                ? text.replacingOccurrences(of: ",", with: "")
                : text.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
