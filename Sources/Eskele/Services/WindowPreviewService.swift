import AppKit
import ScreenCaptureKit

/// Thumbnails of live windows, for the hover tooltip.
///
/// The only feature in Eskele that costs Screen Recording, so it is off by default and every path
/// through here answers `nil` rather than prompting when the permission is not there. Without it the
/// tooltip is exactly what it has always been: the window's title, in text.
///
/// ScreenCaptureKit rather than the older `CGWindowListCreateImage`, which is deprecated and, since
/// Sonoma, returns a placeholder for windows it will not hand over.
@MainActor
final class WindowPreviewService {
    /// Longest edge of a thumbnail. Big enough to recognise a document at a glance, small enough
    /// that the capture and the scaling are both cheap.
    private static let maximumEdge: CGFloat = 320
    /// How long a capture stands in for the live window.
    ///
    /// A preview is a glance, not a monitor: re-capturing on every hover of the same cell would pay
    /// the full cost to show a picture the user just saw. Two seconds is short enough that a window
    /// you switched to and back is current again.
    private static let captureLifetime: TimeInterval = 2
    /// `SCShareableContent` enumerates every window on the system, which is far too expensive to ask
    /// for once per hover. Re-read no more often than this.
    private static let contentLifetime: TimeInterval = 1.5

    private var cache: [String: (image: NSImage, taken: Date)] = [:]
    private var content: (windows: [SCWindow], taken: Date)?

    var isAvailable: Bool { PermissionsService.screenRecordingStatus == .granted }

    /// - Returns: a thumbnail of the window, or `nil` if the permission is missing, the window
    ///   cannot be found, or the capture fails. Every one of those is a reason to fall back to text
    ///   rather than to report an error the user can do nothing about mid-hover.
    func preview(for reference: WindowRef) async -> NSImage? {
        guard isAvailable else { return nil }

        let key = reference.id
        if let hit = cache[key], Date().timeIntervalSince(hit.taken) < WindowPreviewService.captureLifetime {
            return hit.image
        }

        guard let window = await match(reference) else { return nil }
        guard let image = await capture(window) else { return nil }

        prune()
        cache[key] = (image, Date())
        return image
    }

    /// Drops thumbnails nobody is going to ask for again, so a long session does not accumulate one
    /// bitmap per window ever hovered.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-WindowPreviewService.captureLifetime)
        cache = cache.filter { $0.value.taken > cutoff }
    }

    /// Finds the live window a reference names.
    ///
    /// Matched on owning process and title, which is all a `WindowRef` carries — it is identified by
    /// title precisely because macOS exposes no stable window id through Accessibility. Where two
    /// windows of one app share a title, `duplicateIndex` picks between them in the same order the
    /// bar numbered them.
    private func match(_ reference: WindowRef) async -> SCWindow? {
        let windows = await shareableWindows()
        let fallback = NSRunningApplication(processIdentifier: reference.pid)?.localizedName ?? "Window"
        let candidates = windows.filter { window in
            window.owningApplication?.processID == reference.pid
                && ((window.title ?? "").isEmpty ? fallback : window.title ?? "") == reference.title
        }
        guard !candidates.isEmpty else { return nil }
        return candidates[min(reference.duplicateIndex, candidates.count - 1)]
    }

    private func shareableWindows() async -> [SCWindow] {
        if let content, Date().timeIntervalSince(content.taken) < WindowPreviewService.contentLifetime {
            return content.windows
        }
        do {
            // Off-screen windows included: a minimised window, or one on another Space, is exactly
            // the case where a picture tells you something the bar cannot.
            let available = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: false)
            content = (available.windows, Date())
            return available.windows
        } catch {
            // Revoked permission arrives here as an error. Forget the stale list rather than serving
            // it, and let the caller fall back to text.
            content = nil
            return []
        }
    }

    private func capture(_ window: SCWindow) async -> NSImage? {
        // Scaled down to the thumbnail's longest edge, never up: a small palette should stay small
        // rather than be blown up into a blurry slab.
        let longest = max(window.frame.width, window.frame.height)
        let factor = longest > 0 ? min(1, WindowPreviewService.maximumEdge / longest) : 1
        let width = max(1, Int((window.frame.width * factor).rounded()))
        let height = max(1, Int((window.frame.height * factor).rounded()))

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.scalesToFit = true
        // Transparent corners rather than black ones behind a window's rounded shape.
        configuration.backgroundColor = .clear

        let filter = SCContentFilter(desktopIndependentWindow: window)
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
            return NSImage(cgImage: image, size: NSSize(width: width, height: height))
        } catch {
            return nil
        }
    }
}
