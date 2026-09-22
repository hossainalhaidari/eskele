import Foundation

/// Restore Defaults, Export and Import — the three ways a whole set of settings arrives at once.
///
/// All three end in an ordinary `AppDelegate.apply`, so nothing downstream can tell a reset from a
/// click on a toggle. What they need that a click never did is two rules: which settings a
/// replacement may not touch (`Settings.adopting`), and which files are not settings at all (`read`).
///
/// An export is exactly what `Persistence` writes to `settings.json`, byte for byte, so an exported
/// file and a copy of `settings.json` are interchangeable in both directions.
enum SettingsFile {
    enum ReadError: Error, Equatable {
        /// Not JSON, or JSON whose top level is not an object.
        case unreadable
        /// An object, but one whose keys are mostly not settings — another of our files, usually.
        case notSettings
    }

    /// Reads a file the way launch reads `settings.json` — key by key, a bad value costing only
    /// itself and a missing one taking its default — but refuses one that is not a settings file.
    ///
    /// The lenient decoder is why the refusal is needed. It makes `Settings` out of any JSON object
    /// at all, so `layout.json` would import as a flawless set of defaults: a reset by another name,
    /// reported as a success. Unknown keys cannot simply be refused either, because a file exported
    /// by a later version is entitled to carry settings this one has never heard of. So the rule is
    /// that *most* of the file's keys must be settings. The case that sizes it is
    /// `dock-backup.json`, which shares exactly one key — `autohide` — with this file, out of seven;
    /// `layout.json`, `badges.json`, `progress.json` and an empty object share none.
    static func read(_ data: Data) throws(ReadError) -> Settings {
        let decoder = JSONDecoder()
        guard let census = try? decoder.decode(KeyCensus.self, from: data) else { throw .unreadable }
        guard census.recognised * 2 > census.total else { throw .notSettings }
        // Cannot fail once the census has read an object: every key is decoded leniently.
        guard let settings = try? decoder.decode(Settings.self, from: data) else { throw .unreadable }
        return settings
    }

    // MARK: - Wording

    /// Offered in the save panel, which adds the extension.
    static var suggestedName: String {
        String(
            localized: "Eskele Settings",
            comment: "Suggested file name for exported settings; the .json extension is added for you")
    }

    static var resetMessage: String {
        String(localized: "Restore the default settings?", comment: "Restore Defaults confirmation")
    }

    /// Says what is kept as well as what is lost, because the answer is not "nothing": a reset that
    /// is about to bring the system Dock back, or wipe the pinned items, would be a different
    /// question from the one being asked.
    static func resetDetail(keepsCustomDesign: Bool) -> String {
        let detail = String(
            localized: """
                The bar’s appearance, contents and behaviour go back to how a new installation has \
                them. The system Dock stays as it is, and so does what you have put on the bar — pinned \
                items, names and icons.
                """,
            comment: "Restore Defaults confirmation, under the question")
        guard keepsCustomDesign else { return detail }
        let custom = String(
            localized: "Your Custom design stays under its tile, one click from coming back.",
            comment: "Restore Defaults confirmation, when there is a Custom design to go back to")
        return "\(detail)\n\n\(custom)"
    }

    static var resetConfirmTitle: String {
        String(localized: "Restore Defaults", comment: "Button that confirms restoring the default settings")
    }

    static var cancelTitle: String {
        String(localized: "Cancel", comment: "Button that dismisses a confirmation without acting")
    }

    /// One message for both errors: to the person choosing a file, damaged and not-ours call for
    /// the same next step.
    static func refusal(filename: String) -> String {
        String(
            localized: "“\(filename)” is not an Eskele settings file.",
            comment: "Import refused. The file name is already quoted.")
    }

    static var refusalDetail: String {
        String(
            localized: """
                Nothing was changed. A settings file is one saved with Export Settings, or a copy of \
                settings.json.
                """,
            comment: "Import refused, under the message")
    }
}

extension Settings {
    /// `incoming`, as it should land on this Mac.
    ///
    /// Three settings describe the Mac rather than the bar, and a replacement leaves them where they
    /// are: whether first launch has asked its question, and the two answers it got about the system
    /// Dock. A reset that turned suppression off would bring the Dock back mid-session; an import
    /// that turned it on would hide the Dock on a Mac whose owner was asked and said no. That
    /// consent was given here, and it has its own tab and its own restore button.
    ///
    /// The Custom design stays unless the file brings one of its own. A reset brings none, so the
    /// layout being reset away from is still one click away under the Custom tile — `apply` stored
    /// it there on the way in, as it does after every change.
    func adopting(_ incoming: Settings) -> Settings {
        var result = incoming
        result.hasCompletedOnboarding = hasCompletedOnboarding
        result.suppressSystemDock = suppressSystemDock
        result.reserveScreenSpace = reserveScreenSpace
        result.customDesign = incoming.customDesign ?? customDesign
        // What launch does for a hand-edited file, and for the same reason: an imported one is a
        // hand-edited file as far as anyone knows.
        if !result.hasSettingsRoute { result.showStatusItem = true }
        return result
    }
}

/// How many of a JSON object's keys are settings, out of how many it has.
private struct KeyCensus: Decodable {
    var total: Int
    var recognised: Int

    init(from decoder: Decoder) throws {
        total = try decoder.container(keyedBy: AnyKey.self).allKeys.count
        // Counted by name, so a present-but-malformed value still marks the file as settings —
        // the leniency launch applies too.
        recognised = try Settings.recognisedKeyCount(in: decoder)
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
