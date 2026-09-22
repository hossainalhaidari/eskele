import AppKit

/// The URL LaunchServices will actually *launch*, as opposed to the one a process happens to be
/// running from.
///
/// `NSRunningApplication.bundleURL` is the bundle a process was started from, and that is not always
/// something macOS recognises as an application. Steam is the reference case: the copy in
/// `/Applications` is a bootstrapper, and the client it updates and then runs lives at
/// `~/Library/Application Support/Steam/Steam.AppBundle/Steam` — a genuine `APPL` bundle, with
/// Steam's bundle identifier, and **no `.app` extension**. macOS answers `isApplication == false`
/// for such a path, so LaunchServices treats it as a document rather than a program and hands it to
/// whatever opens a folder:
///
///     NSWorkspace.shared.openApplication(at: innerSteam, …)   // -> com.apple.finder, error: nil
///
/// Finder, and *no error* — which is why clicking a running Steam opened its folder and nothing was
/// ever logged. Pinning it was worse: `PersistedItem.make(for:)` classifies by the `.app` extension,
/// so the cell was stored as a *folder* and the mistake outlived the session.
///
/// The rule here is therefore: keep the bundle the process is running from when macOS agrees it is
/// an application, and otherwise ask LaunchServices for the installed copy of the same bundle
/// identifier — which is the `/Applications` copy the user thinks they are clicking. When there is
/// no such copy the original URL is returned unchanged, so an app that only ever exists in this
/// shape is no worse off than before.
enum ApplicationURL {
    /// Whether macOS will launch this URL rather than open it.
    static func isApplication(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isApplicationKey]))?.isApplication ?? false
    }

    /// The bundle identifier of the application bundle at `url`, whatever the bundle is called.
    ///
    /// `CFBundlePackageType` is what separates Steam's extension-less client from an ordinary
    /// folder that merely happens to contain a `Contents` directory.
    static func applicationBundleID(at url: URL) -> String? {
        guard let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier,
              bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL"
        else { return nil }
        return id
    }

    /// The launchable URL for a bundle, given the identifier it belongs to.
    ///
    /// `installedCopy` is injected so the rule can be tested without depending on which applications
    /// happen to be installed on the machine running the tests.
    static func launchable(
        _ url: URL,
        bundleID: String?,
        installedCopy: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    ) -> URL {
        // `rebuild()` runs on every workspace change and walks every running app, so the common
        // case pays a string comparison rather than a trip to the file system. An extension of
        // `app` is only ever an application, which is the answer `isApplication` would give.
        if url.pathExtension == "app" || isApplication(url) { return url }
        guard let bundleID, let copy = installedCopy(bundleID), isApplication(copy) else { return url }
        return copy
    }

    /// The launchable URL for a running process, or nil when it has no bundle at all.
    ///
    /// The identifier comes from the process rather than from re-reading the bundle's `Info.plist`,
    /// which is both cheaper and still right if the bundle has been replaced underneath it.
    static func launchable(for app: NSRunningApplication) -> URL? {
        guard let url = app.bundleURL else { return nil }
        return launchable(url, bundleID: app.bundleIdentifier)
    }

    /// The launchable URL for a bundle we have nothing but a path for — a drag out of Finder, or a
    /// layout entry written before this rule existed. Anything that is not an application bundle is
    /// returned untouched, so folders and files are unaffected.
    static func normalised(_ url: URL) -> URL {
        if url.pathExtension == "app" || isApplication(url) { return url }
        return launchable(url, bundleID: applicationBundleID(at: url))
    }
}
