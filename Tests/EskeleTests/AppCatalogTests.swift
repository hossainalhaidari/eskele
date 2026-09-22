import Foundation
import Testing
@testable import Eskele

private func fixture() -> (roots: [URL], cleanup: () -> Void) {
    let base = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-catalog-\(UUID().uuidString)")
    let apps = base.appendingPathComponent("Apps")
    let system = base.appendingPathComponent("SysApps")
    let utilities = system.appendingPathComponent("Utilities")
    let buried = utilities.appendingPathComponent("Deep")

    let manager = FileManager.default
    for bundle in ["Zebra.app", "Alpha.app"] {
        try? manager.createDirectory(at: apps.appendingPathComponent(bundle), withIntermediateDirectories: true)
    }
    for bundle in ["Mango.app", "Alpha.app"] {
        try? manager.createDirectory(at: system.appendingPathComponent(bundle), withIntermediateDirectories: true)
    }
    try? manager.createDirectory(at: utilities.appendingPathComponent("Terminal.app"), withIntermediateDirectories: true)
    try? manager.createDirectory(at: buried.appendingPathComponent("Buried.app"), withIntermediateDirectories: true)

    return ([apps, system], { try? manager.removeItem(at: base) })
}

@Test func catalogIsSortedByName() {
    let (roots, cleanup) = fixture()
    defer { cleanup() }
    let names = AppCatalog.scan(roots: roots, extras: []).map(\.name)
    #expect(names == ["Alpha", "Mango", "Terminal", "Zebra"])
}

/// Utilities lives one level down and must be picked up; anything deeper is a developer's folder
/// tree, not an app directory, and walking it would be slow for nothing.
@Test func catalogReachesUtilitiesButNoDeeper() {
    let (roots, cleanup) = fixture()
    defer { cleanup() }
    let names = AppCatalog.scan(roots: roots, extras: []).map(\.name)
    #expect(names.contains("Terminal"))
    #expect(!names.contains("Buried"))
}

/// The same app in two roots is one entry, and the earlier root wins so a user's own copy shadows
/// the system one.
@Test func duplicateBundleNamesAreCollapsed() {
    let (roots, cleanup) = fixture()
    defer { cleanup() }
    let entries = AppCatalog.scan(roots: roots, extras: [])
    let alphas = entries.filter { $0.name == "Alpha" }
    #expect(alphas.count == 1)
    #expect(alphas.first?.url?.path.contains("/Apps/") == true)
}

@Test func missingRootsAreSkipped() {
    let entries = AppCatalog.scan(roots: [URL(fileURLWithPath: "/nope-\(UUID().uuidString)")], extras: [])
    #expect(entries.isEmpty)
}

@Test func theRealCatalogFindsInstalledApps() {
    let entries = AppCatalog.scan()
    #expect(entries.count > 20)
    #expect(entries.contains { $0.name == "Finder" })
    // Sorted, deduplicated, and never containing a bundle from inside another bundle.
    #expect(!entries.contains { $0.url?.path.contains(".app/Contents") == true })
}

/// A background agent has no window and no reason to be in a launcher, and there are more of them
/// installed than there are apps. They also carry no category, so leaving them in would make
/// "Other" the biggest group in the list.
@Test func backgroundAgentsAreLeftOut() {
    let (roots, cleanup) = fixture()
    defer { cleanup() }
    write(plist: ["LSUIElement": true], into: roots[0].appendingPathComponent("Zebra.app"))
    write(plist: ["LSBackgroundOnly": "1"], into: roots[0].appendingPathComponent("Alpha.app"))

    let names = AppCatalog.scan(roots: roots, extras: []).map(\.name)
    #expect(!names.contains("Zebra"))
    #expect(!names.contains("Alpha"))
    #expect(names.contains("Mango"))
}

/// A bundle with no readable Info.plist is an ordinary app, never a reason to drop it.
@Test func aBundleWithoutAnInfoPlistIsStillListed() {
    let (roots, cleanup) = fixture()
    defer { cleanup() }
    #expect(AppCatalog.scan(roots: roots, extras: []).contains { $0.name == "Mango" })
}

@Test func theDeclaredCategoryWins() {
    let (roots, cleanup) = fixture()
    defer { cleanup() }
    write(plist: ["LSApplicationCategoryType": "public.app-category.developer-tools"],
          into: roots[0].appendingPathComponent("Zebra.app"))

    let zebra = AppCatalog.scan(roots: roots, extras: []).first { $0.name == "Zebra" }
    #expect(zebra?.category.title == "Developer Tools")
}

/// The Utilities folders are a category in everything but the metadata, and almost nothing in them
/// declares one.
@Test func theUtilitiesFolderStandsInForAMissingCategory() {
    let (roots, cleanup) = fixture()
    defer { cleanup() }
    let entries = AppCatalog.scan(roots: roots, extras: [])
    #expect(entries.first { $0.name == "Terminal" }?.category == .utilities)
    #expect(entries.first { $0.name == "Mango" }?.category == .other)
}

private func write(plist: [String: Any], into bundle: URL) {
    let contents = bundle.appendingPathComponent("Contents")
    try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let data = try? PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
    try? data?.write(to: contents.appendingPathComponent("Info.plist"))
}
