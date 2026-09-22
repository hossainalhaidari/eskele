import Foundation

/// Where a dragged cell lands in the orders the bar keeps.
///
/// Pure and separately tested, for the same reason `BarLayoutSolver` is: an off-by-one in a drag is
/// invisible until somebody drags something, and by then it has already scrambled their bar.
enum ReorderSolver {
    /// One movable thing and the visual index its run of cells begins at. An app split into window
    /// buttons occupies several cells but moves as one entry.
    struct Entry: Equatable {
        var id: String
        var start: Int

        init(id: String, start: Int) {
            self.id = id
            self.start = start
        }
    }

    /// Whether a drop at `index` counts as inside the run these cells occupy.
    ///
    /// The slot just past the last cell is inside: dropping at the far end of a group means "last",
    /// not "outside".
    static func contains(_ positions: [Int], index: Int) -> Bool {
        guard let first = positions.min(), let last = positions.max() else { return false }
        return index >= first && index <= last + 1
    }

    /// The group's ids with `id` moved to sit after every other entry whose run starts before the
    /// drop point.
    static func reordered(_ entries: [Entry], moving id: String, to index: Int) -> [String] {
        let target = entries.filter { $0.id != id && $0.start < index }.count
        var result = entries.map(\.id).filter { $0 != id }
        result.insert(id, at: min(max(0, target), result.count))
        return result
    }

    /// Maps a drop point in the visible strip onto a slot in the stored layout, by finding the
    /// nearest preceding cell that has one.
    ///
    /// Running-but-unpinned cells sit between pinned ones and have no stored slot, so positions
    /// cannot simply be counted. Every cell that *does* belong to a stored item has to be counted
    /// though — including the window buttons an app is split into, which is where this went wrong:
    /// each of those is one cell of the strip but none of them is a stored entry, so a drop just
    /// past a split app landed one slot short and read as a no-op.
    ///
    /// - Parameters:
    ///   - visualIdentities: the stored identity each visible cell maps to, in bar order. Cells with
    ///     no stored counterpart carry an identity that simply is not in `stored`.
    ///   - stored: the identities of the stored layout, in its own order.
    static func storedInsertionIndex(visualIdentities: [String], stored: [String], index: Int) -> Int {
        var lastStored = -1
        for visual in 0..<min(max(0, index), visualIdentities.count) {
            if let slot = stored.firstIndex(of: visualIdentities[visual]) { lastStored = slot }
        }
        return lastStored + 1
    }

    /// Moves one id inside a flat run of cells. `offset` is the drop index measured from the run's
    /// first cell, so it ranges over 0…count.
    static func moved(_ ids: [String], id: String, toOffset offset: Int) -> [String] {
        guard let current = ids.firstIndex(of: id) else { return ids }
        var result = ids
        var target = offset
        result.remove(at: current)
        if target > current { target -= 1 }
        result.insert(id, at: min(max(0, target), result.count))
        return result
    }
}
