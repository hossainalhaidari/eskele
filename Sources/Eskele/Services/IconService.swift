import AppKit

/// Supplies each item's own icon, sized for the bar.
///
/// No recolouring or tinting: we show exactly what the app ships. The work here is entirely about
/// keeping a 1024px `.icns` crisp when drawn at ~24pt.
@MainActor
final class IconService {
    static let shared = IconService()

    private let cache = NSCache<NSString, NSImage>()

    /// Files the user has dropped into `Icons/`, by override key. Pushed in rather than looked up so
    /// this stays a renderer with no opinion about where the folder is or when it changed.
    private var overrides: [String: URL] = [:]

    init() { cache.countLimit = 512 }

    func setOverrides(_ overrides: [String: URL]) {
        guard overrides != self.overrides else { return }
        self.overrides = overrides
        // The cache is keyed by the *source* file, so a key that has just gained or lost an override
        // would otherwise keep serving whichever icon it was built with.
        clear()
    }

    /// - Parameter key: what an override file for this cell would be named — see
    ///   `DockItem.iconOverrideKey`. Nil for a cell no file can address.
    func icon(for url: URL, key: String?, pointSize: CGFloat, scale: CGFloat) -> NSImage {
        if let custom = override(for: key, pointSize: pointSize, scale: scale) { return custom }
        let px = pixelSize(pointSize: pointSize, scale: scale)
        // The mtime in the key means an app update invalidates its own entry — no explicit
        // invalidation logic, and no stale icon after an upgrade.
        let key = "\(url.path)|\(px)|\(modificationStamp(of: url))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let source = NSWorkspace.shared.icon(forFile: url.path)
        let rendered = render(source, pointSize: pointSize, px: px)
        cache.setObject(rendered, forKey: key)
        return rendered
    }

    /// The empty/full pair Finder itself uses. Falls back to SF Symbols if the system resources
    /// ever move.
    func trashIcon(isEmpty: Bool, pointSize: CGFloat, scale: CGFloat) -> NSImage {
        if let custom = override(
            for: IconOverrideService.trashKey, pointSize: pointSize, scale: scale) {
            return custom
        }
        let px = pixelSize(pointSize: pointSize, scale: scale)
        let key = "trash|\(isEmpty)|\(px)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let name = isEmpty ? "TrashIcon" : "FullTrashIcon"
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(name).icns"
        let source = NSImage(contentsOfFile: path)
            ?? NSImage(systemSymbolName: isEmpty ? "trash" : "trash.fill", accessibilityDescription: "Trash")
            ?? NSImage()
        let rendered = render(source, pointSize: pointSize, px: px)
        cache.setObject(rendered, forKey: key)
        return rendered
    }

    /// The launcher glyph. Unlike everything else in the bar this is our own chrome rather than
    /// somebody's app icon, so it is a template symbol tinted to match the menu bar's text — and
    /// therefore has to be re-rendered when the effective appearance flips.
    func appsMenuIcon(pointSize: CGFloat, scale: CGFloat, appearance: NSAppearance) -> NSImage {
        // A supplied glyph is drawn as supplied — it is a picture the user chose, not chrome of
        // ours, so it keeps its own colours instead of being tinted to the menu bar's text.
        if let custom = override(
            for: IconOverrideService.appsMenuKey, pointSize: pointSize, scale: scale) {
            return custom
        }
        let px = pixelSize(pointSize: pointSize, scale: scale)
        let key = "apps-menu|\(px)|\(appearance.name.rawValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize * 0.78, weight: .medium)
        let symbol = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Apps")?
            .withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Apps")
            ?? NSImage()

        var tint = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance { tint = NSColor.labelColor }

        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let box = NSRect(
                x: rect.midX - symbol.size.width / 2,
                y: rect.midY - symbol.size.height / 2,
                width: symbol.size.width,
                height: symbol.size.height)
            symbol.draw(in: box)
            tint.set()
            // sourceAtop keeps the glyph's own alpha and replaces its colour.
            box.fill(using: .sourceAtop)
            return true
        }

        cache.setObject(image, forKey: key)
        return image
    }

    func clear() { cache.removeAllObjects() }

    /// The user's own icon for a cell, rendered exactly like a real one — same cache, same
    /// downscale-never-upscale rule, same mtime in the key so replacing the file takes effect.
    ///
    /// Nil for a file `NSImage` cannot read, which is what makes a stray text file in the folder
    /// harmless rather than a blank cell.
    private func override(for key: String?, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
        guard let key, let url = overrides[IconOverrideService.normalise(key)] else { return nil }
        let px = pixelSize(pointSize: pointSize, scale: scale)
        let cacheKey = "override|\(url.path)|\(px)|\(modificationStamp(of: url))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        guard let source = NSImage(contentsOf: url), source.isValid, source.size.width > 0 else {
            return nil
        }
        let rendered = render(source, pointSize: pointSize, px: px)
        cache.setObject(rendered, forKey: cacheKey)
        return rendered
    }

    // MARK: - Rendering

    private func pixelSize(pointSize: CGFloat, scale: CGFloat) -> Int {
        max(1, Int((pointSize * scale).rounded()))
    }

    private func modificationStamp(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = attributes?[.modificationDate] as? Date
        return Int((date?.timeIntervalSince1970 ?? 0).rounded())
    }

    /// Rasterise once, at exactly the pixel size we will draw at, so nothing resamples per frame.
    private func render(_ source: NSImage, pointSize: CGFloat, px: Int) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return source }

        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            let rect = NSRect(x: 0, y: 0, width: pointSize, height: pointSize)
            if let best = bestRepresentation(of: source, forPixelSize: px) {
                best.draw(in: rect)
            } else {
                source.draw(in: rect)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(rep)
        return image
    }

    /// Smallest representation at or above the target, so we always downscale.
    ///
    /// Upscaling the 32px representation is the classic blurry-dock-icon bug. Returns nil when the
    /// image does not expose usable representations (some system icons are drawn dynamically), in
    /// which case AppKit picks for itself against our high-resolution context.
    private func bestRepresentation(of image: NSImage, forPixelSize px: Int) -> NSImageRep? {
        let usable = image.representations.filter { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
        guard usable.count > 1 else { return nil }
        let atOrAbove = usable.filter { $0.pixelsWide >= px }.min { $0.pixelsWide < $1.pixelsWide }
        return atOrAbove ?? usable.max { $0.pixelsWide < $1.pixelsWide }
    }
}
