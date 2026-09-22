import AppKit

/// Progress for files being written into the folders the bar shows.
///
/// **Why folders and not applications.** `Progress.addSubscriber(forFileURL:)` is public, costs no
/// permission at all, and genuinely works across processes — measured on macOS 26.6, a progress
/// published by one process arrives in another with its fraction, its operation kind and its
/// localised description. What it does *not* carry is who published it. There is no bundle
/// identifier, no process id, nothing that names the application doing the copying. So a download
/// cannot be put on the downloading app's tile, and Eskele puts it where it can honestly be
/// attributed instead: on the cell for the folder the file is landing in.
///
/// That is also why this is not the answer to "show me what the Dock shows". An app's own Dock tile
/// progress is drawn by that app into its `NSDockTile`, which nothing else can read — the same wall
/// `BadgeService` documents for badges.
///
/// **Subscriptions match one URL exactly.** Subscribing to a directory reports nothing about the
/// files inside it (measured — the handler is never called). So each folder is watched for changes
/// and every file that looks like it is being written gets its own subscription.
@MainActor
final class FileProgressService {
    /// Fraction per folder path, for the folders that have something happening in them.
    private(set) var reports: [String: ProgressReport] = [:]
    var onChange: (() -> Void)?

    /// The folders to watch. Set from the bar's own folder cells: a folder nobody put on the bar has
    /// no cell to draw a bar on, so watching it would be work for nothing.
    var folders: [URL] = [] {
        didSet {
            guard folders.map(\.path) != oldValue.map(\.path) else { return }
            resync()
        }
    }

    private struct Watch {
        var source: DispatchSourceFileSystemObject?
        var descriptor: Int32
    }

    /// One live `NSProgress` we are observing, and the handle that stops observing it.
    private struct Subscription {
        var token: Any
        var observation: NSKeyValueObservation?
        var fraction: Double?
        var describedAs: String?
    }

    private var watches: [String: Watch] = [:]
    /// Keyed by file path. A file is subscribed at most once however many folders list it.
    private var subscriptions: [String: Subscription] = [:]
    /// Which folder each subscribed file belongs to.
    private var owners: [String: String] = [:]
    private var rescan: DispatchWorkItem?

    /// How recently a file must have been touched to be worth a subscription. A folder full of old
    /// downloads is the common case, and subscribing to every one of them would be hundreds of
    /// registrations for files nothing is writing.
    private static let recentWindow: TimeInterval = 90
    /// Ceiling on live subscriptions per folder, so a directory that is being unpacked into does not
    /// turn into a thousand of them.
    private static let maximumPerFolder = 24
    private static let debounce: TimeInterval = 0.2

    deinit {
        for watch in watches.values {
            watch.source?.cancel()
        }
    }

    func stop() {
        rescan?.cancel()
        for path in Array(subscriptions.keys) { unsubscribe(path) }
        for watch in watches.values { watch.source?.cancel() }
        watches.removeAll()
        folders = []
        publish([:])
    }

    // MARK: - Watching

    private func resync() {
        let wanted = Set(folders.map(\.path))
        for (path, watch) in watches where !wanted.contains(path) {
            watch.source?.cancel()
            watches.removeValue(forKey: path)
        }
        for folder in folders where watches[folder.path] == nil {
            watches[folder.path] = watch(folder)
        }
        // A file already being written when the folder was added is one nothing will notify us
        // about, so the first scan is immediate rather than waiting for the next change.
        scan()
    }

    /// The same `O_EVTONLY` source `TrashWatcher` uses. A folder we cannot open is simply not
    /// watched — it will be picked up by the next scan if it becomes readable.
    private func watch(_ folder: URL) -> Watch {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return Watch(source: nil, descriptor: -1) }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return Watch(source: source, descriptor: descriptor)
    }

    private func scheduleScan() {
        rescan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        rescan = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + FileProgressService.debounce, execute: work)
    }

    /// Subscribes to the files that look like something is writing them, and lets go of the rest.
    private func scan() {
        var wanted: [String: String] = [:]      // file path → folder path
        for folder in folders {
            for file in candidates(in: folder) {
                wanted[file.path] = folder.path
            }
        }

        for path in Array(subscriptions.keys) where wanted[path] == nil {
            unsubscribe(path)
        }
        for (path, folder) in wanted where subscriptions[path] == nil {
            subscribe(path, folder: folder)
        }
        recompute()
    }

    private func candidates(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        let cutoff = Date().addingTimeInterval(-FileProgressService.recentWindow)
        return entries
            .filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory != true else { return false }
                guard let modified = values?.contentModificationDate else { return false }
                return modified >= cutoff
            }
            .prefix(FileProgressService.maximumPerFolder)
            .map { $0 }
    }

    // MARK: - Subscriptions

    private func subscribe(_ path: String, folder: String) {
        owners[path] = folder
        // The publishing handler is documented to run on the main queue, but a hop costs nothing and
        // makes that an assumption we do not have to be right about.
        let token = Progress.addSubscriber(forFileURL: URL(fileURLWithPath: path)) {
            [weak self] published in
            let describedAs = published.localizedDescription
            let observation = published.observe(\.fractionCompleted) { progress, _ in
                let fraction = progress.fractionCompleted
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.record(fraction, describedAs: describedAs, for: path) }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.attach(observation, to: path)
                    self?.record(published.fractionCompleted, describedAs: describedAs, for: path)
                }
            }
            return {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.record(nil, describedAs: nil, for: path) }
                }
            }
        }
        subscriptions[path] = Subscription(token: token, observation: nil)
    }

    private func attach(_ observation: NSKeyValueObservation, to path: String) {
        guard subscriptions[path] != nil else {
            observation.invalidate()
            return
        }
        subscriptions[path]?.observation?.invalidate()
        subscriptions[path]?.observation = observation
    }

    private func unsubscribe(_ path: String) {
        guard let subscription = subscriptions.removeValue(forKey: path) else { return }
        subscription.observation?.invalidate()
        Progress.removeSubscriber(subscription.token)
        owners.removeValue(forKey: path)
    }

    /// A `nil` fraction means the publisher went away — the operation finished, or its app quit.
    private func record(_ fraction: Double?, describedAs: String?, for path: String) {
        guard subscriptions[path] != nil else { return }
        subscriptions[path]?.fraction = fraction
        subscriptions[path]?.describedAs = describedAs
        recompute()
    }

    private func recompute() {
        var active: [String: [(fraction: Double, describedAs: String?)]] = [:]
        for (path, subscription) in subscriptions {
            guard let fraction = subscription.fraction, let folder = owners[path] else { continue }
            active[folder, default: []].append((fraction, subscription.describedAs))
        }

        var next: [String: ProgressReport] = [:]
        for (folder, entries) in active where !entries.isEmpty {
            // The mean, not the first: two files copying into one folder are one job as far as the
            // cell is concerned, and a bar that tracked whichever happened to be first would jump
            // backwards when that one finished.
            let mean = entries.reduce(0) { $0 + $1.fraction } / Double(entries.count)
            let detail = entries.count == 1
                ? entries[0].describedAs
                : "\(entries.count) file operations"
            next[folder] = ProgressReport(kind: .file, fraction: mean, detail: detail)
        }
        publish(next)
    }

    private func publish(_ next: [String: ProgressReport]) {
        guard next != reports else { return }
        reports = next
        onChange?()
    }
}
