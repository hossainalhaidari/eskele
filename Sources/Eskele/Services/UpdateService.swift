import AppKit
import Observation
import Sparkle

/// Sparkle, reduced to what the rest of the app asks of it: a policy to show and change, a check to
/// run, and a version waiting for the user's attention.
///
/// Only a release build updates itself. `Scripts/build-app.sh` leaves `SUFeedURL` out of any build
/// it was not given a version for, so `make run` never offers to replace itself with the published
/// release — which, with Install Automatically on, it would do the next time it quit. A build with
/// no `SUPublicEDKey` could not verify anything it downloaded, so it is treated the same way. In
/// both cases the updater is never started: started, Sparkle would put up an alert telling the user
/// the app is misconfigured.
@Observable
@MainActor
final class UpdateService: NSObject {
    /// Whether this build has a feed to read and a key to check what it finds against.
    let isAvailable: Bool

    /// Sparkle's two switches, read back rather than remembered, so the update window's own
    /// "Automatically download and install updates" box — which sets one without asking us — shows up
    /// in the settings window.
    private(set) var policy: UpdatePolicy = .manual
    /// False while a check or a background download is already under way.
    private(set) var canCheck = false
    private(set) var lastCheck: Date?
    /// A version a scheduled check found and held back rather than showing. See
    /// `standardUserDriverShouldHandleShowingScheduledUpdate`.
    private(set) var waitingVersion: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation?] = []

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        isAvailable = Self.isConfigured(info)
        super.init()
    }

    nonisolated static func isConfigured(_ info: [String: Any]) -> Bool {
        ["SUFeedURL", "SUPublicEDKey"].allSatisfy { key in
            guard let value = info[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// "0.1.0 (1)": the version a user reads, then the build number Sparkle compares. The second is
    /// what tells two copies of the same version apart when someone reports a problem.
    nonisolated static func version(_ info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Separate from `init` so the scheduler's first check waits for the app to have finished
    /// launching, as Sparkle asks.
    func start() {
        guard isAvailable, controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        // Sparkle's default names the app and its version to whoever serves the feed, and URLSession
        // adds the user's preferred languages. The feed needs none of it to answer — the version is
        // compared here, against the appcast — so every copy sends the same two values instead.
        // Sparkle puts both on the appcast, the release notes and the download alike.
        controller.updater.userAgentString = "Sparkle"
        controller.updater.httpHeaders = ["Accept-Language": "*"]
        controller.startUpdater()
        self.controller = controller

        observations = [
            observe(\.automaticallyChecksForUpdates),
            observe(\.automaticallyDownloadsUpdates),
            observe(\.canCheckForUpdates),
        ]
        refresh()
    }

    func setPolicy(_ newPolicy: UpdatePolicy) {
        guard let updater = controller?.updater else { return }
        // Both switches, every time. One left over from an earlier choice would come back when the
        // other changed: Manual then Ask must not start downloading because Automatic once did.
        updater.automaticallyChecksForUpdates = newPolicy.checksAutomatically
        updater.automaticallyDownloadsUpdates = newPolicy.downloadsAutomatically
        refresh()
    }

    /// Checks now, with Sparkle's progress window and answer. If an update is already waiting, this
    /// is also what brings it forward.
    func checkForUpdates() {
        guard let controller else { return }
        // An agent is never the active app on its own; without this the window opens behind
        // whatever the user was working in.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    private func observe<Value>(_ keyPath: KeyPath<SPUUpdater, Value>) -> NSKeyValueObservation? {
        controller?.updater.observe(keyPath) { [weak self] _, _ in
            // Sparkle changes these on the main thread only; the handler just cannot say so.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard let updater = controller?.updater else { return }
        policy = UpdatePolicy(
            checksAutomatically: updater.automaticallyChecksForUpdates,
            downloadsAutomatically: updater.automaticallyDownloadsUpdates)
        canCheck = updater.canCheckForUpdates
        lastCheck = updater.lastUpdateCheckDate
    }
}

extension UpdateService: SPUUpdaterDelegate {
    /// `lastUpdateCheckDate` is not KVO-compliant, so this is where a finished check is heard about.
    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        refresh()
    }

    /// No system profile, whatever the defaults say. Sparkle sends one only when `SUSendProfileInfo`
    /// is on, which nothing in Eskele sets and `SUEnableSystemProfiling` keeps it from asking for —
    /// but a `defaults write` could still switch it on, and an empty list means it then sends nothing.
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }
}

/// Gentle reminders, in Sparkle's terms.
///
/// Eskele is an agent: no Dock tile to bounce, never frontmost unless the user brings it there. A
/// scheduled check that finds something mid-afternoon would open its alert behind whatever the user
/// is doing, where it would sit unseen. So only when Sparkle judges the moment right — just after
/// launch, or once the Mac has been idle — does it show the alert itself. Any other time the version
/// waits in the status menu and the General pane, and choosing it there brings the alert forward.
extension UpdateService: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        waitingVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        waitingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        waitingVersion = nil
    }
}
