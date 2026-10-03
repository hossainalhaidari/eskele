import Foundation
import Testing
@testable import Eskele

private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func entry(
    _ name: String, folder: Bool = false, added: TimeInterval? = nil,
    modified: TimeInterval? = nil, created: TimeInterval? = nil, kind: String? = nil
) -> StackSort.Entry {
    StackSort.Entry(
        url: URL(fileURLWithPath: "/tmp/stack/\(name)", isDirectory: folder),
        isFolder: folder,
        added: added.map { base.addingTimeInterval($0) },
        modified: modified.map { base.addingTimeInterval($0) },
        created: created.map { base.addingTimeInterval($0) },
        kind: kind)
}

private func names(_ entries: [StackSort.Entry]) -> [String] { entries.map(\.name) }

// MARK: - Orders

/// The order the stack had before there was a choice, so a folder nobody touches looks the same.
@Test func byNameFoldersComeFirstAndNumbersReadAsNumbers() {
    let entries = [entry("b.txt"), entry("Zeta", folder: true), entry("a10.txt"), entry("a2.txt")]
    #expect(names(StackSort.name.ordered(entries)) == ["Zeta", "a2.txt", "a10.txt", "b.txt"])
}

/// The reason the option exists: what just arrived in Downloads is on top — a folder included.
@Test func byDateAddedTheNewestComesFirstFoldersIncluded() {
    let entries = [
        entry("old.pdf", added: 0),
        entry("Unzipped", folder: true, added: 300),
        entry("new.dmg", added: 600),
    ]
    #expect(names(StackSort.dateAdded.ordered(entries)) == ["new.dmg", "Unzipped", "old.pdf"])
}

@Test func eachDateOrderReadsItsOwnDate() {
    let entries = [
        entry("a", added: 100, modified: 0, created: 50),
        entry("b", added: 0, modified: 100, created: 0),
        entry("c", added: 50, modified: 50, created: 100),
    ]
    #expect(names(StackSort.dateAdded.ordered(entries)) == ["a", "c", "b"])
    #expect(names(StackSort.dateModified.ordered(entries)) == ["b", "c", "a"])
    #expect(names(StackSort.dateCreated.ordered(entries)) == ["c", "a", "b"])
}

/// No date is not "the oldest date there is" — it is not knowing, and those go to the bottom
/// rather than being argued about.
@Test func entriesWithoutADateGoLast() {
    let entries = [entry("unknown"), entry("old", added: 0), entry("new", added: 100)]
    #expect(names(StackSort.dateAdded.ordered(entries)) == ["new", "old", "unknown"])
}

/// Ties fall back to the name, so the stack is never in whatever order the directory listed.
@Test func tiesAreBrokenByName() {
    let entries = [entry("c", added: 0), entry("a", added: 0), entry("b", added: 0)]
    #expect(names(StackSort.dateAdded.ordered(entries)) == ["a", "b", "c"])
}

@Test func byKindGroupsByKindThenName() {
    let entries = [
        entry("z.pdf", kind: "PDF document"),
        entry("a.png", kind: "PNG image"),
        entry("Docs", folder: true, kind: "Folder"),
        entry("b.pdf", kind: "PDF document"),
    ]
    #expect(names(StackSort.kind.ordered(entries)) == ["Docs", "b.pdf", "z.pdf", "a.png"])
}

// MARK: - Defaults

@Test func downloadsDefaultsToNewestFirstAndEverythingElseToName() {
    let downloads = URL(fileURLWithPath: "/Users/someone/Downloads", isDirectory: true)
    #expect(StackSort.defaultOrder(for: downloads, downloads: downloads) == .dateAdded)
    // The same folder written another way is still the same folder.
    #expect(StackSort.defaultOrder(
        for: URL(fileURLWithPath: "/Users/someone/Downloads/"), downloads: downloads) == .dateAdded)
    #expect(StackSort.defaultOrder(
        for: URL(fileURLWithPath: "/Users/someone/Documents"), downloads: downloads) == .name)
    #expect(StackSort.defaultOrder(for: downloads, downloads: nil) == .name)
}

// MARK: - Storage

/// An order a later version adds must not cost the folder its place on the bar: a field that fails
/// to decode fails the item, and the layout drops items that fail.
@Test func anUnknownOrderReadsAsNameAndKeepsTheFolder() throws {
    let json = """
        {"version": 1, "items": [
            {"kind": "folder", "path": "/tmp", "name": "tmp", "stackSort": "dateLastOpened"}
        ]}
        """
    let layout = try JSONDecoder().decode(Layout.self, from: Data(json.utf8))
    #expect(layout.items.count == 1)
    #expect(layout.items.first?.stackSort == .name)
}

@Test func aLayoutWithoutAnOrderStillDecodes() throws {
    let json = """
        {"version": 1, "items": [{"kind": "folder", "path": "/tmp", "name": "tmp"}]}
        """
    let layout = try JSONDecoder().decode(Layout.self, from: Data(json.utf8))
    #expect(layout.items.first?.stackSort == nil)
}

@MainActor
private func makeModel() throws -> (DockModel, Persistence, URL) {
    // Resolved, because the temporary directory is under `/var`, a link to `/private/var`: the
    // bookmark resolves to the real path, and the cell would then not match what was stored.
    // `realpath` rather than `resolvingSymlinksInPath`, which strips `/private` back off.
    let temporary = try #require(realpath(NSTemporaryDirectory(), nil))
    defer { free(temporary) }
    let directory = URL(fileURLWithPath: String(cString: temporary))
        .appendingPathComponent("eskele-stack-sort-\(UUID().uuidString)")
    let folder = directory.appendingPathComponent("Pinned", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let persistence = Persistence(directory: directory)
    persistence.saveLayout([try #require(PersistedItem.make(for: folder))])

    var settings = Settings()
    settings.showRunningUnpinned = false
    settings.showTrash = false
    settings.showAppsMenu = false
    let model = DockModel(
        persistence: persistence, running: RunningAppsService(), settings: settings)
    return (model, persistence, directory)
}

@MainActor
private func folderCell(_ model: DockModel) throws -> DockItem {
    try #require(model.items.first { $0.opensMenuOnClick && !$0.isAppsMenu })
}

@MainActor
@Test func aChosenOrderIsStoredAndReachesTheCell() throws {
    let (model, persistence, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(try folderCell(model).stackSort == .name)

    model.setStackSort(try folderCell(model), to: .dateModified)
    #expect(try folderCell(model).stackSort == .dateModified)
    #expect(persistence.loadLayout().first?.stackSort == .dateModified)
}

/// Choosing the default again stores nothing, so the folder goes back to following its default
/// rather than being pinned to a copy of it.
@MainActor
@Test func choosingTheDefaultAgainStoresNothing() throws {
    let (model, persistence, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    model.setStackSort(try folderCell(model), to: .kind)
    model.setStackSort(try folderCell(model), to: .name)
    #expect(try folderCell(model).stackSort == .name)
    #expect(persistence.loadLayout().first?.stackSort == nil)
}


// MARK: - The menu, over a real folder

/// The orders above are tested on values; this is the half that reads the dates off the file
/// system and builds the menu from them, which a typo in a resource key would break silently.
@MainActor
@Test func theStackMenuListsARealFolderInTheChosenOrder() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-stack-menu-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    // Names in one order, modification dates in another, creation dates in a third. Each file is
    // created before it was modified: the file system moves a later creation date back to the
    // modification date, which would make the test about that instead.
    let files: [(name: String, modified: TimeInterval, created: TimeInterval)] = [
        ("a.txt", 150, 100), ("b.txt", 300, 50), ("c.txt", 200, 0),
    ]
    for file in files {
        let url = folder.appendingPathComponent(file.name)
        try Data().write(to: url)
        try FileManager.default.setAttributes([
            .modificationDate: base.addingTimeInterval(file.modified),
            .creationDate: base.addingTimeInterval(file.created),
        ], ofItemAtPath: url.path)
    }
    try FileManager.default.createDirectory(
        at: folder.appendingPathComponent("Sub"), withIntermediateDirectories: false)
    try FileManager.default.setAttributes(
        [.modificationDate: base.addingTimeInterval(-100), .creationDate: base.addingTimeInterval(-100)],
        ofItemAtPath: folder.appendingPathComponent("Sub").path)

    let controller = StackMenuController()
    func titles(_ sort: StackSort) -> [String] {
        let menu = controller.menu(for: folder, sort: sort)
        controller.menuNeedsUpdate(menu)
        return menu.items.prefix { !$0.isSeparatorItem }.map(\.title)
    }
    #expect(titles(.name) == ["Sub", "a.txt", "b.txt", "c.txt"])
    #expect(titles(.dateModified) == ["b.txt", "c.txt", "a.txt", "Sub"])
    #expect(titles(.dateCreated) == ["a.txt", "b.txt", "c.txt", "Sub"])
    #expect(titles(.kind).first == "Sub")

    // And a subfolder opened from the stack inherits its order.
    let parent = controller.menu(for: folder, sort: .dateModified)
    controller.menuNeedsUpdate(parent)
    #expect(parent.items.first { $0.title == "Sub" }?.submenu != nil)
}
