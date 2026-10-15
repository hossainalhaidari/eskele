import Foundation

/// The pure half of reading a shared file list — `.sfl4` on macOS 27, `.sfl3` and `.sfl2` before
/// it: the bookmarks in it, in order.
///
/// A shared file list is a keyed archive. Its layout is undocumented, and the classes it names have
/// changed between versions, so this does not unarchive it — an unarchiver refuses any class it
/// does not know, and one renamed class would empty every list. It reads the archive as the plain
/// property list it is and collects each data object that is a bookmark, by the `book` magic every
/// `URL.bookmarkData()` starts with. A keyed archiver appends each object to `$objects` the first
/// time it encodes it, depth first, so the bookmarks come out in the order of the list they belong
/// to — most recent first, as measured on TextEdit's list. See §5.30.
enum SharedFileList {
    /// What every bookmark starts with.
    static let bookmarkMagic = Data("book".utf8)

    static func bookmarks(in archive: Data) -> [Data] {
        guard let plist = try? PropertyListSerialization.propertyList(from: archive, format: nil),
              let root = plist as? [String: Any],
              let objects = root["$objects"] as? [Any]
        else { return [] }
        return objects.compactMap { object in
            guard let data = object as? Data, data.starts(with: bookmarkMagic) else { return nil }
            return data
        }
    }

    /// The list file for an app, from the directory's file names.
    ///
    /// Each list is named after the app's bundle identifier, lowercased, with an extension that
    /// counts the format's versions — measured on macOS 27: `com.apple.textedit.sfl4`, beside
    /// `.sfl3` lists other apps last wrote under an older macOS. So any `.sfl` and a number will do,
    /// the highest winning, and the match ignores case in case the lowercasing ever stops.
    static func listName(forBundleID bundleID: String, among names: [String]) -> String? {
        let prefix = bundleID.lowercased() + ".sfl"
        return names
            .compactMap { name -> (String, Int)? in
                let lowered = name.lowercased()
                guard lowered.hasPrefix(prefix), let version = Int(lowered.dropFirst(prefix.count)) else {
                    return nil
                }
                return (name, version)
            }
            .max { $0.1 < $1.1 }?.0
    }
}
