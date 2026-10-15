import Foundation

/// Carries out a drop on a pinned folder, off the main thread — a copy from a disk image can take
/// as long as the application in it is large, and the bar must not stop for it.
enum FileMover {
    struct Failure: Sendable {
        let name: String
        let reason: String
    }

    /// Moves or copies each source into the folder, under a free name, and says what went wrong.
    ///
    /// A source already in the folder is passed over rather than moved onto itself or duplicated —
    /// `FolderDrop` refuses a drop made only of those, but a mixed one still gets here.
    static func file(
        _ sources: [URL], into folder: URL, operation: FolderDrop.Operation
    ) async -> [Failure] {
        await Task.detached(priority: .userInitiated) {
            let manager = FileManager()
            var failures: [Failure] = []
            for source in sources.map({ $0.resolvingSymlinksInPath() })
            where !FolderDrop.isDirectly(source, in: folder) {
                let target = FolderDrop.destination(for: source, in: folder) {
                    manager.fileExists(atPath: $0.path)
                }
                do {
                    switch operation {
                    case .move: try manager.moveItem(at: source, to: target)
                    case .copy: try manager.copyItem(at: source, to: target)
                    }
                } catch {
                    failures.append(Failure(name: source.lastPathComponent, reason: error.localizedDescription))
                }
            }
            return failures
        }.value
    }
}
