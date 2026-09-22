import AppKit
import Darwin
import Testing
@testable import Eskele

// MARK: - The unit trap

/// `ri_user_time` is documented as nanoseconds and is not: it is in mach absolute time units, which
/// *are* nanoseconds on Intel — the timebase there is 1/1 — and are not on Apple Silicon, where it
/// is 125/3. Taking the field at its word made a saturated core read as 2.4% instead of 100%: low,
/// but not obviously broken, and invisible to any test that only checks the arithmetic.
///
/// `mach_absolute_time` and `CLOCK_UPTIME_RAW` measure the same clock in the two different units, so
/// converting one has to land on the other. That is the ground truth, on either architecture, and it
/// needs no processor time to establish — an earlier version of this test burned a core for a second
/// and starved the filesystem-event tests running alongside it.
@Test func machTicksAreConvertedToRealNanoseconds() {
    let ticks = mach_absolute_time()
    let nanoseconds = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let converted = ActivityService.nanoseconds(fromMachTicks: ticks)

    // The two readings are a few hundred nanoseconds apart at worst; a wrong timebase is out by a
    // factor of tens.
    let drift = abs(Double(converted) - Double(nanoseconds))
    #expect(drift < 1_000_000, "converted \(converted)ns against \(nanoseconds)ns")
    #expect(converted > 0)
}

@Test func theConversionIsProportional() {
    let one = ActivityService.nanoseconds(fromMachTicks: 1_000_000)
    let ten = ActivityService.nanoseconds(fromMachTicks: 10_000_000)
    #expect(one > 0)
    #expect(abs(Double(ten) - Double(one) * 10) <= Double(ten) * 0.000_001)
    #expect(ActivityService.nanoseconds(fromMachTicks: 0) == 0)
}

// MARK: - The other half of the same trap

/// Nanoseconds over *seconds* is a figure a billion times too large. One core saturated for one
/// second is 100%, and two cores' worth is 200 — Activity Monitor's convention, not a 0…100 scale.
@Test func aSaturatedCoreForOneSecondIsOneHundredPercent() {
    #expect(ActivityService.percentage(cpuDelta: 1_000_000_000, elapsed: 1) == 100)
    #expect(ActivityService.percentage(cpuDelta: 500_000_000, elapsed: 1) == 50)
    // Half a second of wall clock, a full second of processor time: two cores.
    #expect(ActivityService.percentage(cpuDelta: 1_000_000_000, elapsed: 0.5) == 200)
    #expect(ActivityService.percentage(cpuDelta: 0, elapsed: 1) == 0)
}

/// The first sample of a chord has no predecessor, so there is no interval to divide by. Reporting
/// zero would be a claim; nil is the truth, and the cell shows a dash.
@Test func noElapsedTimeMeansNoFigureRatherThanZero() {
    #expect(ActivityService.percentage(cpuDelta: 1_000_000_000, elapsed: 0) == nil)
    #expect(ActivityService.percentage(cpuDelta: 0, elapsed: -1) == nil)
}

// MARK: - Sampling

/// Sampling is meant to cost nothing while nobody is holding the keys.
@MainActor
@Test func nothingIsSampledUntilItIsSwitchedOn() {
    let service = ActivityService()
    #expect(service.samples.isEmpty)
    service.setEnabled(false, pids: [ProcessInfo.processInfo.processIdentifier])
    #expect(service.samples.isEmpty)
}

/// The first sample reports memory and leaves processor use unknown, because there is nothing yet to
/// subtract from. Read live, because the point is that a real process answers at all.
@MainActor
@Test func theFirstSampleHasMemoryButNoProcessorFigure() {
    let me = ProcessInfo.processInfo.processIdentifier
    let service = ActivityService()
    service.setEnabled(true, pids: [me])

    let sample = try! #require(service.samples[me], "rusage refused this process")
    #expect(sample.cpu == nil)
    #expect(sample.memory > 0)

    // Switching off forgets everything, so a stale figure cannot be drawn next time.
    service.setEnabled(false)
    #expect(service.samples.isEmpty)
}
