import AppKit

/// The **Add to Eskele** item in Finder's Services menu.
///
/// The other way to pin something is to drag it onto the bar, which needs the bar to be visible and
/// on the same screen as the Finder window you are dragging from. This one does not.
@MainActor
final class ServicesProvider: NSObject {
    /// The `NSMessage` value in `Info.plist`, from which macOS forms the selector
    /// `addToBar:userData:error:`.
    ///
    /// Declared here as well as in the plist because nothing checks that the two agree — a rename on
    /// either side leaves a menu item that silently does nothing. `ServicesTests` compares them.
    nonisolated static let messageName = "addToBar"

    /// Returns false when the item cannot be pinned: already on the bar, or gone by the time we
    /// look.
    var pin: ((URL) -> Bool)?

    @objc func addToBar(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = String(
                localized: "Eskele can only add files, folders and applications.",
                comment: "Services menu error when the selection is something the bar cannot pin") as NSString
            return
        }

        let added = urls.filter { pin?($0) == true }
        guard added.isEmpty else { return }

        // Every one refused. The overwhelmingly likely reason is that they are already pinned, and
        // saying so is more use than a generic failure — but a file that has just been deleted lands
        // here too, so the wording does not promise which.
        error.pointee = urls.count == 1
            ? "\(urls[0].lastPathComponent) is already on the bar." as NSString
            : String(
                localized: "Those items are already on the bar.",
                comment: "Services menu error when everything selected is pinned already") as NSString
    }
}
