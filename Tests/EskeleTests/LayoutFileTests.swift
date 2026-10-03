import Foundation
import Testing
@testable import Eskele

private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
private let otherHome = URL(fileURLWithPath: "/Users/else", isDirectory: true)

private func app(_ id: String, _ name: String) -> PersistedItem {
    PersistedItem(
        kind: .app, bundleID: id, bookmark: Data([1, 2, 3]),
        path: "/Applications/\(name).app", name: name)
}

private func folder(_ path: String) -> PersistedItem {
    PersistedItem(
        kind: .folder, bookmark: Data([4, 5, 6]), path: path,
        name: URL(fileURLWithPath: path).lastPathComponent)
}

/// A Mac where only `present` exists: an entry is found when its bundle ID or its path is listed.
/// `make` stands in for `PersistedItem.make`, which reads the real disk.
private func resolve(_ items: [PersistedItem], on home: URL, present: Set<String>)
    -> LayoutFile.Resolution
{
    LayoutFile.resolve(
        items, home: home,
        locate: { entry in
            if let id = entry.bundleID, present.contains(id) {
                return URL(fileURLWithPath: "/Applications/\(entry.name ?? id).app")
            }
            if let path = entry.path, present.contains(path) { return URL(fileURLWithPath: path) }
            return nil
        },
        make: { url in
            url.pathExtension == "app"
                ? PersistedItem(kind: .app, bundleID: "id.\(url.lastPathComponent)", path: url.path)
                : PersistedItem(kind: .folder, path: url.path, name: url.lastPathComponent)
        })
}

// MARK: - Export

/// A bookmark names a file on one volume of one Mac; elsewhere it is noise at best.
@Test func anExportCarriesNoBookmarks() {
    let portable = LayoutFile.portable([app("com.apple.Safari", "Safari"), folder("/tmp")], home: home)
    #expect(portable.allSatisfy { $0.bookmark == nil })
}

@Test func pathsInTheHomeFolderTravelRelativeToIt() {
    let portable = LayoutFile.portable([
        folder("/Users/someone/Downloads"),
        folder("/Users/someone"),
        folder("/Users/someoneelse/Shared"),
        folder("/Volumes/Archive"),
    ], home: home)
    #expect(portable.map(\.path) == ["~/Downloads", "~", "/Users/someoneelse/Shared", "/Volumes/Archive"])
}

@Test func anExportReadsBackAsALayout() throws {
    var renamed = folder("/Users/someone/Downloads")
    renamed.customName = "Inbox"
    renamed.stackSort = .dateModified
    let data = try LayoutFile.encode([renamed, .separator()], home: home)
    let items = try LayoutFile.read(data)
    #expect(items.count == 2)
    #expect(items.first?.path == "~/Downloads")
    #expect(items.first?.customName == "Inbox")
    #expect(items.first?.stackSort == .dateModified)
}

// MARK: - Reading

/// `Layout` decodes any object at all as an empty layout, so a settings file would otherwise import
/// as a bar with nothing on it.
@Test func aFileWithoutAnItemsListIsRefused() {
    for json in [#"{"showTrash": false, "edge": "left"}"#, "{}", "[]", "not json"] {
        #expect(throws: LayoutFile.ReadError.notLayout) { try LayoutFile.read(Data(json.utf8)) }
    }
}

@Test func aCopyOfLayoutJSONReads() throws {
    let data = try JSONEncoder().encode(Layout(items: [app("com.apple.Safari", "Safari")]))
    #expect(try LayoutFile.read(data).first?.bundleID == "com.apple.Safari")
}

// MARK: - Importing

/// The point of the feature: another Mac, another user name, the same Downloads.
@Test func aHomeFolderPathIsFoundUnderThisMacsHome() {
    let exported = LayoutFile.portable([folder("/Users/else/Downloads")], home: otherHome)
    let resolution = resolve(exported, on: home, present: ["/Users/someone/Downloads"])
    #expect(resolution.items.map(\.path) == ["/Users/someone/Downloads"])
    #expect(resolution.missing.isEmpty)
}

@Test func whatIsNotHereIsReportedByTheNameTheUserKnows() {
    var renamed = folder("~/Projects")
    renamed.customName = "Work"
    let resolution = resolve(
        [app("com.apple.Safari", "Safari"), app("com.example.Gone", "Gone"), renamed],
        on: home, present: ["com.apple.Safari"])
    #expect(resolution.items.count == 1)
    #expect(resolution.missing == ["Gone", "Work"])
}

/// What was found is made afresh, so its bookmark is this Mac's — but the user's name for it and
/// its stack order are theirs, not the file system's, and come along.
@Test func aFoundItemKeepsItsNameAndOrder() {
    var item = folder("~/Downloads")
    item.customName = "Inbox"
    item.stackSort = .kind
    let found = resolve([item], on: home, present: ["/Users/someone/Downloads"]).items.first
    #expect(found?.customName == "Inbox")
    #expect(found?.stackSort == .kind)
}

/// A separator between two things that were both left out would be a gap with no reason.
@Test func separatorsAreNotLeftStranded() {
    let items: [PersistedItem] = [
        .separator(), app("com.apple.Safari", "Safari"), .separator(),
        app("com.example.Gone", "Gone"), .separator(), app("com.apple.mail", "Mail"), .separator(),
    ]
    let resolution = resolve(items, on: home, present: ["com.apple.Safari", "com.apple.mail"])
    #expect(resolution.items.map(\.kind) == [.app, .separator, .app])
}

@Test func theSameThingTwiceIsPinnedOnce() {
    let resolution = resolve(
        [folder("~/Downloads"), folder("/Users/someone/Downloads")],
        on: home, present: ["/Users/someone/Downloads"])
    #expect(resolution.items.count == 1)
}

// MARK: - On the real disk

/// The stand-ins above decide what exists; this lets `resolveURL` and `make` do it. One home is
/// exported, renamed to another as a second Mac would have it, and imported there.
@Test func aRealLayoutSurvivesMovingToAnotherHome() throws {
    let temporary = try #require(realpath(NSTemporaryDirectory(), nil))
    defer { free(temporary) }
    let root = URL(fileURLWithPath: String(cString: temporary))
        .appendingPathComponent("eskele-layout-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let before = root.appendingPathComponent("before", isDirectory: true)
    let after = root.appendingPathComponent("after", isDirectory: true)
    try FileManager.default.createDirectory(
        at: before.appendingPathComponent("Downloads"), withIntermediateDirectories: true)

    var downloads = try #require(PersistedItem.make(for: before.appendingPathComponent("Downloads")))
    downloads.customName = "Inbox"
    // Finder at a path no Mac has: only its bundle identifier can find it.
    var finder = try #require(PersistedItem.make(
        for: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
    finder.path = "/Nowhere/Finder.app"
    let data = try LayoutFile.encode([finder, downloads], home: before)

    try FileManager.default.moveItem(at: before, to: after)
    let resolution = LayoutFile.resolve(try LayoutFile.read(data), home: after)

    #expect(resolution.missing.isEmpty)
    #expect(resolution.items.map(\.kind) == [.app, .folder])
    #expect(resolution.items.first?.bundleID == "com.apple.finder")
    #expect(resolution.items.last?.path == after.appendingPathComponent("Downloads").path)
    #expect(resolution.items.last?.customName == "Inbox")
    // Made afresh here, so it has a bookmark of this Mac's own.
    #expect(resolution.items.last?.bookmark != nil)
}
