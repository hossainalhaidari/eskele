import Foundation
import Testing
@testable import Eskele

private func entries(_ titles: [String], shortcuts: Set<String> = []) -> [RecentDocuments.Entry] {
    titles.map { RecentDocuments.Entry(title: $0, hasShortcut: shortcuts.contains($0)) }
}

/// AppKit's own shape: the documents, a separator, *Clear Menu*.
@Test func theDocumentsAreWhatComesBeforeClearMenu() {
    let menu = entries(["Report.pages", "Budget.numbers", "", "Clear Menu"])
    #expect(RecentDocuments.documentIndices(in: menu) == [0, 1])
}

/// An empty list is *Clear Menu* alone — what TextEdit and Preview showed on a Mac whose Recent
/// Items setting keeps none.
@Test func anEmptyListHasNothing() {
    #expect(RecentDocuments.documentIndices(in: entries(["Clear Menu"])).isEmpty)
    #expect(RecentDocuments.documentIndices(in: []).isEmpty)
}

/// Xcode's projects and files, separated, are both documents.
@Test func groupsBeforeTheLastSeparatorStayIn() {
    let menu = entries(["Eskele.xcodeproj", "", "main.swift", "", "Clear Menu"])
    #expect(RecentDocuments.documentIndices(in: menu) == [0, 2])
}

/// Measured on VS Code: a command with a shortcut heads the list and *More…* closes it.
@Test func commandsInTheListAreLeftOut() {
    let menu = entries(
        ["Reopen Closed Editor", "", "~/Projects/eskele", "~/Downloads/run.sh", "More…", "", "Clear Recently Opened"],
        shortcuts: ["Reopen Closed Editor"])
    #expect(RecentDocuments.documentIndices(in: menu) == [2, 3])
}

@Test func threeDotsCountAsAnEllipsisToo() {
    #expect(RecentDocuments.documentIndices(in: entries(["Notes.txt", "More...", "", "Clear Menu"])) == [0])
}

@Test func theLocalisedTitleJoinsTheEnglishOne() {
    #expect(RecentDocuments.menuTitles(localized: "Benutzte Dokumente") == ["Open Recent", "Benutzte Dokumente"])
    #expect(RecentDocuments.menuTitles(localized: nil) == ["Open Recent"])
    #expect(RecentDocuments.menuTitles(localized: "") == ["Open Recent"])
}
