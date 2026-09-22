import CoreServices
import Foundation

/// The things a Start menu offers at the bottom.
///
/// Each is an Apple event to `loginwindow`, which is how every launcher has done this since the
/// classic Mac OS: there is no Cocoa API for any of them, and the shell equivalents need root.
/// Sending one raises the same Automation prompt that emptying the Trash does, once.
enum PowerAction: String, CaseIterable, Equatable, Sendable {
    case sleep
    case logOut
    case restart
    case shutDown

    var title: String {
        switch self {
        // The three that end your session name themselves with an ellipsis, because they ask first.
        case .sleep: String(localized: "Sleep", comment: "Power action")
        case .logOut: String(localized: "Log Out…", comment: "Power action that asks first")
        case .restart: String(localized: "Restart…", comment: "Power action that asks first")
        case .shutDown: String(localized: "Shut Down…", comment: "Power action that asks first")
        }
    }

    /// For matching what the user types: "restart" should find Restart without the ellipsis getting
    /// in the way.
    var searchName: String {
        switch self {
        case .sleep: String(localized: "Sleep", comment: "Power action")
        case .logOut: String(localized: "Log Out", comment: "Power action, without the ellipsis, for search")
        case .restart: String(localized: "Restart", comment: "Power action, without the ellipsis, for search")
        case .shutDown: String(
            localized: "Shut Down", comment: "Power action, without the ellipsis, for search")
        }
    }

    var symbolName: String {
        switch self {
        case .sleep: "moon.fill"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        }
    }

    /// Whether to ask before doing it.
    ///
    /// Sleep is a keystroke away from being undone. The other three end the session and can lose
    /// work, and a launcher you drive by typing is exactly where a mistyped Return lands on the row
    /// below the one you meant.
    var needsConfirmation: Bool { self != .sleep }

    var confirmationTitle: String {
        switch self {
        case .sleep: ""
        case .logOut: String(localized: "Log out of your account?", comment: "Confirmation alert title")
        case .restart: String(localized: "Restart this Mac?", comment: "Confirmation alert title")
        case .shutDown: String(localized: "Shut down this Mac?", comment: "Confirmation alert title")
        }
    }

    var confirmationDetail: String {
        String(
            localized: "Applications will be asked to quit, and anything unsaved may be lost.",
            comment: "Confirmation alert body, shared by Log Out, Restart and Shut Down")
    }

    /// The four-character Apple event `loginwindow` answers to.
    var eventID: AEEventID {
        switch self {
        case .sleep: AEEventID(kAESleep)
        case .logOut: AEEventID(kAELogOut)
        case .restart: AEEventID(kAERestart)
        case .shutDown: AEEventID(kAEShutDown)
        }
    }
}
