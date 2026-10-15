import Foundation
import Testing
@testable import Eskele

/// Real files with real bookmarks, in a folder that goes away afterwards.
private struct Scratch {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedFileListTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func file(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// A keyed archive laid out as the shared file lists are believed to be: a dictionary of items,
/// each a dictionary carrying its bookmark, beside a dictionary of list properties. The real
/// format is unverified (§5.30), which is why the reader depends on none of this shape.
/// Paths as one spelling: a resolved bookmark says `/private/var` where the temporary directory
/// says `/var`.
private func paths(_ urls: [URL]) -> [String] { urls.map { $0.resolvingSymlinksInPath().path } }

private func archive(_ bookmarks: [Data]) throws -> Data {
    let items = bookmarks.map { bookmark -> NSDictionary in
        ["Bookmark": bookmark, "uuid": UUID().uuidString, "visibility": 0,
         "CustomItemProperties": ["com.apple.LSSharedFileList.ItemIsHidden": false]]
    }
    let root: NSDictionary = ["items": items, "properties": ["com.apple.LSSharedFileList.MaxAmount": 10]]
    return try NSKeyedArchiver.archivedData(withRootObject: root, requiringSecureCoding: false)
}

@Test func bookmarksComeOutInListOrder() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let urls = try ["c.txt", "a.txt", "b.txt"].map(scratch.file)
    let bookmarks = try urls.map { try $0.bookmarkData() }

    #expect(SharedFileList.bookmarks(in: try archive(bookmarks)) == bookmarks)
    #expect(paths(RecentDocumentLists.resolve(SharedFileList.bookmarks(in: try archive(bookmarks)))) == paths(urls))
}

/// Every bookmark starts the same way, which is how they are told from the other data in a list.
@Test func everyBookmarkStartsWithTheMagic() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(try scratch.file("x").bookmarkData().starts(with: SharedFileList.bookmarkMagic))
}

@Test func otherDataInTheArchiveIsIgnored() throws {
    let root: NSDictionary = ["items": [["Bookmark": Data("not a bookmark".utf8)]]]
    let data = try NSKeyedArchiver.archivedData(withRootObject: root, requiringSecureCoding: false)
    #expect(SharedFileList.bookmarks(in: data).isEmpty)
}

@Test func somethingThatIsNotAnArchiveHasNothing() {
    #expect(SharedFileList.bookmarks(in: Data()).isEmpty)
    #expect(SharedFileList.bookmarks(in: Data("book, but not a plist".utf8)).isEmpty)
}

/// A document deleted or moved out of reach drops out rather than becoming an entry that fails.
@Test func aDocumentThatIsGoneIsLeftOut() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let kept = try scratch.file("kept.txt")
    let gone = try scratch.file("gone.txt")
    let bookmarks = try [gone, kept].map { try $0.bookmarkData() }
    try FileManager.default.removeItem(at: gone)
    #expect(paths(RecentDocumentLists.resolve(bookmarks)) == paths([kept]))
}

@Test func theSameDocumentTwiceIsListedOnce() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let file = try scratch.file("twice.txt")
    #expect(paths(RecentDocumentLists.resolve([try file.bookmarkData(), try file.bookmarkData()])) == paths([file]))
}

@Test func aLongListIsCut() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let bookmarks = try (0..<(RecentDocumentLists.limit + 5)).map { try scratch.file("\($0).txt").bookmarkData() }
    #expect(RecentDocumentLists.resolve(bookmarks).count == RecentDocumentLists.limit)
}

// MARK: - Finding the list

@Test func theListIsFoundWhateverItsCase() {
    let names = ["com.apple.textedit.sfl3", "com.microsoft.vscode.sfl3"]
    #expect(SharedFileList.listName(forBundleID: "com.apple.TextEdit", among: names) == "com.apple.textedit.sfl3")
    #expect(SharedFileList.listName(forBundleID: "com.microsoft.VSCode", among: names) == "com.microsoft.vscode.sfl3")
}

@Test func theCurrentFormatWinsOverAnOlderOne() {
    let names = ["com.apple.Preview.sfl2", "com.apple.Preview.sfl3"]
    #expect(SharedFileList.listName(forBundleID: "com.apple.Preview", among: names) == "com.apple.Preview.sfl3")
    #expect(SharedFileList.listName(forBundleID: "com.apple.Preview", among: ["com.apple.Preview.sfl2"])
        == "com.apple.Preview.sfl2")
}

/// One bundle identifier that is the start of another must not pick up the other's list.
@Test func aLongerBundleIdentifierIsNotAMatch() {
    #expect(SharedFileList.listName(forBundleID: "com.apple.Pages", among: ["com.apple.pages.beta.sfl3"]) == nil)
}

/// Measured on macOS 27: the lists are `.sfl4`, named in lower case, beside `.sfl3` lists no app has
/// written since an older macOS.
@Test func theNewestFormatWins() {
    let names = ["com.apple.textedit.sfl3", "com.apple.textedit.sfl4", "com.apple.texteditor.sfl4"]
    #expect(SharedFileList.listName(forBundleID: "com.apple.TextEdit", among: names) == "com.apple.textedit.sfl4")
}

/// A format after this one should not need a release to be found.
@Test func aFormatNotYetSeenIsFoundToo() {
    #expect(SharedFileList.listName(forBundleID: "com.apple.Pages", among: ["com.apple.pages.sfl5"])
        == "com.apple.pages.sfl5")
}

@Test func somethingElseAfterTheNameIsNotAList() {
    #expect(SharedFileList.listName(forBundleID: "com.apple.Pages", among: ["com.apple.pages.sfl4.bak"]) == nil)
}
