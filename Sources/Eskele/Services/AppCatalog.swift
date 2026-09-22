import AppKit

struct CatalogEntry: Equatable, Sendable {
    /// What choosing the row does.
    ///
    /// The launcher started out as a list of applications and could assume every row was a bundle to
    /// launch. A settings pane is a URL to hand to the workspace, and a power action has no file
    /// behind it at all, so the row has to carry its own verb.
    enum Action: Equatable, Sendable {
        case launch(URL)
        /// Handed to the workspace: a folder to open in Finder, or a settings pane's deep link.
        case open(URL)
        case power(PowerAction)
    }

    var action: Action
    var name: String
    /// Only meaningful for the All Apps list, which is the only one that groups.
    var category: AppCategory = .other
    /// Drawn when there is no file to take an icon from.
    var symbolName: String?

    /// The file behind the row, where there is one — for its icon, and for anything that needs a
    /// path. Nil for a power action, which is the point of `Action` being an enum.
    var url: URL? {
        switch action {
        case .launch(let url), .open(let url): url
        case .power: nil
        }
    }

    /// The overwhelmingly common case: an application to launch.
    init(url: URL, name: String, category: AppCategory = .other) {
        self.init(action: .launch(url), name: name, category: category)
    }

    init(action: Action, name: String, category: AppCategory = .other, symbolName: String? = nil) {
        self.action = action
        self.name = name
        self.category = category
        self.symbolName = symbolName
    }
}

/// Finds installed applications for the launcher.
///
/// Deliberately a plain directory scan rather than Launch Services: `LSCopyApplicationURLsForBundleIdentifier`
/// and friends answer "what can open this?", not "what has the user installed?", and the metadata
/// query alternative needs Spotlight to be enabled. Scanning four folders is fast and always works.
enum AppCatalog {
    /// Ordered so that a user's own copy shadows a system one of the same name.
    static var defaultRoots: [URL] {
        var roots: [URL] = []
        if let userApps = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(userApps)
        }
        roots.append(URL(fileURLWithPath: "/Applications"))
        roots.append(URL(fileURLWithPath: "/System/Applications"))
        // The user-facing half of CoreServices — Keychain Access, Wireless Diagnostics, About This
        // Mac. The folder *above* it is the system's agent zoo: scanning that turned up 39 bundles
        // here, of which two were apps anyone would launch.
        roots.append(URL(fileURLWithPath: "/System/Library/CoreServices/Applications"))
        return roots
    }

    /// Apps that belong in the list but live nowhere worth scanning.
    static let defaultExtras = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]

    /// Scans each root plus one level of subdirectories — enough to pick up Utilities — and never
    /// descends into a bundle, which is itself a directory.
    static func scan(
        roots: [URL] = AppCatalog.defaultRoots,
        extras: [URL] = AppCatalog.defaultExtras,
        fileManager: FileManager = .default
    ) -> [CatalogEntry] {
        var seen: Set<String> = []
        var entries: [CatalogEntry] = []

        for url in roots.flatMap({ applications(in: $0, depth: 1, fileManager: fileManager) }) + extras {
            // Same bundle name in two roots is the same app; the earlier root wins.
            let key = url.lastPathComponent.lowercased()
            guard seen.insert(key).inserted else { continue }
            let info = bundleInfo(for: url)
            // A background agent is not something you launch. Skipping them is what keeps the
            // grouped list readable: they are the bulk of what has no category to group by.
            guard !info.isAgent else { continue }
            entries.append(CatalogEntry(
                url: url,
                name: displayName(for: url, fileManager: fileManager),
                category: info.category ?? fallbackCategory(for: url)))
        }

        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func applications(in root: URL, depth: Int, fileManager: FileManager) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [URL] = []
        for url in contents {
            if url.pathExtension == "app" {
                found.append(url)
            } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                found.append(contentsOf: applications(in: url, depth: depth - 1, fileManager: fileManager))
            }
        }
        return found
    }

    private static func displayName(for url: URL, fileManager: FileManager) -> String {
        let name = fileManager.displayName(atPath: url.path)
        // displayName keeps the extension when the Finder would hide it, depending on settings.
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// The Utilities folders are a category in everything but the metadata, and they are where the
    /// system's own tools live — without this, half of "Other" is Disk Utility and its neighbours.
    private static func fallbackCategory(for url: URL) -> AppCategory {
        url.deletingLastPathComponent().lastPathComponent == "Utilities" ? .utilities : .other
    }

    // MARK: - Bundle metadata

    private struct BundleInfo {
        var isAgent = false
        var category: AppCategory?
    }

    /// Reads `Contents/Info.plist` directly rather than through `Bundle`, which would load and cache
    /// a hundred-odd bundles for two keys. An unreadable plist means an ordinary app with no
    /// category — never a reason to drop something from the list.
    private static func bundleInfo(for url: URL) -> BundleInfo {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let keys = plist as? [String: Any]
        else { return BundleInfo() }

        return BundleInfo(
            isAgent: flag(keys["LSUIElement"]) || flag(keys["LSBackgroundOnly"]),
            category: AppCategory.declared(keys["LSApplicationCategoryType"] as? String))
    }

    /// Both agent keys are documented as booleans and written in the wild as `1`, `"1"` and `"true"`.
    private static func flag(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: number.boolValue
        case let string as String: ["1", "true", "yes"].contains(string.lowercased())
        default: false
        }
    }
}

/// Keeps the scan off the main thread and hands back a cached list, so opening the launcher never
/// waits on the file system.
@MainActor
final class AppCatalogService {
    private(set) var entries: [CatalogEntry] = []
    /// Fired when a scan lands, so a launcher that opened mid-scan can fill itself in.
    var onChange: (() -> Void)?

    private var lastScan = Date.distantPast
    private var isScanning = false

    func refreshIfStale(maxAge: TimeInterval = 120) {
        guard !isScanning, Date().timeIntervalSince(lastScan) > maxAge else { return }
        isScanning = true
        Task {
            let scanned = await Task.detached(priority: .utility) { AppCatalog.scan() }.value
            self.entries = scanned
            self.lastScan = Date()
            self.isScanning = false
            self.onChange?()
        }
    }
}
