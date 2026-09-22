import AppKit
import Testing
@testable import Eskele

private func urls(_ names: [String]) -> [URL] {
    names.map { URL(fileURLWithPath: "/tmp/Icons/\($0)") }
}

// MARK: - Naming

@Test func aFileIsMatchedToTheCellItIsNamedAfter() {
    let map = IconOverrideService.map(urls(["com.apple.Safari.png", "trash.icns"]))
    #expect(map["com.apple.safari"]?.lastPathComponent == "com.apple.Safari.png")
    #expect(map["trash"]?.lastPathComponent == "trash.icns")
}

/// The file system is case-insensitive on a default macOS volume, so a key that matched only on
/// exact case would be a puzzle with no clue in it.
@Test func capitalsDoNotMatter() {
    let map = IconOverrideService.map(urls(["COM.APPLE.SAFARI.png"]))
    #expect(map[IconOverrideService.normalise("com.apple.Safari")] != nil)
}

/// Two files for one cell has to resolve the same way every time, not by whichever the file system
/// listed first.
@Test func theEarliestExtensionWins() {
    let both = IconOverrideService.map(urls(["x.pdf", "x.png", "x.tiff"]))
    #expect(both["x"]?.pathExtension == "png")
    // Order of the directory listing must not change the answer.
    let reversed = IconOverrideService.map(urls(["x.tiff", "x.png", "x.pdf"]))
    #expect(reversed["x"]?.pathExtension == "png")
}

/// The folder holds a README, and people put other things in folders. Neither may become a cell.
@Test func filesThatAreNotImagesAreIgnored() {
    let map = IconOverrideService.map(urls(["README.txt", "notes.md", ".DS_Store", "x.png"]))
    #expect(map.count == 1)
    #expect(map["x"] != nil)
}

@Test func aFileWithNoNameIsIgnored() {
    #expect(IconOverrideService.map(urls([".png"])).isEmpty)
}

// MARK: - Which cells can be addressed

@Test func cellsWithANameAreAddressable() {
    let url = URL(fileURLWithPath: "/System/Applications/Music.app")
    let ref = AppRef(bundleID: "com.apple.Music", url: url, name: "Music")
    let window = WindowRef(pid: 1, title: "Music", isMinimized: false)

    #expect(DockItem(kind: .app(ref)).iconOverrideKey == "com.apple.Music")
    // A window button is the app's icon, so it takes the app's override.
    #expect(DockItem(kind: .window(ref, window)).iconOverrideKey == "com.apple.Music")
    #expect(DockItem(kind: .trash(isEmpty: true)).iconOverrideKey == IconOverrideService.trashKey)
    #expect(DockItem(kind: .appsMenu).iconOverrideKey == IconOverrideService.appsMenuKey)
}

/// A path is not a filename, and these have Finder's own Get Info route instead.
@Test func foldersAndFilesAreNotAddressable() {
    #expect(DockItem(kind: .folder(URL(fileURLWithPath: "/Users/x/Downloads"))).iconOverrideKey == nil)
    #expect(DockItem(kind: .file(URL(fileURLWithPath: "/Users/x/a.txt"))).iconOverrideKey == nil)
    #expect(DockItem(kind: .separator("s")).iconOverrideKey == nil)
    #expect(DockItem(kind: .clock).iconOverrideKey == nil)
}

// MARK: - End to end

/// The whole point: a file in the folder is drawn instead of the real icon, and taking it away puts
/// the real one back.
@MainActor
@Test func anOverrideFileReplacesTheRealIcon() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-icons-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let service = IconOverrideService(directory: directory)
    defer { service.stop() }
    let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    let key = "com.apple.finder"

    IconService.shared.setOverrides([:])
    let real = IconService.shared.icon(for: finder, key: key, pointSize: 32, scale: 2)

    // A plain red square, which no real app icon is.
    let square = NSImage(size: NSSize(width: 64, height: 64))
    square.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 64, height: 64).fill()
    square.unlockFocus()
    let tiff = try #require(square.tiffRepresentation)
    let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try data.write(to: directory.appendingPathComponent("\(key).png"))

    service.rescan()
    #expect(service.url(for: "com.apple.Finder") != nil)   // and case-insensitively
    IconService.shared.setOverrides(service.files)

    let overridden = IconService.shared.icon(for: finder, key: key, pointSize: 32, scale: 2)
    #expect(!overridden.tiffRepresentation!.elementsEqual(real.tiffRepresentation!))

    // Taking the file away restores the real icon rather than leaving the last one cached.
    try FileManager.default.removeItem(at: directory.appendingPathComponent("\(key).png"))
    service.rescan()
    IconService.shared.setOverrides(service.files)
    let restored = IconService.shared.icon(for: finder, key: key, pointSize: 32, scale: 2)
    #expect(restored.tiffRepresentation!.elementsEqual(real.tiffRepresentation!))

    IconService.shared.setOverrides([:])
}

/// A stray text file renamed to .png must not blank a cell.
@MainActor
@Test func anUnreadableOverrideFallsBackToTheRealIcon() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-icons-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try Data("not an image".utf8).write(to: directory.appendingPathComponent("com.apple.finder.png"))
    let service = IconOverrideService(directory: directory)
    defer { service.stop() }

    let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    IconService.shared.setOverrides([:])
    let real = IconService.shared.icon(for: finder, key: "com.apple.finder", pointSize: 32, scale: 2)
    IconService.shared.setOverrides(service.files)
    let drawn = IconService.shared.icon(for: finder, key: "com.apple.finder", pointSize: 32, scale: 2)

    #expect(drawn.tiffRepresentation!.elementsEqual(real.tiffRepresentation!))
    IconService.shared.setOverrides([:])
}

/// Dropping a file into the folder has to show on the bar without a restart — that is the whole
/// interface, so the watch is the feature.
@MainActor
@Test func aFileAppearingIsNoticedWithoutARestart() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-icons-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let service = IconOverrideService(directory: directory)
    defer { service.stop() }
    #expect(service.files.isEmpty)

    var changes = 0
    service.onChange = { changes += 1 }

    let square = NSImage(size: NSSize(width: 8, height: 8))
    square.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 8, height: 8).fill()
    square.unlockFocus()
    let tiff = try #require(square.tiffRepresentation)
    try tiff.write(to: directory.appendingPathComponent("com.example.app.tiff"))

    let deadline = Date().addingTimeInterval(5)
    while service.files.isEmpty, Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(service.url(for: "com.example.app") != nil)
    #expect(changes >= 1)

    // And going away again.
    try FileManager.default.removeItem(at: directory.appendingPathComponent("com.example.app.tiff"))
    let gone = Date().addingTimeInterval(5)
    while !service.files.isEmpty, Date() < gone {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(service.files.isEmpty)
}
