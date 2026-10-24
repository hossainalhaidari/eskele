import AppKit
import Testing
@testable import Eskele

// MARK: - Which volumes are on the bar

/// The values as the volumes on a real Mac report them — measured, not assumed. A server reports no
/// answer at all for `isInternal`, since it has no drive to be inside.
private func shown(
    browsable: Bool = true, root: Bool = false, ejectable: Bool = false, removable: Bool = false,
    inside: Bool? = true, local: Bool = true
) -> Bool {
    MountedVolume.isShown(
        isBrowsable: browsable, isRoot: root, isEjectable: ejectable, isRemovable: removable,
        isInternal: inside, isLocal: local)
}

@Test func theStartupDiskIsNotOnTheBar() {
    #expect(!shown(root: true))
}

@Test func aSecondVolumeOnTheInternalDriveIsNotOnTheBar() {
    #expect(!shown())
}

@Test func anExternalDiskIsOnTheBar() {
    #expect(shown(inside: false))
    #expect(shown(ejectable: true, removable: true, inside: false))
}

@Test func aDiskImageIsOnTheBar() {
    #expect(shown(ejectable: true, removable: true, inside: nil))
}

@Test func aServerIsOnTheBar() {
    #expect(shown(inside: nil, local: false))
}

/// Xcode mounts one of these per simulator runtime, and macOS a dozen of its own under
/// `/System/Volumes`: every one is ejectable, and Finder shows none of them.
@Test func aVolumeFinderHidesIsNotOnTheBar() {
    #expect(!shown(browsable: false, ejectable: true, removable: true, inside: nil))
}

@Test func theStartupDiskAndAPlainFolderAreNotOnTheBar() {
    #expect(MountedVolume(url: URL(fileURLWithPath: "/")) == nil)
    #expect(MountedVolume(url: URL(fileURLWithPath: NSTemporaryDirectory())) == nil)
}

@Test func volumesAreListedByName() {
    let volumes = [
        MountedVolume(url: URL(fileURLWithPath: "/Volumes/Zeta"), name: "Zeta"),
        MountedVolume(url: URL(fileURLWithPath: "/Volumes/disk 10"), name: "disk 10"),
        MountedVolume(url: URL(fileURLWithPath: "/Volumes/disk 9"), name: "disk 9"),
        MountedVolume(url: URL(fileURLWithPath: "/Volumes/Alpha"), name: "Alpha"),
    ]
    // Numbers in names compare as numbers, as they do in Finder.
    #expect(MountedVolume.list(volumes).map(\.name) == ["Alpha", "disk 9", "disk 10", "Zeta"])
}

// MARK: - Dropping on the Trash

private let stick = MountedVolume(url: URL(fileURLWithPath: "/Volumes/Stick"), name: "Stick")
private let card = MountedVolume(url: URL(fileURLWithPath: "/Volumes/Card"), name: "Card")

private func lookup(_ url: URL) -> MountedVolume? {
    [stick, card].first { $0.url == url }
}

@Test func disksDroppedOnTheTrashAreEjected() {
    #expect(MountedVolume.ejectsOnTrash([stick.url, card.url], volume: lookup) == [stick, card])
}

@Test func aDropMixingADiskWithFilesDoesNotEject() {
    let file = URL(fileURLWithPath: "/Users/someone/Report.pdf")
    #expect(MountedVolume.ejectsOnTrash([stick.url, file], volume: lookup) == nil)
    #expect(MountedVolume.ejectsOnTrash([file], volume: lookup) == nil)
    #expect(MountedVolume.ejectsOnTrash([], volume: lookup) == nil)
}

// MARK: - The cell

private func volumeCell(ejecting: Bool = false) -> DockItem {
    var item = DockItem(kind: .volume(stick))
    item.isEjecting = ejecting
    return item
}

@Test func aDiskCellIsNamedAfterTheDisk() {
    #expect(volumeCell().displayName == "Stick")
    #expect(volumeCell().hoverTitle == "Stick")
    #expect(volumeCell(ejecting: true).hoverTitle == "Stick — ejecting…")
    #expect(volumeCell().url == stick.url)
}

@Test func voiceOverSaysADiskIsADiskAndWhenItIsGoing() throws {
    let still = try #require(CellDescription(item: volumeCell()))
    #expect(still.role == .button)
    #expect(still.label == "Stick")
    #expect(still.value == "disk")
    let going = try #require(CellDescription(item: volumeCell(ejecting: true)))
    #expect(going.value == "ejecting, disk")
}

@Test func aDiskOpensInFinderAndOnlyRevealsWithAModifier() {
    let cell = volumeCell()
    #expect(ClickAction.resolve(modifiers: [], for: cell) == .activate)
    #expect(ClickAction.resolve(modifiers: [.command], for: cell) == .revealInFinder)
    // Hiding and quitting are about programs.
    #expect(ClickAction.resolve(modifiers: [.option], for: cell) == nil)
    #expect(ClickAction.resolve(modifiers: [.shift], for: cell) == nil)
    #expect(ClickAction.resolve(modifiers: [], button: .middle, for: cell) == nil)
}

@Test func aDragHeldOverADiskOpensIt() {
    #expect(volumeCell().springsOpen)
}

@Test func disksAreShownUnlessTurnedOff() throws {
    #expect(Settings().showVolumes)
    let decoded = try JSONDecoder().decode(Settings.self, from: Data(#"{"showVolumes": false}"#.utf8))
    #expect(!decoded.showVolumes)
    // One bad value costs that value, as everywhere else in the file.
    let broken = try JSONDecoder().decode(Settings.self, from: Data(#"{"showVolumes": "yes"}"#.utf8))
    #expect(broken.showVolumes)
}

// MARK: - Where disks go on the bar

@MainActor
private func makeModel(
    pinning folder: URL? = nil, configure: (inout Settings) -> Void = { _ in }
) throws -> (DockModel, URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-volumes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let persistence = Persistence(directory: directory)
    var pinned: [PersistedItem] = []
    if let folder { pinned.append(try #require(PersistedItem.make(for: folder))) }
    // An empty layout is replaced by the default one, so a bar with nothing pinned gets a separator.
    persistence.saveLayout(pinned.isEmpty ? [.separator()] : pinned)

    var settings = Settings()
    settings.showRunningUnpinned = false
    settings.showAppsMenu = false
    settings.showTrash = true
    settings.showClock = true
    configure(&settings)
    let model = DockModel(
        persistence: persistence, running: RunningAppsService(), settings: settings)
    return (model, directory)
}

@MainActor
@Test func disksSitBesideTheTrashInNameOrder() throws {
    let (model, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    model.setVolumes([card, stick], ejecting: [])
    let tail = model.items.filter { !$0.isSeparator }.map(\.id)
    #expect(tail == ["volume:/Volumes/Card", "volume:/Volumes/Stick", "trash", "clock"])
}

@MainActor
@Test func disksAreLeftOffWhenTurnedOff() throws {
    let (model, directory) = try makeModel { $0.showVolumes = false }
    defer { try? FileManager.default.removeItem(at: directory) }

    model.setVolumes([stick], ejecting: [])
    #expect(!model.items.contains { $0.isVolume })
}

@MainActor
@Test func aDiskBeingEjectedSaysSo() throws {
    let (model, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    model.setVolumes([stick, card], ejecting: [stick.url.path])
    let ejecting = model.items.filter(\.isEjecting).map(\.displayName)
    #expect(ejecting == ["Stick"])
}

/// A disk pinned as a folder already has a cell, with Eject in its menu; a second cell for the same
/// place would be two icons for one thing.
@MainActor
@Test func aDiskPinnedAsAFolderHasNoSecondCell() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-pinned-disk-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let (model, directory) = try makeModel(pinning: folder)
    defer { try? FileManager.default.removeItem(at: directory) }

    let pinnedDisk = MountedVolume(url: folder, name: "Pinned")
    model.setVolumes([pinnedDisk, stick], ejecting: [])
    #expect(model.items.filter(\.isVolume).map(\.displayName) == ["Stick"])
    #expect(model.items.contains { $0.opensMenuOnClick })
}

/// A disk is draggable only so it can be dropped on the Trash. Dropping it anywhere else must not
/// pin it, as it would any other cell that has a URL and no stored slot.
@MainActor
@Test func draggingADiskAlongTheBarDoesNotPinIt() throws {
    let (model, directory) = try makeModel()
    defer { try? FileManager.default.removeItem(at: directory) }

    model.setVolumes([stick], ejecting: [])
    let before = model.pinnedItems
    let disk = try #require(model.items.first { $0.isVolume })
    model.move(disk, toVisualIndex: 0)
    #expect(model.pinnedItems == before)
    #expect(model.items.filter(\.isVolume).count == 1)
}
