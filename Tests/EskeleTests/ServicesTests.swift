import AppKit
import Testing
@testable import Eskele

/// `Resources/Info.plist`, read from the repository rather than from a built bundle: the test target
/// is not the app, so the only copy it can see is the source of truth the build script copies.
private func infoPlist() throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EskeleTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root
    let url = root.appendingPathComponent("Resources/Info.plist")
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(plist as? [String: Any])
}

private func serviceEntry() throws -> [String: Any] {
    let services = try #require(try infoPlist()["NSServices"] as? [[String: Any]])
    #expect(services.count == 1)
    return try #require(services.first)
}

/// The plist names a message and macOS turns it into a selector. Nothing checks that the selector
/// exists — a rename on either side leaves a menu item that quietly does nothing at all — so this
/// is the check.
@MainActor
@Test func theServiceMessageMatchesAMethodThatExists() throws {
    let message = try #require(try serviceEntry()["NSMessage"] as? String)
    #expect(message == ServicesProvider.messageName)

    // macOS appends the two fixed arguments to form the selector it sends.
    let selector = Selector("\(message):userData:error:")
    #expect(
        ServicesProvider.instancesRespond(to: selector),
        "ServicesProvider has no \(selector) — the Services menu item would do nothing")
}

/// The port name is how the pasteboard server finds the running app; it has to be the executable's
/// name, not the display name.
@MainActor
@Test func theServiceIsAddressedToThisApp() throws {
    let entry = try serviceEntry()
    let plist = try infoPlist()
    #expect(entry["NSPortName"] as? String == plist["CFBundleExecutable"] as? String)

    let menuItem = try #require(entry["NSMenuItem"] as? [String: Any])
    let title = try #require(menuItem["default"] as? String)
    #expect(!title.isEmpty)
}

/// The bar pins applications, folders and files. `public.item` is the one type that covers all
/// three; anything narrower would hide the menu item for something that would have worked.
@MainActor
@Test func theServiceAcceptsEverythingTheBarCanPin() throws {
    let types = try #require(try serviceEntry()["NSSendFileTypes"] as? [String])
    #expect(types.contains("public.item"))
}

/// Each of the three kinds a Finder selection can be must survive the round trip into a stored item,
/// or the menu item would accept a drop the bar then discards.
@MainActor
@Test func everyKindTheServiceAcceptsCanBeStored() throws {
    let application = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let folder = URL(fileURLWithPath: "/System/Library/CoreServices")
    #expect(PersistedItem.make(for: application)?.kind == .app)
    #expect(PersistedItem.make(for: folder)?.kind == .folder)

    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("eskele-service-\(UUID().uuidString).txt")
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(PersistedItem.make(for: file)?.kind == .file)

    // Something that is not there any more is refused rather than stored as a hole.
    #expect(PersistedItem.make(for: file.appendingPathExtension("gone")) == nil)
}
