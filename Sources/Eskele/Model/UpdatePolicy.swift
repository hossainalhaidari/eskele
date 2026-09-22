import Foundation

/// How Eskele goes about new versions, as the one choice the settings window offers.
///
/// Sparkle keeps this as two switches — check on a schedule, and download what the check finds —
/// and the second means nothing without the first. Three of the four combinations are distinct
/// behaviours; the fourth, downloading without checking, is the same as never checking, so it reads
/// back as `.manual` rather than as a state the picker cannot show.
///
/// Not part of `Settings`: Sparkle stores both switches in the app's own defaults and its update
/// window changes the download switch itself, so a copy in `settings.json` would be a second record
/// that window never updates. Export and Import leave it alone for the same reason they leave the
/// login item alone: it is about this Mac, not about the bar.
///
/// Out of the box it is `.manual`: `SUEnableAutomaticChecks` is off in `Info.plist`, so Eskele goes
/// online only when the user asks it to.
enum UpdatePolicy: CaseIterable, Hashable {
    /// Download in the background and install when Eskele next quits.
    case automatic
    /// Check once a day and show what was found, with a choice to install it.
    case ask
    /// Only look when the user asks.
    case manual

    init(checksAutomatically: Bool, downloadsAutomatically: Bool) {
        self = switch (checksAutomatically, downloadsAutomatically) {
        case (true, true): .automatic
        case (true, false): .ask
        case (false, _): .manual
        }
    }

    var checksAutomatically: Bool { self != .manual }
    var downloadsAutomatically: Bool { self == .automatic }

    var title: String {
        switch self {
        case .automatic:
            String(localized: "Install Automatically", comment: "Update policy: download and install without asking")
        case .ask:
            String(localized: "Ask Before Installing", comment: "Update policy: check daily, then ask")
        case .manual:
            String(localized: "Only When I Check", comment: "Update policy: never check on a schedule")
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            String(
                localized: """
                    Eskele checks once a day, downloads what it finds in the background, and installs it \
                    the next time it quits — or, if it goes a long time without quitting, offers to \
                    restart.
                    """,
                comment: "Footer under the update policy picker when updates install automatically")
        case .ask:
            String(
                localized: "Eskele checks once a day and asks before downloading anything.",
                comment: "Footer under the update policy picker when updates ask first")
        case .manual:
            String(
                localized: "Eskele never looks for updates on its own. Check Now looks once.",
                comment: "Footer under the update policy picker when checks are manual")
        }
    }
}
