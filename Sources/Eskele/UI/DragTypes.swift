import AppKit

extension NSPasteboard.PasteboardType {
    /// Internal reordering payload: the item's stable id.
    ///
    /// We deliberately do *not* also write `.fileURL` when dragging a cell. Doing so would let a
    /// drag that ends in a Finder window move the user's application bundle, which is never what
    /// dragging something out of a dock means.
    static let eskeleItem = NSPasteboard.PasteboardType("de.alhaidari.eskele.item")
}
