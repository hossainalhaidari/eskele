import Foundation

public enum TrashError: Error, LocalizedError {
    case scriptFailed(String)
    case notPermitted

    public var errorDescription: String? {
        switch self {
        case .scriptFailed(let message): "Could not empty the Trash: \(message)"
        case .notPermitted: "Eskele needs permission to control Finder in order to empty the Trash."
        }
    }
}

/// What the Trash currently holds.
///
/// `isExact` records how we know: a real directory listing, or the metadata estimate we fall back on
/// when macOS refuses to let us read the folder. The estimate is good enough to badge and to pick an
/// icon, but it is not something to build an "empty N items?" confirmation on.
public struct TrashSnapshot: Equatable, Sendable {
    public var count: Int
    public var isExact: Bool

    public init(count: Int, isExact: Bool) {
        self.count = count
        self.isExact = isExact
    }

    public var isEmpty: Bool { count == 0 }

    public static let empty = TrashSnapshot(count: 0, isExact: true)
}

public enum Trash {
    public static var url: URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }

    /// Ignores the housekeeping files Finder leaves behind so an "empty" Trash reads as empty.
    static let ignoredNames: [String] = [".DS_Store", ".localized"]

    /// APFS stores a directory as a fixed header plus one fixed-size record per entry, and counts
    /// every entry — files included — in `st_nlink`. Both numbers therefore yield the entry count,
    /// and agreeing with each other is what tells us the assumption holds on this volume.
    private static let directoryHeader = 64
    private static let directoryRecord = 32

    /// How many items the Trash holds, and how sure we are of it.
    ///
    /// **Reading `~/.Trash` needs Full Disk Access.** Without it `contentsOfDirectory` fails outright
    /// — which is what used to make the Trash read as permanently empty, since a failed listing and
    /// an empty one were the same answer. `stat`, however, is not gated: the directory's own metadata
    /// still gives us the entry count, and individual children can still be probed by name, so the
    /// housekeeping files can be subtracted exactly as a listing would.
    public static func read(at url: URL = Trash.url) -> TrashSnapshot {
        if let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
            return TrashSnapshot(count: names.filter { !ignoredNames.contains($0) }.count, isExact: true)
        }
        guard let estimate = metadataCount(at: url) else { return .empty }
        return TrashSnapshot(count: estimate, isExact: false)
    }

    public static func isEmpty(at url: URL = Trash.url) -> Bool { read(at: url).isEmpty }

    public static func itemCount(at url: URL = Trash.url) -> Int { read(at: url).count }

    /// Cheap change detector for the polling watcher: the directory's mtime moves whenever an entry
    /// is added or removed, and reading it costs one `stat`.
    public static func modificationStamp(at url: URL = Trash.url) -> Double? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
    }

    /// Entry count derived from the directory's own metadata, or nil when this volume does not lay
    /// directories out the way we assume.
    ///
    /// Public because it is the whole answer on a machine without Full Disk Access, and because a
    /// number this load-bearing should be testable against a directory we *can* list.
    public static func metadataCount(at url: URL) -> Int? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return nil }

        let byLinks = Int(info.st_nlink) - 2
        let size = Int(info.st_size)
        let bySize: Int? = size >= directoryHeader && (size - directoryHeader) % directoryRecord == 0
            ? (size - directoryHeader) / directoryRecord
            : nil
        // Only trust the number when both readings agree. On a volume where they do not — HFS+
        // counts subdirectories alone in st_nlink — we would rather say nothing than guess.
        guard let entries = bySize, entries == byLinks else { return nil }
        guard entries > 0 else { return 0 }

        let housekeeping = ignoredNames.filter { name in
            var child = stat()
            return stat(url.appendingPathComponent(name).path, &child) == 0
        }.count
        return max(0, entries - housekeeping)
    }

    /// Moves items to the Trash the way Finder does, preserving "Put Back".
    ///
    /// Deliberately not `removeItem`: that ignores the user's confirmation setting, cannot be undone,
    /// and does not understand other volumes' `.Trashes`.
    @discardableResult
    public static func moveToTrash(_ urls: [URL]) -> [(URL, Error)] {
        var failures: [(URL, Error)] = []
        for url in urls {
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            } catch {
                failures.append((url, error))
            }
        }
        return failures
    }

    /// There is no public API to empty the Trash, so we ask Finder.
    ///
    /// Requires `NSAppleEventsUsageDescription` and, under Hardened Runtime, the
    /// `com.apple.security.automation.apple-events` entitlement. The first call raises the system
    /// Automation consent prompt; a refusal surfaces as `.notPermitted` so the caller can fall back
    /// to simply opening the Trash in Finder.
    @MainActor
    public static func empty() throws {
        let source = "tell application \"Finder\" to empty trash"
        guard let script = NSAppleScript(source: source) else {
            throw TrashError.scriptFailed("could not compile the Finder script")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743 = user has not authorised Automation for this app.
            if code == -1743 { throw TrashError.notPermitted }
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "error \(code)"
            throw TrashError.scriptFailed(message)
        }
    }
}
