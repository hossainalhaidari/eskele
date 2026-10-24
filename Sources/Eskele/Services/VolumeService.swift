import AppKit
import DiskArbitration
import IOKit

/// The disks, disk images and servers that are mounted, and ejecting them.
///
/// Driven entirely by the workspace's mount notifications, so it costs nothing while nothing is
/// plugged in or out: there is no timer to pause. The list itself is read off the main thread,
/// because asking a server that has gone away for its volume's name can block for as long as the
/// network takes to give up. See §5.32.
@MainActor
final class VolumeService {
    struct EjectError: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    private(set) var volumes: [MountedVolume] = []
    /// Paths of the volumes an eject is under way for. Flushing a stick's writes can take seconds,
    /// and a cell that sat there unchanged would look like the eject had been ignored.
    private(set) var ejecting: Set<String> = []
    var onChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    /// Bumped on every read, so a slow read that finishes after a newer one cannot overwrite it.
    private var generation = 0

    init() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        generation += 1
        let current = generation
        Task {
            let found = await Task.detached(priority: .utility) { VolumeService.scan() }.value
            guard current == self.generation, found != self.volumes else { return }
            self.volumes = found
            self.onChange?()
        }
    }

    /// The volume at `url`, if the bar would show it — for a disk dragged onto the Trash from
    /// Finder, which may not be on the bar at all.
    func volume(at url: URL) -> MountedVolume? {
        let path = url.standardizedFileURL.path
        return volumes.first { $0.url.standardizedFileURL.path == path } ?? MountedVolume(url: url)
    }

    nonisolated static func scan() -> [MountedVolume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: MountedVolume.resourceKeys,
            options: [.skipHiddenVolumes]) ?? []
        return MountedVolume.list(urls.compactMap(MountedVolume.init(url:)))
    }

    // MARK: - Ejecting

    /// Unmounts the volume and ejects the disk it is on, as Finder's Eject button does — every
    /// volume on that disk goes with it, since the disk cannot leave while any of them is mounted.
    func eject(_ volume: MountedVolume) async throws {
        try await whileEjecting(volume) {
            do {
                try await FileManager.default.unmountVolume(
                    at: volume.url, options: [.allPartitionsAndEjectDisk, .withoutUI])
            } catch {
                throw EjectError(reason: Self.reason(for: error))
            }
        }
    }

    /// Unmounts the volume whatever is still using it, then ejects its disk.
    ///
    /// For the alert after an eject was refused, as Finder offers. What was open on the disk loses
    /// whatever it had not written, which is why it is only ever a second step the user chooses.
    func forceEject(_ volume: MountedVolume) async throws {
        try await whileEjecting(volume) {
            try await Task.detached(priority: .userInitiated) {
                try DiskEjector.forceEject(volume.url)
            }.value
        }
    }

    private func whileEjecting(_ volume: MountedVolume, _ work: () async throws -> Void) async throws {
        let path = volume.url.path
        ejecting.insert(path)
        onChange?()
        defer {
            ejecting.remove(path)
            onChange?()
            // The unmount notification is usually here first, but a refused eject sends none and
            // the cell has to come back from looking busy.
            refresh()
        }
        try await work()
    }

    /// Who is holding the disk, when the refusal says — it carries the dissenting process, which
    /// is what Finder names in its own alert. Otherwise the system's sentence, which for a busy disk
    /// only repeats that it could not be ejected.
    private static func reason(for error: Error) -> String {
        let error = error as NSError
        if let pid = error.userInfo[NSFileManagerUnmountDissentingProcessIdentifierErrorKey] as? pid_t,
           let name = processName(pid) {
            return String(
                localized: "“\(name)” is using it.",
                comment: "Why a disk could not be ejected: the app or program that has it open")
        }
        return error.localizedDescription
    }

    /// An app's own name, or a background process's executable name.
    private static func processName(_ pid: pid_t) -> String? {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }
}

/// The DiskArbitration half of a forced eject. `FileManager` has no force option, and DiskArbitration
/// is what Finder's own *Force Eject* goes through.
private enum DiskEjector {
    /// Waits for each callback, since DiskArbitration reports on a queue of its own and this is
    /// already off the main thread.
    nonisolated static func forceEject(_ url: URL) throws {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL)
        else {
            throw VolumeService.EjectError(reason: String(
                localized: "The disk could not be found.",
                comment: "Force Eject failed because the disk had gone or could not be looked up"))
        }
        let queue = DispatchQueue(label: "de.alhaidari.eskele.eject")
        DASessionSetDispatchQueue(session, queue)
        defer { DASessionSetDispatchQueue(session, nil) }

        // Every volume on the disk, which only the whole disk can be asked for — the option on one of
        // its volumes is refused as unsupported. A server has no whole disk, and is unmounted alone.
        let whole = DADiskCopyWholeDisk(disk)
        let unmount = Outcome()
        DADiskUnmount(
            whole ?? disk,
            DADiskUnmountOptions(
                whole == nil ? kDADiskUnmountOptionForce : kDADiskUnmountOptionWhole | kDADiskUnmountOptionForce),
            { _, dissenter, context in Outcome.finish(context, dissenter) },
            Unmanaged.passUnretained(unmount).toOpaque())
        try unmount.wait()

        guard let whole else { return }
        let eject = Outcome()
        DADiskEject(
            physicalDisk(under: whole, session: session) ?? whole, DADiskEjectOptions(kDADiskEjectOptionDefault),
            { _, dissenter, context in Outcome.finish(context, dissenter) },
            Unmanaged.passUnretained(eject).toOpaque())
        // Unmounted is what was asked for; a device that will not then power down is no reason to
        // say the eject failed, since nothing on it can be reached any more.
        try? eject.wait()
    }

    /// The disk an APFS container sits on. The container is a whole disk of its own, synthesized
    /// by APFS, and ejecting it leaves the stick — or the disk image — it lives on attached; the
    /// real one is the nearest whole medium above it in the registry. Nil for a disk that is not a
    /// container, which has nothing above it but its driver.
    nonisolated private static func physicalDisk(under whole: DADisk, session: DASession) -> DADisk? {
        var entry = DADiskCopyIOMedia(whole)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        while true {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return nil
            }
            IOObjectRelease(entry)
            entry = parent
            guard IOObjectConformsTo(entry, "IOMedia") != 0,
                  let property = IORegistryEntryCreateCFProperty(
                    entry, "Whole" as CFString, kCFAllocatorDefault, 0),
                  property.takeRetainedValue() as? Bool == true
            else { continue }
            return DADiskCreateFromIOMedia(kCFAllocatorDefault, session, entry)
        }
    }

    /// One callback's result, handed from DiskArbitration's queue to the thread waiting for it.
    private final class Outcome: @unchecked Sendable {
        private let done = DispatchSemaphore(value: 0)
        private var failure: String?

        static func finish(_ context: UnsafeMutableRawPointer?, _ dissenter: DADissenter?) {
            guard let context else { return }
            let outcome = Unmanaged<Outcome>.fromOpaque(context).takeUnretainedValue()
            if let dissenter {
                // As DiskArbitration's own headers write its codes, 0xF8DA0002 and the rest; as a
                // signed decimal it is a long negative number that means nothing to anybody.
                let status = String(format: "0x%08X", UInt32(bitPattern: DADissenterGetStatus(dissenter)))
                outcome.failure = (DADissenterGetStatusString(dissenter) as String?)
                    ?? String(
                        localized: "The disk refused (error \(status)).",
                        comment: "Force Eject failed and the system gave only a code for why")
            }
            outcome.done.signal()
        }

        func wait() throws {
            // DiskArbitration answers in milliseconds, or seconds for a disk flushing its writes; a
            // minute without an answer is a disk that is not going to give one.
            guard done.wait(timeout: .now() + 60) == .success else {
                throw VolumeService.EjectError(reason: String(
                    localized: "The disk did not answer.",
                    comment: "Force Eject gave up waiting for the system to unmount the disk"))
            }
            if let failure { throw VolumeService.EjectError(reason: failure) }
        }
    }
}
