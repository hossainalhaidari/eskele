import AppKit

/// Full-screen windows sitting on other Spaces, which Accessibility cannot see.
///
/// **Measured on macOS 26.6:** the AX API exposes only the windows of the *active* Space. An app with
/// a window in a full-screen Space of its own advertises one fewer window — VS Code with a normal
/// window and a full-screen one answered `1 returned, 1 advertised`, and its `AXChildren` held a
/// single `AXWindow`. Not a messaging timeout (a 2s one returned the same), not Electron's lazy
/// accessibility tree (`AXManualAccessibility` changed nothing), not the title filter. The window is
/// simply not in the tree, and no public API reaches across a Space boundary.
///
/// `CGWindowList` does see every Space, and needs no permission — but it cannot be trusted wholesale.
/// Measured on the same machine, its off-Space entries are mostly ghosts: cached panels and template
/// windows at 500×500, 800×600, 420×632, for apps whose real window count is zero. That is the same
/// over-reporting that ruled `CGWindowList` out for counting windows in the first place (§5.16).
///
/// One narrow slice of it *is* reliable: an off-Space, layer-0 window the size of a whole display.
/// None of the ghosts come close, and a merely zoomed window stops short of the menu bar — 874pt
/// against a full-screen window's 923pt on a 956pt display — so the two do not overlap.
@MainActor
final class SpaceWindowService {
    /// How many full-screen windows each app has parked on some other Space.
    private(set) var countsByPID: [pid_t: Int] = [:]
    var onChange: (() -> Void)?

    private var poll: Poll?
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// A window on another Space cannot change without a Space change or an app doing something, so
    /// this is a slow safety net rather than the primary signal.
    private static let interval: TimeInterval = 3

    /// How far short of a display's height a window may fall and still count as full-screen. A
    /// full-screen window gives up the menu bar's strip; a zoomed one gives up the menu bar *and*
    /// the Dock's, which is what puts it out of range.
    nonisolated static let heightTolerance: CGFloat = 48

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }

        poll = Poll(every: SpaceWindowService.interval, tolerance: 1) { [weak self] in self?.refresh() }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
    }

    func refresh() {
        let next = SpaceWindowService.scan(
            displays: NSScreen.screens.map(\.frame.size), excluding: ownPID)
        guard next != countsByPID else { return }
        countsByPID = next
        onChange?()
    }

    /// - Parameter displays: the sizes a full-screen window could have taken.
    nonisolated static func scan(displays: [CGSize], excluding ownPID: pid_t) -> [pid_t: Int] {
        let list = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? []
        var counts: [pid_t: Int] = [:]

        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  // On screen means it is on the Space we are looking at, where AX can see it.
                  (entry[kCGWindowIsOnscreen as String] as? Bool) != true,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  isDisplaySized(width: width, height: height, displays: displays)
            else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }

    /// Bounded on both sides. A floor alone would let a window that merely *exceeds* some display
    /// count as full-screen on it — which on a two-display setup means anything oversized on the
    /// large screen is read as full-screen on the small one.
    nonisolated static func isDisplaySized(width: CGFloat, height: CGFloat, displays: [CGSize]) -> Bool {
        displays.contains { display in
            abs(width - display.width) <= 2
                && height <= display.height + 2
                && height >= display.height - heightTolerance
        }
    }
}
