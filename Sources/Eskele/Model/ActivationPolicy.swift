import Foundation

/// What a click on an app should do.
///
/// Pure, because the matrix is bigger than it looks — running or not, frontmost or not, hidden,
/// windowless, all-minimised — and two of its cells used to do nothing observable at all.
enum ActivationPolicy {
    enum Decision: Equatable {
        /// Not running: start it.
        case launch
        /// Running, but there is nothing on screen to bring forward. Ask LaunchServices to open it
        /// anyway, which sends the reopen event the Dock sends — that is what makes an app with no
        /// windows produce one.
        case reopen
        /// Running and in front of you, with windows: step to the next one, or hide it if there is
        /// only the one.
        case cycleOrHide
    }

    /// - Parameter visibleWindows: windows that are neither closed nor minimised, or `nil` when we
    ///   have no way to know. Without Accessibility every count is zero, and "zero" must not be read
    ///   as "this app has nothing open" — so `nil` keeps the behaviour that permission-free users
    ///   have always had.
    static func decide(isRunning: Bool, isActive: Bool, visibleWindows: Int?) -> Decision {
        guard isRunning else { return .launch }
        // Not frontmost covers hidden apps and all-minimised ones too: both need the reopen, and
        // `NSRunningApplication.activate()` gives neither of them a window.
        guard isActive else { return .reopen }
        // Frontmost with nothing on screen. Hiding it would be invisible, which is the "I clicked
        // it and nothing happened" case.
        if visibleWindows == 0 { return .reopen }
        return .cycleOrHide
    }
}
