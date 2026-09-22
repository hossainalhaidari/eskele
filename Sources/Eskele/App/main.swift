import AppKit
import DockPrefsKit

/// Rescue path, documented in the README: `Eskele --restore-dock` puts the system Dock back without
/// launching the UI, so a user can recover even after deleting the app.
if CommandLine.arguments.contains("--restore-dock") {
    let support = SupportDirectory.url.appendingPathComponent("dock-backup.json")

    let suppressor = DockSuppressor(backups: FileBackupStore(url: support))
    if suppressor.restore() {
        print("Restored your Dock preferences from the backup.")
    } else {
        // No usable backup — un-hide unconditionally rather than leaving the user stuck.
        let store = CFPreferencesStore()
        store.setBool(false, forKey: DockPrefKey.autohide)
        store.setDouble(nil, forKey: DockPrefKey.autohideDelay)
        store.setDouble(nil, forKey: DockPrefKey.autohideTimeModifier)
        store.synchronize()
        DockSuppressor.terminateDockProcess()
        print("No backup found; reset the Dock to visible with default timings.")
    }
    exit(0)
}

if CommandLine.arguments.contains("--version") {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    let build = info?["CFBundleVersion"] as? String ?? "0"
    print("Eskele \(short) (\(build))")
    exit(0)
}

/// Reports why a permission-dependent feature is or is not working.
///
/// Permission problems on macOS are close to un-debuggable from the UI alone, so this is a
/// first-class flag rather than a hack.
if CommandLine.arguments.contains("--diagnose") {
    let info = Bundle.main.infoDictionary
    let requirement = Diagnostics.designatedRequirement()
    let trusted = AXIsProcessTrusted()

    var report = """
        Eskele \(info?["CFBundleShortVersionString"] as? String ?? "?")
          bundle:        \(Bundle.main.bundlePath)
          identifier:    \(Bundle.main.bundleIdentifier ?? "none")
          signed as:     \(Diagnostics.signingSummary(requirement: requirement))
          accessibility: \(trusted ? "granted" : "NOT granted")
             └ needed for: window lists, full-screen detection, window counts
          automation:    \(PermissionsService.automationStatus().summary)
             └ needed for: emptying the Trash
          power events:  \(PermissionsService.automationStatus(bundleID: "com.apple.loginwindow").summary)
             └ needed for: Sleep, Log Out, Restart and Shut Down in the Apps Menu
          screen rec.:   \(PermissionsService.screenRecordingStatus.summary)
             └ needed for: window previews on hover
          login item:    \(LoginItemService.isEnabled ? "enabled" : "disabled")

        """

    if requirement.contains("cdhash") {
        report += """
              ⚠︎  Ad-hoc signature: macOS will forget every permission on the next rebuild.
                 See https://hossainalhaidari.github.io/eskele/docs/permissions/

            """
    }

    // TCC attributes a permission check to the *responsible* process, which for anything started
    // from a shell is the terminal rather than us. Measured: this same binary reports false when
    // exec'd from a shell and true when launched through LaunchServices. There is no reliable way
    // to tell which happened from inside the process, so rather than guess — and risk sending
    // someone off to re-grant a permission they already have — say so whenever the answer is no.
    if !trusted {
        report += """
              Either accessibility has not been granted, or this process was started from a shell,
              in which case macOS reports the *terminal's* permissions rather than Eskele's.

              For Eskele's own state, open Settings ▸ General in the app, or run:
                open -n \(Bundle.main.bundlePath) --args --diagnose
                cat \(Diagnostics.reportPath)

              To grant: System Settings ▸ Privacy & Security ▸ Accessibility. If Eskele is already
              listed, remove it and add it again — a re-signed build is a different app to macOS.

            """
    }

    print(report, terminator: "")
    // Written as well as printed: when launched through LaunchServices — the only way to see
    // Eskele's own permissions — there is no terminal to print to.
    Diagnostics.writeReport(report)
    exit(0)
}

/// Dumps what Accessibility actually reports about every running app's windows.
///
/// The features that depend on AX — window buttons, full-screen detection, the attention highlight —
/// are the ones whose bugs are invisible from the outside: a window that is silently missing from a
/// list looks exactly like a window that does not exist. This prints the raw material those features
/// are built on, so a report of "it does not work" can be answered with what AX said.
///
/// Must be run through LaunchServices to mean anything — a process started from a shell reports the
/// terminal's permissions, not Eskele's:
///
///     open -n <Eskele.app> --args --diagnose-windows
if CommandLine.arguments.contains("--diagnose-windows") {
    let report = WindowDiagnostics.report(service: WindowService())
    print(report, terminator: "")
    Diagnostics.writeReport(report, to: Diagnostics.windowReportPath)
    exit(0)
}

/// What each progress source answers when it is actually asked.
///
/// Like `--diagnose-windows`, this must be run through LaunchServices to mean anything: TCC
/// attributes an Apple event to the *responsible* process, which for anything started from a shell
/// is the terminal rather than Eskele — so a script run from a terminal can succeed while the same
/// script from the bar is refused, and vice versa.
///
///     open -n <Eskele.app> --args --diagnose-progress
if CommandLine.arguments.contains("--diagnose-progress") {
    let persistence = Persistence()
    let report = ProgressDiagnostics.report(
        persistence: persistence, settings: persistence.loadSettings())
    print(report, terminator: "")
    Diagnostics.writeReport(report, to: Diagnostics.progressReportPath)
    exit(0)
}

/// What the Dock's own tiles say, next to what the bar makes of them.
///
/// Like `--diagnose-windows`, this must be run through LaunchServices to mean anything: a process
/// started from a shell reports the terminal's Accessibility permission rather than Eskele's, and
/// without that permission the Dock's tiles read as empty.
///
///     open -n <Eskele.app> --args --diagnose-badges
if CommandLine.arguments.contains("--diagnose-badges") {
    let persistence = Persistence()
    let report = BadgeDiagnostics.report(
        persistence: persistence, settings: persistence.loadSettings())
    print(report, terminator: "")
    Diagnostics.writeReport(report, to: Diagnostics.badgeReportPath)
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Agent: no Dock tile of our own, no menu bar, never steals focus.
application.setActivationPolicy(.accessory)
application.run()
