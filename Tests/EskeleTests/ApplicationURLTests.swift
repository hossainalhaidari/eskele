import AppKit
import Testing
@testable import Eskele

/// Steam's client updates itself into `~/Library/Application Support/Steam/Steam.AppBundle/Steam`
/// and runs from there: a real `APPL` bundle with Steam's identifier and no `.app` extension. macOS
/// will not *launch* such a path — it opens it, and opening a bundle means Finder — so a cell built
/// from `NSRunningApplication.bundleURL` opened Steam's folder instead of Steam, and LaunchServices
/// reported success while doing it. These tests pin the rule that fixed it.
struct ApplicationURLTests {
    /// A bundle laid out like Steam's: `Contents/Info.plist` with `CFBundlePackageType APPL`, and a
    /// directory name carrying whatever extension the test is about.
    private func makeBundle(named name: String, id: String, packageType: String = "APPL") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("eskele-appurl-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent(name, isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": id,
            "CFBundleExecutable": "stub",
            "CFBundlePackageType": packageType,
        ]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eskele-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - The rule

    /// The Steam case. An application bundle macOS will not launch resolves to the installed copy of
    /// the same identifier — the `/Applications` one the user believes they are clicking.
    @Test func anExtensionLessAppBundleResolvesToTheInstalledCopy() throws {
        let inner = try makeBundle(named: "Steam", id: "com.example.steam")
        defer { try? FileManager.default.removeItem(at: inner.deletingLastPathComponent()) }
        let installed = URL(fileURLWithPath: "/System/Applications/Calendar.app")

        let resolved = ApplicationURL.launchable(
            inner, bundleID: "com.example.steam", installedCopy: { _ in installed })

        #expect(resolved == installed)
    }

    /// An ordinary app is left exactly as it was: the rule must not reroute the common case through
    /// a LaunchServices lookup that could pick a different copy.
    @Test func anOrdinaryAppIsUntouched() {
        let app = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        var asked = false

        let resolved = ApplicationURL.launchable(app, bundleID: "com.apple.iCal", installedCopy: { _ in
            asked = true
            return URL(fileURLWithPath: "/System/Applications/Mail.app")
        })

        #expect(resolved == app)
        #expect(!asked, "a .app needs no lookup at all")
    }

    /// Nothing installed under that identifier: the original URL comes back, so an app that only
    /// ever exists in this shape behaves exactly as it did before the rule existed.
    @Test func withNoInstalledCopyTheOriginalSurvives() throws {
        let inner = try makeBundle(named: "Steam", id: "com.example.steam")
        defer { try? FileManager.default.removeItem(at: inner.deletingLastPathComponent()) }

        let resolved = ApplicationURL.launchable(inner, bundleID: "com.example.steam", installedCopy: { _ in nil })

        #expect(resolved == inner)
    }

    /// A process with no identifier has nothing to look the installed copy up by.
    @Test func withNoBundleIDTheOriginalSurvives() throws {
        let inner = try makeBundle(named: "Steam", id: "com.example.steam")
        defer { try? FileManager.default.removeItem(at: inner.deletingLastPathComponent()) }

        #expect(ApplicationURL.launchable(inner, bundleID: nil, installedCopy: { _ in
            URL(fileURLWithPath: "/System/Applications/Calendar.app")
        }) == inner)
    }

    /// The candidate has to be a real application too, or a stale LaunchServices answer would swap a
    /// working URL for a broken one.
    @Test func anInstalledCopyThatIsNotAnApplicationIsRefused() throws {
        let inner = try makeBundle(named: "Steam", id: "com.example.steam")
        let folder = try makeFolder()
        defer {
            try? FileManager.default.removeItem(at: inner.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: folder)
        }

        #expect(ApplicationURL.launchable(inner, bundleID: "com.example.steam", installedCopy: { _ in folder })
            == inner)
    }

    // MARK: - Telling an app bundle from a folder

    @Test func packageTypeSeparatesAnAppBundleFromAFolderThatMerelyLooksLikeOne() throws {
        let app = try makeBundle(named: "Steam", id: "com.example.steam")
        let notApp = try makeBundle(named: "Bundle", id: "com.example.thing", packageType: "BNDL")
        let folder = try makeFolder()
        defer {
            try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: notApp.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: folder)
        }

        #expect(ApplicationURL.applicationBundleID(at: app) == "com.example.steam")
        #expect(ApplicationURL.applicationBundleID(at: notApp) == nil)
        #expect(ApplicationURL.applicationBundleID(at: folder) == nil)
    }

    /// The finding the whole fix rests on: macOS does not consider Steam's client an application,
    /// and does consider an ordinary `.app` one.
    @Test func macOSDoesNotCallAnExtensionLessBundleAnApplication() throws {
        let inner = try makeBundle(named: "Steam", id: "com.example.steam")
        defer { try? FileManager.default.removeItem(at: inner.deletingLastPathComponent()) }

        #expect(!ApplicationURL.isApplication(inner))
        #expect(ApplicationURL.isApplication(URL(fileURLWithPath: "/System/Applications/Calendar.app")))
    }

    // MARK: - What gets written to the layout

    /// Pinning such a cell used to store it as a *folder*, which is how one bad click became a
    /// permanent one. Unregistered here, so the entry cannot be rescued by the lookup and the kind
    /// is the only thing under test.
    @Test func pinningAFolderStillStoresAFolder() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(PersistedItem.make(for: folder)?.kind == .folder)
    }

    @Test func pinningAnOrdinaryAppStillStoresAnApp() {
        let entry = PersistedItem.make(for: URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        #expect(entry?.kind == .app)
        #expect(entry?.bundleID == "com.apple.iCal")
    }

    private static let steamClient = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Steam/Steam.AppBundle/Steam")

    /// Steam's own client must never be stored as a folder. Skipped where Steam is not installed, a
    /// CI runner among them: a failed `#require` is a failure, not a skip.
    @Test(.enabled(
        if: FileManager.default.fileExists(atPath: steamClient.path)
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.valvesoftware.steam") != nil,
        "Steam's self-updated client is not on this machine"))
    func pinningSteamsOwnClientStoresTheApplication() {
        let entry = PersistedItem.make(for: Self.steamClient)
        #expect(entry?.kind == .app)
        #expect(entry?.bundleID == "com.valvesoftware.steam")
        #expect(entry?.path.map { URL(fileURLWithPath: $0).pathExtension } == "app")
    }
}
