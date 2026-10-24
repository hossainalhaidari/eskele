import AppKit
import Testing
@testable import Eskele

// MARK: - Which paths wait for a disk

@Test func aPathOnADiskNamesWhereThatDiskMounts() {
    #expect(PersistedItem.volumeMountPoint(of: "/Volumes/Stick/Photos") == "/Volumes/Stick")
    #expect(PersistedItem.volumeMountPoint(of: "/Volumes/Stick") == "/Volumes/Stick")
    #expect(PersistedItem.volumeMountPoint(of: "/Volumes/My Disk/a/b.pdf") == "/Volumes/My Disk")
}

@Test func aPathOnTheStartupDiskWaitsForNothing() {
    #expect(PersistedItem.volumeMountPoint(of: "/Users/someone/Documents") == nil)
    #expect(PersistedItem.volumeMountPoint(of: "/Volumes") == nil)
    #expect(PersistedItem.volumeMountPoint(of: "/Applications/Volumes/Thing") == nil)
}

@Test func onlyAPinWhoseDiskIsAwayWaits() {
    let pin = PersistedItem(kind: .folder, path: "/Volumes/Stick/Photos")
    #expect(pin.awaitsVolume { _ in false })
    #expect(!pin.awaitsVolume { _ in true })
    #expect(!PersistedItem(kind: .folder, path: "/Users/someone/Gone").awaitsVolume { _ in false })
    #expect(!PersistedItem(kind: .folder).awaitsVolume { _ in false })
}

@Test func theStartupDiskIsAMountPointAndAFolderIsNot() {
    #expect(PersistedItem.isMountPoint("/"))
    #expect(!PersistedItem.isMountPoint(NSTemporaryDirectory()))
    #expect(!PersistedItem.isMountPoint("/Volumes/eskele-no-such-disk-\(UUID().uuidString)"))
}

// MARK: - The layout keeps them

/// A pin on a disk that was never mounted here, stored as `layout.json` would hold it: the bookmark
/// cannot resolve, so the path is all there is.
private let photos = PersistedItem(
    kind: .folder, path: "/Volumes/Eskele Missing Disk/Photos", name: "Photos")

@MainActor
private final class Mounts {
    var mounted: Set<String> = []
}

@MainActor
private func makeModel(mounts: Mounts) throws -> (DockModel, Persistence, URL) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-unmounted-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let persistence = Persistence(directory: directory)
    persistence.saveLayout([.separator(), photos])

    var settings = Settings()
    settings.showRunningUnpinned = false
    settings.showAppsMenu = false
    settings.showTrash = false
    let model = DockModel(
        persistence: persistence, running: RunningAppsService(), settings: settings,
        isMountPoint: { mounts.mounted.contains($0) })
    return (model, persistence, directory)
}

@MainActor
@Test func aPinOnADiskThatIsAwayIsKeptButNotShown() throws {
    let (model, persistence, directory) = try makeModel(mounts: Mounts())
    defer { try? FileManager.default.removeItem(at: directory) }

    model.rebuild()
    #expect(!model.items.contains { $0.displayName == "Photos" })
    #expect(persistence.loadLayout().contains(photos))
    #expect(model.pinnedItems.contains(photos))
}

/// The disk is mounted and the folder still is not there: it was deleted, and the pin goes, as a pin
/// to anything deleted always has.
@MainActor
@Test func aPinWhoseDiskIsBackButWhoseFolderIsGoneIsForgotten() throws {
    let mounts = Mounts()
    let (model, persistence, directory) = try makeModel(mounts: mounts)
    defer { try? FileManager.default.removeItem(at: directory) }

    mounts.mounted = ["/Volumes/Eskele Missing Disk"]
    model.rebuild()
    #expect(!persistence.loadLayout().contains(photos))
    #expect(!model.pinnedItems.contains(photos))
}

/// Something else being forgotten rewrites the layout; the waiting pin has to survive that write,
/// in its place.
@MainActor
@Test func forgettingAnotherPinKeepsTheOneThatIsWaiting() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-unmounted-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = Persistence(directory: directory)
    let deleted = PersistedItem(kind: .folder, path: "/Users/eskele-nobody/Deleted", name: "Deleted")
    let separator = PersistedItem.separator()
    persistence.saveLayout([separator, photos, deleted])

    var settings = Settings()
    settings.showRunningUnpinned = false
    let model = DockModel(
        persistence: persistence, running: RunningAppsService(), settings: settings,
        isMountPoint: { _ in false })
    #expect(model.pinnedItems == [separator, photos])
    #expect(persistence.loadLayout() == [separator, photos])
}

/// The disk coming back, with the folder on it: the pin shows again where it was.
@MainActor
@Test func aPinComesBackWhenItsDiskDoes() throws {
    let disk = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-disk-\(UUID().uuidString)")
    let folder = disk.appendingPathComponent("Photos")
    defer { try? FileManager.default.removeItem(at: disk) }
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-unmounted-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // Pinned while the "disk" was there, then unplugged: the folder is gone and so is its mount.
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var stored = try #require(PersistedItem.make(for: folder))
    // Filed under `/Volumes` as a pin on a real disk would be. The bookmark still finds the folder,
    // which is what it does once the disk is back.
    stored.path = "/Volumes/Eskele Test Disk/Photos"
    let persistence = Persistence(directory: directory)
    persistence.saveLayout([stored])
    try FileManager.default.removeItem(at: folder)

    var settings = Settings()
    settings.showRunningUnpinned = false
    settings.showTrash = false
    settings.showAppsMenu = false
    let model = DockModel(
        persistence: persistence, running: RunningAppsService(), settings: settings,
        isMountPoint: { _ in false })
    #expect(!model.items.contains { $0.displayName == "Photos" })

    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    model.rebuild()
    #expect(model.items.contains { $0.displayName == "Photos" && $0.isPinned })
    #expect(model.pinnedItems == [stored])
}
