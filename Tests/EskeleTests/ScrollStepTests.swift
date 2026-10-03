import CoreGraphics
import Testing
@testable import Eskele

/// Feeds a run of scroll events through one `ScrollStep` and collects the steps it answered with —
/// `#expect` cannot wrap a mutating call.
private func steps(_ events: [(CGFloat, ScrollStep.Phase)]) -> [Int] {
    var scroll = ScrollStep()
    return events.map { scroll.step(delta: $0.0, phase: $0.1) }
}

// MARK: - Mouse wheel

@Test func eachWheelNotchIsAStep() {
    #expect(steps([(1, .wheel), (1, .wheel), (-3, .wheel), (0, .wheel)]) == [1, 1, -1, 0])
}

// MARK: - Trackpad

@Test func aSwipeIsOneStepHoweverFarItGoes() {
    let swipe: [(CGFloat, ScrollStep.Phase)] = [
        (0, .began), (5, .changed), (10, .changed), (40, .changed), (80, .changed), (0, .ended),
    ]
    #expect(steps(swipe) == [0, 0, 1, 0, 0, 0])
}

@Test func aSwipeDownStepsBack() {
    #expect(steps([(0, .began), (-8, .changed), (-8, .changed), (0, .ended)]) == [0, 0, -1, 0])
}

/// Resting fingers, or a swipe that goes a little way and comes back, is not a request.
@Test func aSmallMovementDoesNothing() {
    #expect(steps([
        (0, .began), (6, .changed), (-4, .changed), (5, .changed), (0, .ended),
    ]).allSatisfy { $0 == 0 })
}

/// The coasting after the fingers lift is the trackpad's animation, not the hand.
@Test func momentumIsIgnored() {
    #expect(steps([
        (0, .began), (2, .changed), (0, .ended), (50, .momentum), (50, .momentum),
    ]).allSatisfy { $0 == 0 })
}

@Test func eachGestureStartsAfresh() {
    #expect(steps([
        (0, .began), (20, .changed), (0, .ended),
        (0, .began), (20, .changed), (20, .changed), (0, .ended),
    ]) == [0, 1, 0, 0, 1, 0, 0])
    // A gesture that never ended — fingers lifted off the cell — does not carry its travel over.
    #expect(steps([(0, .began), (10, .changed), (0, .began), (10, .changed)]) == [0, 0, 0, 0])
}

// MARK: - Direction

/// Natural scrolling flips the sign of the same hand movement; the step should not flip with it.
@Test func directionFollowsTheHandNotTheScrollSetting() {
    // Fingers moving up the pad: negative with natural scrolling on, positive with it off.
    #expect(ScrollStep.physicalDelta(-10, invertedFromDevice: true) == 10)
    #expect(ScrollStep.physicalDelta(10, invertedFromDevice: false) == 10)
}

// MARK: - Cycling

@Test func steppingWrapsBothWays() {
    #expect(WindowService.stepped(from: 2, by: 1, count: 3) == 0)
    #expect(WindowService.stepped(from: 0, by: -1, count: 3) == 2)
    #expect(WindowService.stepped(from: 1, by: -1, count: 3) == 0)
    #expect(WindowService.stepped(from: 0, by: -4, count: 3) == 2)
}
