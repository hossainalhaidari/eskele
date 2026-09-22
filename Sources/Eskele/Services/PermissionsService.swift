import AppKit
import ApplicationServices
import CoreGraphics
import CoreServices

/// Status of the optional permissions Eskele can use. None is needed for the bar itself.
@MainActor
enum PermissionsService {
    enum Status: Equatable {
        case granted
        case denied
        case notDetermined
        case unavailable

        var summary: String {
            switch self {
            case .granted: String(localized: "Granted", comment: "Permission status")
            case .denied: String(localized: "Denied", comment: "Permission status")
            case .notDetermined: String(
                localized: "Not requested yet",
                comment: "Permission status: the system has not been asked, so nothing is decided")
            case .unavailable: String(
                localized: "Unavailable",
                comment: "Permission status: this build cannot ask for the permission at all")
            }
        }
    }

    /// Checked *without* prompting, so opening Preferences never raises a consent dialog.
    static func automationStatus(bundleID: String = "com.apple.finder") -> Status {
        var address = AEAddressDesc()
        var identifier = Array(bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, &identifier, identifier.count, &address) == noErr else {
            return .unavailable
        }
        defer { AEDisposeDesc(&address) }

        switch AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        default: return .unavailable
        }
    }

    static var accessibilityStatus: Status {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Preflighted rather than requested, so merely opening Preferences never raises the dialog.
    ///
    /// macOS reports no "not yet asked" state for this one — before the first request it answers
    /// exactly as it does after a refusal — so an ungranted permission is reported as denied rather
    /// than guessed at.
    static var screenRecordingStatus: Status {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Raises the system prompt, once. After the user has answered, macOS never asks again and this
    /// returns false forever; the settings pane is the only way back.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
