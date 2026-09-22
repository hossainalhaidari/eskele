import Foundation

/// A heading in the launcher's grouped All Apps list.
///
/// The only categorisation a Mac application carries is `LSApplicationCategoryType`, the key the App
/// Store requires. Coverage is therefore partial — Apple's own bundles mostly omit it, and so do
/// plenty of direct downloads — so a folder fallback claims the Utilities folders and everything
/// left over lands in ``other``, which sorts last so the groups that mean something stay at the top.
struct AppCategory: Hashable, Sendable, Comparable {
    var title: String
    /// The bucket for apps that declare nothing. It belongs at the end of the list, not under "O".
    var isCatchAll = false
    /// Not applications at all — settings panes, folders, the power actions. These sort after every
    /// app category, so a list that has always opened on applications still does.
    var isSystem = false
    /// Order among the system sections, which are placed deliberately rather than alphabetically —
    /// that would put Power between Folders and System Settings. Ignored for applications.
    var systemOrder = 0

    static let other = AppCategory(
        title: String(localized: "Other", comment: "Launcher heading for apps that declare no category"),
        isCatchAll: true)
    static let utilities = AppCategory(
        title: String(localized: "Utilities", comment: "Launcher heading, Apple's own category name"))
    static let systemSettings = AppCategory(
        title: String(localized: "System Settings", comment: "Launcher heading for preference panes"),
        isSystem: true, systemOrder: 0)
    static let folders = AppCategory(
        title: String(localized: "Folders", comment: "Launcher heading for the common folders"),
        isSystem: true, systemOrder: 1)
    /// Last, so the row that shuts the machine down is the furthest from everything you reach for
    /// by accident.
    static let power = AppCategory(
        title: String(localized: "Power", comment: "Launcher heading for Sleep, Log Out, Restart, Shut Down"),
        isSystem: true, systemOrder: 2)

    /// Applications first, then the ones that declared no category, then everything that is not an
    /// application.
    private var rank: Int {
        if isSystem { return 2 }
        return isCatchAll ? 1 : 0
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        if lhs.isSystem, rhs.isSystem, lhs.systemOrder != rhs.systemOrder {
            return lhs.systemOrder < rhs.systemOrder
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

extension AppCategory {
    private static let prefix = "public.app-category."

    /// Apple's published titles, which are not simply the identifier spelled out — `graphics-design`
    /// is "Graphics & Design", `healthcare-fitness` is "Health & Fitness".
    ///
    /// macOS knows these names in every language it ships, but exposes them nowhere a process can
    /// read, so they are translated here like any other string. Built once, on first use.
    private static let titles: [String: String] = [
        "books": String(localized: "Books", comment: "App category"),
        "business": String(localized: "Business", comment: "App category"),
        "developer-tools": String(localized: "Developer Tools", comment: "App category"),
        "education": String(localized: "Education", comment: "App category"),
        "entertainment": String(localized: "Entertainment", comment: "App category"),
        "finance": String(localized: "Finance", comment: "App category"),
        "food-and-drink": String(localized: "Food & Drink", comment: "App category"),
        "graphics-design": String(localized: "Graphics & Design", comment: "App category"),
        "healthcare-fitness": String(localized: "Health & Fitness", comment: "App category"),
        "lifestyle": String(localized: "Lifestyle", comment: "App category"),
        "medical": String(localized: "Medical", comment: "App category"),
        "music": String(localized: "Music", comment: "App category"),
        "navigation": String(localized: "Navigation", comment: "App category"),
        "news": String(localized: "News", comment: "App category"),
        "photography": String(localized: "Photography", comment: "App category"),
        "productivity": String(localized: "Productivity", comment: "App category"),
        "reference": String(localized: "Reference", comment: "App category"),
        "shopping": String(localized: "Shopping", comment: "App category"),
        "social-networking": String(localized: "Social Networking", comment: "App category"),
        "sports": String(localized: "Sports", comment: "App category"),
        "travel": String(localized: "Travel", comment: "App category"),
        "utilities": String(localized: "Utilities", comment: "Launcher heading, Apple's own category name"),
        "video": String(localized: "Video", comment: "App category"),
        "weather": String(localized: "Weather", comment: "App category"),
    ]

    /// - Returns: `nil` when the bundle declares no category, so the caller can try its own fallback
    ///   before giving up and using ``other``.
    static func declared(_ identifier: String?) -> AppCategory? {
        guard let identifier, identifier.hasPrefix(prefix) else { return nil }
        let key = String(identifier.dropFirst(prefix.count))
        guard !key.isEmpty else { return nil }
        // There are nineteen game genres and no user wants nineteen headings of one app each.
        if key == "games" || key.hasSuffix("-games") {
            return AppCategory(title: String(localized: "Games", comment: "App category"))
        }
        if let title = titles[key] { return AppCategory(title: title) }
        // A category invented after this ships still reads correctly rather than falling to "Other".
        let title = key.split(separator: "-").map(\.capitalized).joined(separator: " ")
        return AppCategory(title: title)
    }
}
