import Foundation

/// How a pinned folder's stack lists what is inside it — the system Dock's *Sort by*.
///
/// Per folder rather than a setting, because the right order depends on the folder: Downloads wants
/// the newest file on top, a folder of projects wants them by name.
enum StackSort: String, Codable, CaseIterable {
    case name
    case dateAdded
    case dateModified
    case dateCreated
    case kind

    /// Lenient, so an order a later version added reads as the default here. A field that fails to
    /// decode fails the whole `PersistedItem`, and `Layout` drops an item that fails — the folder
    /// would vanish from the bar over how its contents are listed.
    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(StackSort.init(rawValue:)) ?? .name
    }

    /// The order a folder has until somebody picks one: newest first for Downloads, as the Dock
    /// does, and by name for everything else, as Finder does.
    static func defaultOrder(for folder: URL, downloads: URL? = StackSort.downloads) -> StackSort {
        guard let downloads else { return .name }
        return folder.standardizedFileURL.path == downloads.standardizedFileURL.path
            ? .dateAdded : .name
    }

    private static let downloads = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask).first

    var title: String {
        switch self {
        case .name: String(localized: "Name", comment: "Sort By choice for a folder stack")
        case .dateAdded: String(localized: "Date Added", comment: "Sort By choice for a folder stack")
        case .dateModified: String(localized: "Date Modified", comment: "Sort By choice for a folder stack")
        case .dateCreated: String(localized: "Date Created", comment: "Sort By choice for a folder stack")
        case .kind: String(localized: "Kind", comment: "Sort By choice for a folder stack")
        }
    }

    /// What the stack needs to know about one thing in the folder in order to place it.
    struct Entry: Equatable {
        var url: URL
        var isFolder: Bool
        var added: Date?
        var modified: Date?
        var created: Date?
        /// Finder's "Kind" column — "PDF document", "Folder" — in the user's language.
        var kind: String?

        var name: String { url.lastPathComponent }
    }

    /// The entries in this order.
    ///
    /// By name and by kind, folders come first, as Finder shows them. By a date they do not: the
    /// point of sorting Downloads by date added is that the thing that just arrived is on top, and a
    /// folder that arrived an hour ago is no exception. Dates run newest first, and an entry the
    /// file system gave no date goes last rather than being read as the oldest of all. Ties fall
    /// back to the name, so the order never depends on how the directory happened to list.
    func ordered(_ entries: [Entry]) -> [Entry] {
        entries.sorted { lhs, rhs in
            switch self {
            case .name:
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            case .kind:
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                let order = (lhs.kind ?? "").localizedStandardCompare(rhs.kind ?? "")
                if order != .orderedSame { return order == .orderedAscending }
            case .dateAdded:
                if let newer = StackSort.newerFirst(lhs.added, rhs.added) { return newer }
            case .dateModified:
                if let newer = StackSort.newerFirst(lhs.modified, rhs.modified) { return newer }
            case .dateCreated:
                if let newer = StackSort.newerFirst(lhs.created, rhs.created) { return newer }
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Whether `lhs` goes before `rhs`, or nil when the dates do not decide it.
    private static func newerFirst(_ lhs: Date?, _ rhs: Date?) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (nil, _): false
        case (_, nil): true
        case let (lhs?, rhs?): lhs == rhs ? nil : lhs > rhs
        }
    }
}
