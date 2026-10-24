import AppKit

/// On-disk form of a pinned item.
///
/// Both a bookmark and a bundle identifier are stored: the bookmark survives the app being moved or
/// renamed, the bundle ID survives the bookmark going stale (e.g. reinstalled from a fresh download).
struct PersistedItem: Codable, Equatable {
    enum Kind: String, Codable { case app, folder, file, separator }

    var kind: Kind
    var bundleID: String?
    var bookmark: Data?
    var path: String?
    var name: String?
    /// A name the user typed, which wins over `name`.
    ///
    /// Deliberately a second field rather than overwriting `name`: `name` is what the thing was
    /// called when it was pinned, and keeping the two apart is what lets an app that is renamed on
    /// disk follow its new name unless somebody has said otherwise.
    var customName: String?
    /// How a folder's stack is sorted, when the user has picked something other than
    /// `StackSort.defaultOrder` — nil otherwise, so a folder left alone keeps following its default.
    var stackSort: StackSort?
    var token: String?

    static func separator() -> PersistedItem {
        PersistedItem(kind: .separator, token: UUID().uuidString)
    }

    static func make(for url: URL) -> PersistedItem? {
        // An application bundle macOS will not launch is mapped onto the installed copy of the same
        // app first, so it is stored as the app it is rather than as a folder — see
        // `ApplicationURL`. Anything that is not an application bundle passes through untouched.
        let url = ApplicationURL.normalised(url)
        let bookmark = try? url.bookmarkData(options: [.minimalBookmark])
        if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
           url.pathExtension == "app" {
            return PersistedItem(
                kind: .app,
                bundleID: id,
                bookmark: bookmark,
                path: url.path,
                name: FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
            )
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return PersistedItem(
            kind: isDirectory.boolValue ? .folder : .file,
            bookmark: bookmark,
            path: url.path,
            name: url.lastPathComponent
        )
    }

    /// Bookmark first, then bundle ID, then the recorded path. Returns nil when the item is simply
    /// gone, which the caller treats as "drop it from the layout".
    func resolveURL() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        if let path, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    var identity: String {
        switch kind {
        case .app: "app:\(bundleID ?? path ?? "")"
        case .folder: "folder:\(path ?? "")"
        case .file: "file:\(path ?? "")"
        case .separator: "sep:\(token ?? "")"
        }
    }
}

struct Layout: Codable, Equatable {
    var version: Int = 1
    var items: [PersistedItem] = []

    init(version: Int = 1, items: [PersistedItem] = []) {
        self.version = version
        self.items = items
    }

    /// Decodes item by item and drops the ones that fail.
    ///
    /// Losing one pinned entry to a schema change is a nuisance; losing the whole arrangement is the
    /// kind of thing that makes someone stop using an app.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1

        var decoded: [PersistedItem] = []
        if var array = try? container.nestedUnkeyedContainer(forKey: .items) {
            while !array.isAtEnd {
                if let item = try? array.decode(PersistedItem.self) {
                    decoded.append(item)
                } else if (try? array.decode(SkippedElement.self)) == nil {
                    // Cannot even skip the element: the array is unreadable from here on.
                    break
                }
            }
        }
        items = decoded
    }
}

/// Consumes one element of an unkeyed container without inspecting it, so a failed decode can be
/// stepped over — a throwing `decode` does not advance the container's index.
private struct SkippedElement: Decodable {
    init(from decoder: Decoder) throws {}
}

extension PersistedItem {
    /// Whether this pin lives on a disk that is not mounted, and so cannot be told from one whose
    /// target is gone — only the disk coming back can say which.
    ///
    /// Read off the stored path: `/Volumes/<name>/…` with nothing mounted at `/Volumes/<name>`. A
    /// pin that fails to resolve anywhere else, or under a disk that *is* mounted, really has gone.
    /// Bookmarks are resolved without mounting, so a disk that is not there resolves to nothing
    /// however good the bookmark, and without this its pins were dropped from the layout for good
    /// the first time the bar was rebuilt with it unplugged.
    func awaitsVolume(isMountPoint: (String) -> Bool) -> Bool {
        guard let path, let mountPoint = Self.volumeMountPoint(of: path) else { return false }
        return !isMountPoint(mountPoint)
    }

    /// `/Volumes/<name>` for a path on a disk mounted there, nil for a path anywhere else.
    static func volumeMountPoint(of path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else { return nil }
        return "/Volumes/" + components[2]
    }

    /// Whether a volume is mounted at exactly `path`. A folder left behind in `/Volumes` by a disk
    /// that went without unmounting cleanly is on the startup disk, and is not one.
    static func isMountPoint(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let volume = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume else { return false }
        return volume.standardizedFileURL.path == url.standardizedFileURL.path
    }
}
