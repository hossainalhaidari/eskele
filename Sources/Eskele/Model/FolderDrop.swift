import AppKit

/// What dropping files on a pinned folder does: Finder's rules, as the system Dock follows them.
///
/// Until this, a drop on a folder cell pinned the files beside it — the folder did not count as a
/// target at all. The rules are Finder's because the Dock's are: the same volume moves and another
/// volume copies, ⌥ copies and ⌘ moves whatever the volume. AppKit already turns those keys into
/// the drag's operation mask — ⌥ leaves only copy, ⌘ only generic — so the mask is all this asks.
/// See §5.31.
enum FolderDrop {
    enum Operation: Equatable { case move, copy }

    /// What the drop does, or nil when there is nothing it could sensibly do.
    ///
    /// - Parameter sources: what is being dragged, standardised.
    /// - Parameter folder: the pinned folder, standardised.
    /// - Parameter mask: the drag's source operation mask, modifiers already applied.
    /// - Parameter sameVolume: whether every source is on the folder's volume.
    static func operation(
        for sources: [URL], into folder: URL, mask: NSDragOperation, sameVolume: Bool
    ) -> Operation? {
        guard !sources.isEmpty, !sources.contains(where: { contains($0, folder) }) else { return nil }
        // Every file already in the folder: a move would be a no-op and a copy a duplicate nobody
        // asked for by dropping a file where it already is.
        guard sources.contains(where: { !isDirectly($0, in: folder) }) else { return nil }

        let copies = mask.contains(.copy)
        let moves = mask.contains(.move) || mask.contains(.generic)
        // ⌥: the mask is copy alone. ⌘: generic alone, which Finder takes as move.
        if copies && !moves { return .copy }
        if moves && !copies { return .move }
        guard copies || moves else { return nil }
        return sameVolume ? .move : .copy
    }

    /// Whether `url` sits in `folder` itself, not deeper. By components: `URL`'s own equality
    /// compares the string, and a directory URL may or may not end in a slash.
    static func isDirectly(_ url: URL, in folder: URL) -> Bool {
        url.deletingLastPathComponent().pathComponents == folder.pathComponents
    }

    /// Whether `folder` is `source` or lies inside it — a folder cannot go into itself.
    static func contains(_ source: URL, _ folder: URL) -> Bool {
        let parent = source.pathComponents
        let child = folder.pathComponents
        return child.count >= parent.count && Array(child.prefix(parent.count)) == parent
    }

    /// Where `source` lands in `folder`: under its own name, or Finder's *Keep Both* name when that
    /// is taken — `Report 2.pdf`, `Report 3.pdf`. Nothing is ever replaced: Finder would ask first,
    /// and a bar has nowhere good to ask from in the middle of a drop.
    static func destination(for source: URL, in folder: URL, exists: (URL) -> Bool) -> URL {
        let name = source.lastPathComponent
        let candidate = folder.appendingPathComponent(name)
        guard exists(candidate) else { return candidate }

        let ext = source.pathExtension
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var number = 2
        while true {
            let numbered = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            let url = folder.appendingPathComponent(numbered)
            if !exists(url) { return url }
            number += 1
        }
    }
}
