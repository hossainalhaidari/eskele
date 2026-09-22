import AppKit
import Testing
@testable import Eskele

private let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

@MainActor
private func makeModel() throws -> (DockModel, Persistence, URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-rename-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let persistence = Persistence(directory: directory)
    let entry = try #require(PersistedItem.make(for: finder))
    persistence.saveLayout([entry])

    var settings = Settings()
    settings.showRunningUnpinned = false
    settings.showTrash = false
    settings.showAppsMenu = false
    let model = DockModel(
        persistence: persistence, running: RunningAppsService(), settings: settings)
    return (model, persistence, directory)
}

@MainActor
private func finderCell(_ model: DockModel) throws -> DockItem {
    try #require(model.items.first { $0.isApp })
}

// MARK: - The name a cell shows

@MainActor
@Test func aRenamedCellShowsTheNameItWasGiven() throws {
    let (model, _, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    let before = try finderCell(model)
    #expect(before.displayName == "Finder")
    #expect(model.customName(of: before) == nil)

    model.rename(before, to: "Files")
    let after = try finderCell(model)
    #expect(after.displayName == "Files")
    #expect(model.customName(of: after) == "Files")
    // The hover label is the other place a name is read.
    #expect(after.hoverTitle == "Files")
}

/// The name has to reach the app's *reference* too, or a window button and the Quit menu item would
/// go on calling it by its real name.
@MainActor
@Test func theNameTravelsWithTheApp() throws {
    let (model, _, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    model.rename(try finderCell(model), to: "Files")
    let item = try finderCell(model)
    guard case .app(let ref) = item.kind else { Issue.record("not an app"); return }
    #expect(ref.name == "Files")
}

@MainActor
@Test func resettingGoesBackToTheRealName() throws {
    let (model, _, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    model.rename(try finderCell(model), to: "Files")
    model.rename(try finderCell(model), to: nil)
    #expect(try finderCell(model).displayName == "Finder")
    #expect(model.customName(of: try finderCell(model)) == nil)
}

/// Whitespace is not a name. Typing spaces into the field is how somebody clears it by hand.
@MainActor
@Test func blankNamesClearRatherThanBlankTheCell() throws {
    let (model, _, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    model.rename(try finderCell(model), to: "   ")
    #expect(try finderCell(model).displayName == "Finder")

    model.rename(try finderCell(model), to: "")
    #expect(try finderCell(model).displayName == "Finder")

    // And a name with spaces around it keeps the name, not the spaces.
    model.rename(try finderCell(model), to: "  Files  ")
    #expect(try finderCell(model).displayName == "Files")
}

// MARK: - Storage

/// Renaming writes to `layout.json`, so it survives a restart — that is the whole point of storing
/// it rather than keeping it in memory like a running app's position.
@MainActor
@Test func aNameSurvivesBeingReloaded() throws {
    let (model, persistence, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    model.rename(try finderCell(model), to: "Files")

    let stored = persistence.loadLayout()
    #expect(stored.first?.customName == "Files")
    // `name` is what it was called when it was pinned, and is left alone — so an app renamed on
    // disk still follows its own name once the override is cleared.
    #expect(stored.first?.name == "Finder")
}

@Test func customNameRoundTripsThroughTheLayoutFile() throws {
    var entry = try #require(PersistedItem.make(for: finder))
    entry.customName = "Files"
    let data = try JSONEncoder().encode(Layout(items: [entry]))
    let decoded = try JSONDecoder().decode(Layout.self, from: data)
    #expect(decoded.items.first?.customName == "Files")
}

/// A layout written before renaming existed has to decode with no name rather than failing.
@Test func aLayoutWithoutTheFieldStillDecodes() throws {
    let json = """
        {"version": 1, "items": [
            {"kind": "app", "bundleID": "com.apple.Safari", "name": "Safari"}
        ]}
        """
    let layout = try JSONDecoder().decode(Layout.self, from: Data(json.utf8))
    #expect(layout.items.count == 1)
    #expect(layout.items.first?.customName == nil)
    #expect(layout.items.first?.name == "Safari")
}
