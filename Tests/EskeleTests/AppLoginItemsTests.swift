import Foundation
import Testing
@testable import Eskele

private let mail = URL(fileURLWithPath: "/System/Applications/Mail.app")

private func identify(_ table: [String: String]) -> (URL) -> String? {
    { table[$0.path] }
}

@MainActor
@Test func theSamePathIsTheSameApp() {
    #expect(AppLoginItems.matches(
        URL(fileURLWithPath: "/System/Applications/Mail.app/"), url: mail, bundleID: nil,
        identify: identify([:])))
}

/// An app moved since it was added — another copy in another folder — is still the same app.
@MainActor
@Test func aMovedCopyIsFoundByItsBundleIdentifier() {
    let moved = URL(fileURLWithPath: "/Users/someone/Applications/Mail.app")
    #expect(AppLoginItems.matches(
        moved, url: mail, bundleID: "com.apple.mail",
        identify: identify([moved.path: "com.apple.mail"])))
    #expect(!AppLoginItems.matches(
        moved, url: mail, bundleID: "com.apple.mail",
        identify: identify([moved.path: "com.apple.Safari"])))
}

/// An entry whose app is gone — Ollama in the Trash, say — resolves to nothing and matches nothing.
@MainActor
@Test func anEntryThatResolvesToNothingMatchesNothing() {
    #expect(!AppLoginItems.matches(nil, url: mail, bundleID: "com.apple.mail", identify: identify([:])))
}

/// The real list, with a throwaway app that is added and removed again. Off unless asked for,
/// because it changes the login items of whoever runs the suite for as long as it takes:
///
///     ESKELE_LOGIN_ITEM_PROBE=1 swift test --filter AppLoginItems
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["ESKELE_LOGIN_ITEM_PROBE"] == "1"))
func theRealListTakesAnAppAndGivesItBack() throws {
    #expect(AppLoginItems.isAvailable)
    let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("EskeleLoginProbe-\(UUID().uuidString).app", isDirectory: true)
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundle) }
    let id = "app.eskele.login-probe"
    let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    defer { AppLoginItems.setEnabled(false, url: bundle, bundleID: id) }

    #expect(!AppLoginItems.isEnabled(url: bundle, bundleID: id))
    #expect(AppLoginItems.setEnabled(true, url: bundle, bundleID: id))
    #expect(AppLoginItems.isEnabled(url: bundle, bundleID: id))
    // Asking again is not a second entry.
    #expect(AppLoginItems.setEnabled(true, url: bundle, bundleID: id))
    #expect(AppLoginItems.setEnabled(false, url: bundle, bundleID: id))
    #expect(!AppLoginItems.isEnabled(url: bundle, bundleID: id))
}
