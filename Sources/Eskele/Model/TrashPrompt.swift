import Foundation
import TrashKit

/// The wording of the "Empty Trash" confirmation.
///
/// Pure, because what it says turns on something easy to get wrong: whether we actually *know* how
/// many items are in there. Without Full Disk Access the count is inferred from directory metadata
/// (`TrashSnapshot.isExact`), and a confirmation is the one place a guess must not be stated as a
/// fact — "permanently erase the 4 items" has to be true, or the dialog is lying about what it is
/// about to destroy.
///
/// The counted sentence is the one plural in Eskele, so it is the one string that lives in
/// `Localizable.stringsdict` rather than `Localizable.strings`: English needs two forms, Polish
/// three and Arabic six, and a `switch` in Swift can only ever offer the two this language happens
/// to want. Hence the `bundle` parameter — the rule is only applied when a catalogue is actually
/// loaded, and the tests pass the repository's own `en.lproj` so the forms are checked rather than
/// assumed.
enum TrashPrompt {
    /// Finder's own phrasing, which is what a user comparing the two will expect.
    static var detail: String {
        String(
            localized: "You can’t undo this action.",
            comment: "Empty Trash confirmation, under the question. Finder's own wording.")
    }

    static var confirmTitle: String {
        String(localized: "Empty Trash", comment: "Button that empties the Trash")
    }

    static var cancelTitle: String {
        String(localized: "Cancel", comment: "Button that dismisses a confirmation without acting")
    }

    static func message(for snapshot: TrashSnapshot, bundle: Bundle = .main) -> String {
        guard snapshot.isExact else {
            return String(
                localized: "Are you sure you want to permanently erase the items in the Trash?",
                bundle: bundle,
                comment: "Empty Trash confirmation when the number of items could not be counted")
        }
        return String(
            localized: "Are you sure you want to permanently erase the \(snapshot.count) items in the Trash?",
            bundle: bundle,
            comment: "Empty Trash confirmation. Pluralised in Localizable.stringsdict.")
    }
}
