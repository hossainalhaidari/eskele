import AppKit

/// Icons the user has supplied, from `Icons/` in Eskele's support directory.
///
/// Named after the cell they replace — `com.apple.Safari.png`, `trash.png` — which is uBar's
/// convention and the only one that needs no interface: dropping a file into a folder is the whole
/// gesture. The folder is watched, so a file appearing, changing or being deleted shows on the bar
/// without a restart.
///
/// **Only the cells that have a name to be addressed by.** An app has a bundle identifier and the
/// Trash and the launcher have reserved words, but a folder or a file has only a path, which does
/// not fit in a filename. That is no loss: Finder's own Get Info ▸ paste-an-icon already overrides
/// those, and `NSWorkspace.icon(forFile:)` reads the result — so folders and files have a native
/// route to the same thing.
@MainActor
final class IconOverrideService {
    /// Override key → the file to draw. Empty when the folder is empty or missing.
    private(set) var files: [String: URL] = [:]
    var onChange: (() -> Void)?

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    /// What `NSImage` can read that anybody would plausibly hand us, best first. A key with several
    /// files takes the earliest — otherwise replacing `x.png` with `x.icns` would depend on which
    /// the file system happened to list first.
    nonisolated static let extensions = ["png", "icns", "tiff", "tif", "jpg", "jpeg", "heic", "pdf", "svg"]

    /// Reserved keys for the two cells that stand for no application.
    nonisolated static let trashKey = "trash"
    nonisolated static let appsMenuKey = "apps-menu"

    private static let debounce: TimeInterval = 0.2

    init(directory: URL) {
        self.directory = directory
        rescan()
        start()
    }

    deinit {
        source?.cancel()
    }

    func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    func url(for key: String) -> URL? {
        files[IconOverrideService.normalise(key)]
    }

    /// Creates the folder and drops a note in it explaining the naming, so "where do I put the file"
    /// is answered by opening the folder rather than by reading the README.
    func seedIfMissing() {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let note = """
            Drop an image in here to replace a cell's icon.

            Name it after the thing it replaces:

              com.apple.Safari.png      an app, by its bundle identifier
              \(IconOverrideService.trashKey).png                 the Trash
              \(IconOverrideService.appsMenuKey).png            the Apps Menu button

            Capitals do not matter. \(IconOverrideService.extensions.map { ".\($0)" }
                .joined(separator: " ")) all work; if a key has more \
            than one file the earliest of those wins. A square image looks best — anything else is \
            scaled to fit rather than cropped.

            Changes here show up on the bar straight away. Delete a file to get the real icon back.

            Pinned folders and files are not listed by name here, because a path is not a filename.
            They do not need to be: Finder's own Get Info ▸ paste-an-icon already overrides those,
            and Eskele draws whatever Finder reports.

            To find an app's bundle identifier:
              osascript -e 'id of app "Safari"'
            """
        try? note.write(
            to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Watching

    /// The same `O_EVTONLY` source `TrashWatcher` uses. A folder that does not exist yet cannot be
    /// opened, so it is polled for by the seed call rather than watched into existence.
    private func start() {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRescan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func scheduleRescan() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rescan() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IconOverrideService.debounce, execute: work)
    }

    func rescan() {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let next = IconOverrideService.map(entries)
        guard next != files else { return }
        files = next
        onChange?()
    }

    // MARK: - Naming

    /// Keys are compared case-insensitively. The file system is too, on a default macOS volume, so a
    /// `com.apple.safari.png` that silently did nothing would be a puzzle with no clue in it.
    nonisolated static func normalise(_ key: String) -> String {
        key.lowercased()
    }

    /// Picks one file per key, preferring the earliest listed extension.
    nonisolated static func map(_ entries: [URL]) -> [String: URL] {
        var result: [String: URL] = [:]
        var rank: [String: Int] = [:]
        for url in entries {
            let ext = url.pathExtension.lowercased()
            guard let position = extensions.firstIndex(of: ext) else { continue }
            let key = normalise(url.deletingPathExtension().lastPathComponent)
            guard !key.isEmpty else { continue }
            if let existing = rank[key], existing <= position { continue }
            rank[key] = position
            result[key] = url
        }
        return result
    }
}
