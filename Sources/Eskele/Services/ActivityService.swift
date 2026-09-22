import AppKit
import Darwin

/// Processor and memory use per app, sampled only while the activity overlay is held.
///
/// `proc_pid_rusage` rather than `task_info`: reading another process's task port needs an
/// entitlement Eskele does not have and could not justify, while rusage answers for any process the
/// same user owns and needs no permission at all. Measured here against every running app — none
/// refused.
@MainActor
final class ActivityService {
    private(set) var samples: [pid_t: ActivitySample] = [:]
    var onChange: (() -> Void)?

    /// Fast enough to watch a number move, slow enough that the sampling itself is not the load
    /// being reported.
    private static let interval: TimeInterval = 0.6

    private var timer: Timer?
    /// Cumulative processor time per app at the previous sample, and when it was taken.
    private var previous: [pid_t: UInt64] = [:]
    private var previousAt: Date?
    private var pids: [pid_t] = []

    /// - Parameter pids: the apps on the bar. Everything else on the system is somebody else's
    ///   business, and walking it would cost more than the answer is worth.
    func setEnabled(_ enabled: Bool, pids: [pid_t] = []) {
        self.pids = pids
        guard enabled != (timer != nil) else {
            if enabled { sample() }
            return
        }
        guard enabled else {
            timer?.invalidate()
            timer = nil
            previous = [:]
            previousAt = nil
            samples = [:]
            onChange?()
            return
        }

        // The first sample has no predecessor to subtract, so it reports memory and leaves processor
        // use unknown; the second, a moment later, fills it in.
        sample()
        let timer = Timer.scheduledTimer(withTimeInterval: ActivityService.interval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = ActivityService.interval / 4
        self.timer = timer
    }

    private func sample() {
        guard !pids.isEmpty else { return }
        let now = Date()
        let elapsed = previousAt.map { now.timeIntervalSince($0) } ?? 0
        let tree = ActivityService.descendants(of: Set(pids))

        var next: [pid_t: ActivitySample] = [:]
        var times: [pid_t: UInt64] = [:]
        for pid in pids {
            var cpuTime: UInt64 = 0
            var memory: UInt64 = 0
            var answered = false
            for member in tree[pid] ?? [pid] {
                guard let usage = ActivityService.usage(of: member) else { continue }
                answered = true
                cpuTime &+= usage.cpuTime
                memory &+= usage.footprint
            }
            guard answered else { continue }
            times[pid] = cpuTime

            var cpu: Double?
            // Only a delta over real elapsed time means anything. A process that has just appeared
            // has no previous total, so it waits one interval like everything else rather than
            // reporting its entire lifetime's work as though it happened in the last half second.
            if elapsed > 0, let before = previous[pid], cpuTime >= before {
                cpu = ActivityService.percentage(cpuDelta: cpuTime - before, elapsed: elapsed)
            }
            next[pid] = ActivitySample(cpu: cpu, memory: memory)
        }

        previous = times
        previousAt = now
        guard next != samples else { return }
        samples = next
        onChange?()
    }

    /// The machine's mach-tick to nanosecond ratio. Arithmetic over constants, so `nonisolated`:
    /// nothing here touches the sampler's state, and the conversion is worth testing on its own.
    ///
    /// **`ri_user_time` is documented as nanoseconds and is not.** It is in mach absolute time
    /// units, which happen to *be* nanoseconds on Intel — the timebase there is 1/1 — and are not on
    /// Apple Silicon, where it is 125/3. Measured: one saturated core read as 2.4% before this
    /// conversion and 100% after, which is exactly the 41.67 the timebase predicts. Code that looks
    /// correct on an Intel Mac is wrong by a factor of forty here.
    private nonisolated static let timebase: (numerator: UInt64, denominator: UInt64) = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return (1, 1) }
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    /// Processor time as a percentage of one core, the way Activity Monitor reports it — so a busy
    /// app can exceed 100.
    ///
    /// Both quantities have to be in the same unit before they are divided, which is the other half
    /// of the timebase trap: nanoseconds over *seconds* is a figure a billion times too large, and
    /// nanoseconds over nanoseconds is the answer.
    nonisolated static func percentage(cpuDelta: UInt64, elapsed: TimeInterval) -> Double? {
        guard elapsed > 0 else { return nil }
        return Double(cpuDelta) / (elapsed * 1_000_000_000) * 100
    }

    /// Mach absolute time units as nanoseconds.
    ///
    /// Split into whole and remainder rather than multiplying first: a long-running process's tick
    /// total times the numerator would be a much larger number than it needs to be, and there is no
    /// reason to go near the ceiling for it.
    nonisolated static func nanoseconds(fromMachTicks ticks: UInt64) -> UInt64 {
        ticks / timebase.denominator &* timebase.numerator
            &+ ticks % timebase.denominator &* timebase.numerator / timebase.denominator
    }

    /// Cumulative processor time in nanoseconds, and physical footprint in bytes.
    private static func usage(of pid: pid_t) -> (cpuTime: UInt64, footprint: UInt64)? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return nil }
        let ticks = info.ri_user_time &+ info.ri_system_time
        return (nanoseconds(fromMachTicks: ticks), info.ri_phys_footprint)
    }

    /// Each app's own process plus every process descended from it.
    ///
    /// An Electron app does its work in helper processes that are children of the app, so reading
    /// the app's own process alone reports a fraction of the truth — VS Code has nine of them.
    ///
    /// **Not everything can be attributed.** WebKit's content processes are started by launchd and
    /// have it as their parent, so Safari's tabs belong to no app as far as the process tree is
    /// concerned. macOS knows the real answer — that is what the "responsible process" is — but
    /// exposes it only through private API. Safari therefore reports its own process alone.
    private static func descendants(of roots: Set<pid_t>) -> [pid_t: [pid_t]] {
        var children: [pid_t: [pid_t]] = [:]
        for pid in allProcesses() {
            guard let parent = parent(of: pid), parent != pid else { continue }
            children[parent, default: []].append(pid)
        }

        var tree: [pid_t: [pid_t]] = [:]
        for root in roots {
            var found: [pid_t] = [root]
            var queue = children[root] ?? []
            // Bounded by the process table, and a cycle is impossible in a parent map — but a
            // corrupt read should not be able to hang the bar, so visits are counted anyway.
            var visited: Set<pid_t> = [root]
            while let next = queue.popLast() {
                guard visited.insert(next).inserted else { continue }
                found.append(next)
                queue.append(contentsOf: children[next] ?? [])
            }
            tree[root] = found
        }
        return tree
    }

    private static func allProcesses() -> [pid_t] {
        var size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.size)
        size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, size)
        guard size > 0 else { return [] }
        return pids.prefix(Int(size) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }
}
