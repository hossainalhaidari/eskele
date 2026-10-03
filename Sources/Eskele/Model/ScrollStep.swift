import CoreGraphics

/// Turns scrolling on a cell into steps through the app's windows: +1 for the next window, -1 for
/// the one before.
///
/// Pure, because the two devices that scroll disagree about everything and the rules are worth
/// asserting rather than finding out with a trackpad. A mouse wheel sends one event per notch, and
/// each notch is a step. A trackpad sends a stream of small deltas and then a momentum tail after
/// the fingers lift; that is one gesture, and one gesture is one step — a swipe that raced through
/// five windows would leave you on one you never saw. The momentum tail is ignored outright: it is
/// the trackpad's animation, not the user's hand.
struct ScrollStep: Equatable {
    /// How far a trackpad has to travel before a gesture counts, in points. Enough that resting
    /// fingers or a swipe that changes its mind do nothing.
    static let threshold: CGFloat = 12

    enum Phase: Equatable {
        /// A mouse wheel notch, or any device without phases.
        case wheel
        /// Fingers touched down — a new gesture.
        case began
        case changed
        /// Fingers lifted, or the gesture was cancelled.
        case ended
        /// The trackpad's coasting after the fingers lifted.
        case momentum
    }

    private var travel: CGFloat = 0
    private var hasStepped = false

    /// - Parameter delta: how far, with up — the wheel rolled away from you, or fingers moving up
    ///   the pad — positive whatever the user's scroll direction setting. See `physicalDelta`.
    /// - Returns: +1, -1, or 0 for no step.
    mutating func step(delta: CGFloat, phase: Phase) -> Int {
        switch phase {
        case .wheel:
            return delta > 0 ? 1 : delta < 0 ? -1 : 0
        case .momentum:
            return 0
        case .began:
            travel = 0
            hasStepped = false
            return 0
        case .ended:
            travel = 0
            hasStepped = false
            return 0
        case .changed:
            guard !hasStepped else { return 0 }
            travel += delta
            guard abs(travel) >= ScrollStep.threshold else { return 0 }
            hasStepped = true
            return travel > 0 ? 1 : -1
        }
    }

    /// The scroll as the hand moved, undoing *natural scrolling*: with it on, fingers moving up
    /// report a negative delta, because the content goes up. The direction should not flip with a
    /// setting that is about moving content — there is no content here.
    static func physicalDelta(_ delta: CGFloat, invertedFromDevice: Bool) -> CGFloat {
        invertedFromDevice ? -delta : delta
    }
}
