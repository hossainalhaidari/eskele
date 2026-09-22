import Foundation

/// Watches the Trash and reports when its contents change.
///
/// Two mechanisms, because one of them is not always available. A `DispatchSource` on an
/// `O_EVTONLY` descriptor is the cheap, immediate route — but opening `~/.Trash` at all needs Full
/// Disk Access, and without it `open` fails with `EPERM` and the source can never be created. In
/// that case we fall back to polling the directory's `stat`, which macOS does allow, and which is
/// two syscalls every couple of seconds.
@MainActor
public final class TrashWatcher {
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var poll: Timer?
    private var stamp: Double?
    private let debounce: TimeInterval
    private let pollInterval: TimeInterval
    private let url: URL

    public private(set) var snapshot: TrashSnapshot
    /// Fires on any change to what the Trash holds — including a count that moves without the
    /// Trash becoming empty or non-empty, which the badge needs.
    public var onChange: ((TrashSnapshot) -> Void)?

    public var isEmpty: Bool { snapshot.isEmpty }

    /// True when we are polling because macOS would not let us watch the folder directly.
    public private(set) var isPolling = false

    /// Stops the poll while nobody can see the result — the displays asleep, say. Unpausing reads
    /// the Trash once straight away, so whatever changed in the meantime is not left waiting for the
    /// next tick. The watched route costs nothing while nothing happens, so this leaves it alone.
    public var isPaused = false {
        didSet {
            guard isPaused != oldValue, isPolling else { return }
            poll?.invalidate()
            poll = nil
            guard !isPaused else { return }
            schedulePoll()
            pollOnce()
        }
    }

    public init(url: URL = Trash.url, debounce: TimeInterval = 0.15, pollInterval: TimeInterval = 2.0) {
        self.url = url
        self.debounce = debounce
        self.pollInterval = pollInterval
        self.snapshot = Trash.read(at: url)
        self.stamp = Trash.modificationStamp(at: url)
        start()
    }

    deinit {
        source?.cancel()
    }

    /// Tears down the poll timer, which the run loop would otherwise keep alive on its own.
    public func stop() {
        poll?.invalidate()
        poll = nil
        source?.cancel()
        source = nil
    }

    private func start() {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            startPolling()
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    /// Only the directory's mtime is read on each tick; the contents are re-counted just when it
    /// moves, so a Trash nobody is touching costs one `stat` every couple of seconds.
    private func startPolling() {
        isPolling = true
        schedulePoll()
    }

    private func schedulePoll() {
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollOnce() }
        }
        timer.tolerance = pollInterval / 4
        poll = timer
    }

    private func pollOnce() {
        let current = Trash.modificationStamp(at: url)
        guard current != stamp else { return }
        stamp = current
        refresh()
    }

    private func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// Re-reads the Trash and notifies only when something the bar draws has actually changed.
    public func refresh() {
        let next = Trash.read(at: url)
        stamp = Trash.modificationStamp(at: url)
        guard next != snapshot else { return }
        snapshot = next
        onChange?(next)
    }
}
