import Foundation
import Testing
@testable import Eskele

@MainActor
private func wait(upTo seconds: Double = 5, until condition: @MainActor () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// The mechanism the whole file source rests on: a progress published for a file turns up on the
/// cell for the folder that file is in.
///
/// Worth an integration test rather than a unit one — the interesting part is whether macOS's
/// progress publishing actually reaches a subscriber, which no amount of testing our own arithmetic
/// would tell us.
@MainActor
@Test func aPublishedFileProgressLandsOnItsFolder() async throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-progress-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let file = folder.appendingPathComponent("big.zip")
    try Data("x".utf8).write(to: file)

    let service = FileProgressService()
    defer { service.stop() }
    service.folders = [folder]

    let published = Progress(parent: nil, userInfo: [
        .fileOperationKindKey: Progress.FileOperationKind.copying,
        .fileURLKey: file,
    ])
    published.kind = .file
    published.totalUnitCount = 100
    published.completedUnitCount = 40
    published.publish()
    defer { published.unpublish() }

    try await wait { service.reports[folder.path] != nil }
    let report = try #require(service.reports[folder.path])
    #expect(report.kind == .file)
    #expect(abs(report.fraction - 0.4) < 0.001)

    published.completedUnitCount = 90
    try await wait { (service.reports[folder.path]?.fraction ?? 0) > 0.5 }
    #expect(abs((service.reports[folder.path]?.fraction ?? 0) - 0.9) < 0.001)
}

/// A folder nobody put on the bar has no cell to draw on, so it is not watched at all.
@MainActor
@Test func onlyTheFoldersOnTheBarAreWatched() async throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("eskele-progress-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("big.zip")
    try Data("x".utf8).write(to: file)

    let service = FileProgressService()
    defer { service.stop() }

    let published = Progress(parent: nil, userInfo: [.fileURLKey: file])
    published.kind = .file
    published.totalUnitCount = 100
    published.completedUnitCount = 40
    published.publish()
    defer { published.unpublish() }

    try await Task.sleep(for: .milliseconds(400))
    #expect(service.reports.isEmpty)
}
