import AppKit
import Testing
@testable import Eskele

private let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
private let desktop = URL(fileURLWithPath: "/Users/me/Desktop")
private let report = desktop.appendingPathComponent("Report.pdf")

private func operation(
    _ sources: [URL], into folder: URL = downloads, mask: NSDragOperation = .every, sameVolume: Bool = true
) -> FolderDrop.Operation? {
    FolderDrop.operation(for: sources, into: folder, mask: mask, sameVolume: sameVolume)
}

// MARK: - Move or copy

@Test func theSameVolumeMoves() {
    #expect(operation([report]) == .move)
}

@Test func anotherVolumeCopies() {
    #expect(operation([report], sameVolume: false) == .copy)
}

/// AppKit leaves only copy in the mask while ⌥ is held.
@Test func optionCopiesOnTheSameVolume() {
    #expect(operation([report], mask: .copy) == .copy)
}

/// …and only generic while ⌘ is held, which Finder takes as a move even off the volume.
@Test func commandMovesFromAnotherVolume() {
    #expect(operation([report], mask: .generic, sameVolume: false) == .move)
}

@Test func aSourceThatOnlyOffersCopyIsCopied() {
    #expect(operation([report], mask: [.copy, .link]) == .copy)
}

@Test func aSourceThatOffersNeitherIsRefused() {
    #expect(operation([report], mask: .link) == nil)
}

// MARK: - Nothing to do

@Test func aFolderCannotGoIntoItself() {
    #expect(operation([downloads]) == nil)
}

@Test func aFolderCannotGoIntoOneOfItsOwn() {
    let inner = downloads.appendingPathComponent("Archive", isDirectory: true)
    #expect(operation([downloads], into: inner) == nil)
}

/// A sibling whose name merely starts the same way is not inside it.
@Test func aSimilarlyNamedFolderIsNotInside() {
    let sibling = URL(fileURLWithPath: "/Users/me/Downloads Old")
    #expect(operation([downloads], into: sibling) == .move)
}

@Test func filesAlreadyThereAreRefused() {
    #expect(operation([downloads.appendingPathComponent("a.zip")]) == nil)
}

/// One file already there does not stop the others; `FileMover` passes over that one.
@Test func aMixedDropStillGoes() {
    #expect(operation([downloads.appendingPathComponent("a.zip"), report]) == .move)
}

/// The folder's URL may end in a slash where the file's parent does not, or the other way round.
@Test func aTrailingSlashDoesNotHideAFileAlreadyThere() {
    let bare = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: false)
    #expect(FolderDrop.isDirectly(downloads.appendingPathComponent("a.zip"), in: bare))
    #expect(FolderDrop.isDirectly(bare.appendingPathComponent("a.zip"), in: downloads))
}

// MARK: - Naming

@Test func aFreeNameIsKept() {
    #expect(FolderDrop.destination(for: report, in: downloads) { _ in false }
        == downloads.appendingPathComponent("Report.pdf"))
}

/// Finder's *Keep Both*: never replace, number the newcomer instead.
@Test func aTakenNameIsNumbered() {
    let taken: Set<String> = ["Report.pdf", "Report 2.pdf"]
    #expect(FolderDrop.destination(for: report, in: downloads) { taken.contains($0.lastPathComponent) }
        == downloads.appendingPathComponent("Report 3.pdf"))
}

@Test func aNameWithoutAnExtensionIsNumberedAtTheEnd() {
    let folder = desktop.appendingPathComponent("Photos")
    #expect(FolderDrop.destination(for: folder, in: downloads) { $0.lastPathComponent == "Photos" }
        == downloads.appendingPathComponent("Photos 2"))
}

@Test func anApplicationKeepsItsExtension() {
    let app = URL(fileURLWithPath: "/Volumes/Eskele/Eskele.app")
    #expect(FolderDrop.destination(for: app, in: downloads) { $0.lastPathComponent == "Eskele.app" }
        == downloads.appendingPathComponent("Eskele 2.app"))
}

// MARK: - On disk

/// The real round trip: one file moved in under a free name, one already there left alone, one
/// clashing name numbered.
@Test func filingMovesAndNumbersOnDisk() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("FolderDropTests-\(UUID().uuidString)")
        .resolvingSymlinksInPath()
    let source = root.appendingPathComponent("source")
    let folder = root.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try Data("new".utf8).write(to: source.appendingPathComponent("a.txt"))
    try Data("old".utf8).write(to: folder.appendingPathComponent("a.txt"))
    try Data("there".utf8).write(to: folder.appendingPathComponent("b.txt"))

    let failures = await FileMover.file(
        [source.appendingPathComponent("a.txt"), folder.appendingPathComponent("b.txt")],
        into: folder, operation: .move)

    #expect(failures.isEmpty)
    #expect(try String(contentsOf: folder.appendingPathComponent("a.txt"), encoding: .utf8) == "old")
    #expect(try String(contentsOf: folder.appendingPathComponent("a 2.txt"), encoding: .utf8) == "new")
    #expect(try String(contentsOf: folder.appendingPathComponent("b.txt"), encoding: .utf8) == "there")
    #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("a.txt").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("b 2.txt").path))
}
