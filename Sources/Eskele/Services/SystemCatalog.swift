import AppKit

/// The Start-menu half of the launcher: System Settings panes, the folders everyone has, and the
/// power actions.
///
/// Everything here is searchable alongside the applications, which is the point — typing `displ`
/// should reach the Displays pane and `downl` the Downloads folder without first choosing a mode.
enum SystemCatalog {
    // MARK: - Settings panes

    /// Where System Settings keeps its panes on macOS 13 and later.
    static let extensionsDirectory = URL(
        fileURLWithPath: "/System/Library/ExtensionKit/Extensions")

    /// The extension point every System Settings pane declares, and nothing else does.
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    /// Panes, read from the extensions System Settings itself loads.
    ///
    /// Enumerated rather than hard-coded, so the list is right for whatever macOS this is. The older
    /// `/System/Library/PreferencePanes` route looks tempting and is not: on macOS 26 most of those
    /// bundles are empty stubs with no `Info.plist`, which yields names like
    /// "DesktopScreenEffectsPref" and entries for hardware nobody has had since 2016.
    ///
    /// Two of Apple's own flags do the filtering, so there is no denylist to rot:
    /// `allowsXAppleSystemPreferencesURLScheme` says the pane can be opened by URL at all, and a
    /// representation marked `hidden` is one System Settings does not show either — which is what
    /// takes out CDs & DVDs and ClassKit.
    static func settingsPanes(in directory: URL = extensionsDirectory) -> [CatalogEntry] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        return contents.compactMap { url -> CatalogEntry? in
            guard let bundle = Bundle(url: url),
                  let info = bundle.infoDictionary,
                  let identifier = info["CFBundleIdentifier"] as? String,
                  let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
                  let settings = attributes["SettingsExtensionAttributes"] as? [String: Any],
                  settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
                  !isHidden(settings),
                  let link = URL(string: "x-apple.systempreferences:\(identifier)")
            else { return nil }

            return CatalogEntry(
                action: .open(link),
                name: paneName(bundle: bundle, info: info, settings: settings, url: url),
                category: .systemSettings,
                symbolName: "gearshape")
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A pane every one of whose representations is hidden.
    ///
    /// This catches the panes Apple has retired outright. It does **not** catch one whose visible
    /// representation is gated on a predicate — `device.cddvd == YES`, `showClassKitPrefsPane ==
    /// YES` — because evaluating those means evaluating System Settings' own expression language
    /// against live device state. CDs & DVDs and Classroom therefore appear on machines that would
    /// not show them; opening one is harmless, and guessing at the predicates would not be.
    private static func isHidden(_ settings: [String: Any]) -> Bool {
        guard let representations = settings["representations"] as? [[String: Any]],
              !representations.isEmpty
        else { return false }
        return representations.allSatisfy { ($0["hidden"] as? NSNumber)?.boolValue == true }
    }

    /// The name System Settings shows in its own sidebar.
    ///
    /// The localised dictionary is the one that has it: unlocalised, half of these read
    /// "AccessibilitySettingsExtension" or "PowerPreferences" rather than "Accessibility" and
    /// "Battery". Where even that is missing, the trailing noise words are trimmed off by hand.
    private static func paneName(
        bundle: Bundle, info: [String: Any], settings: [String: Any], url: URL
    ) -> String {
        let localized = bundle.localizedInfoDictionary
        let candidates = [
            localized?["CFBundleDisplayName"] as? String,
            localized?["CFBundleName"] as? String,
            sidebarName(bundle: bundle, settings: settings),
            info["CFBundleDisplayName"] as? String,
            info["CFBundleName"] as? String,
            url.deletingPathExtension().lastPathComponent,
        ]
        let raw = candidates.compactMap { $0 }.first { !$0.isEmpty }
            ?? String(localized: "Settings", comment: "Fallback name for a preference pane that names itself nowhere")
        return tidy(raw)
    }

    /// The sidebar label a representation declares, resolved through the bundle's own strings.
    ///
    /// A last resort for the handful of panes carrying no localised display name — without it the
    /// Battery pane is listed as "PowerPreferences". The value is usually a localisation key rather
    /// than a string, which is why it goes through `localizedString`.
    ///
    /// The *last* representation wins. Apple writes them least-specific first — Battery declares the
    /// no-battery case before the battery one, Touch ID the no-Touch-ID case before it — so the last
    /// is the one describing the machine this pane is most likely being read on. It decides a single
    /// row's wording and nothing else.
    private static func sidebarName(bundle: Bundle, settings: [String: Any]) -> String? {
        guard let representations = settings["representations"] as? [[String: Any]] else { return nil }
        let keys = representations.compactMap { representation -> String? in
            guard !isHiddenRepresentation(representation) else { return nil }
            return representation["sidebar-name"] as? String
        }
        guard let key = keys.last, !key.isEmpty else { return nil }
        let resolved = bundle.localizedString(forKey: key, value: key, table: nil)
        return resolved.isEmpty ? nil : resolved
    }

    private static func isHiddenRepresentation(_ representation: [String: Any]) -> Bool {
        (representation["hidden"] as? NSNumber)?.boolValue == true
    }

    /// Strips the suffixes an internal bundle name carries. Only ever applied to the fallback, so a
    /// pane that is genuinely called "Extensions" keeps its name.
    static func tidy(_ name: String) -> String {
        var result = name
        for suffix in [" Settings Extension", "SettingsExtension", " Extension", "Extension", "Settings"] {
            if result.hasSuffix(suffix), result.count > suffix.count {
                result = String(result.dropLast(suffix.count))
                break
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Folders

    /// The folders a Start menu lists, in the order the Finder's sidebar puts them.
    ///
    /// Only the ones that actually exist: iCloud Drive is absent on a Mac not signed in, and an
    /// entry that opens nothing is worse than no entry.
    static func folders(fileManager: FileManager = .default) -> [CatalogEntry] {
        let home = fileManager.homeDirectoryForCurrentUser
        // Translated here rather than read from `FileManager.displayName(atPath:)`, which answers
        // the *account's* folder name for the home directory — "hossain" rather than "Home" — so it
        // would be right for nine of these and wrong for the one the list opens with. Finder's own
        // names for the other nine are what these translations should match.
        let candidates: [(String, URL)] = [
            (String(localized: "Home", comment: "Folder: the user's home directory"), home),
            (String(localized: "Desktop", comment: "Folder, as Finder names it"),
             home.appendingPathComponent("Desktop")),
            (String(localized: "Documents", comment: "Folder, as Finder names it"),
             home.appendingPathComponent("Documents")),
            (String(localized: "Downloads", comment: "Folder, as Finder names it"),
             home.appendingPathComponent("Downloads")),
            (String(localized: "Pictures", comment: "Folder, as Finder names it"),
             home.appendingPathComponent("Pictures")),
            (String(localized: "Music", comment: "App category"),
             home.appendingPathComponent("Music")),
            (String(localized: "Movies", comment: "Folder, as Finder names it"),
             home.appendingPathComponent("Movies")),
            (String(localized: "iCloud Drive", comment: "Folder, as Finder names it"),
             home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")),
            (String(localized: "Applications", comment: "Folder, as Finder names it"),
             URL(fileURLWithPath: "/Applications")),
            (String(localized: "Utilities", comment: "Launcher heading, Apple's own category name"),
             URL(fileURLWithPath: "/System/Applications/Utilities")),
        ]

        return candidates.compactMap { name, url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            return CatalogEntry(
                action: .open(url), name: name, category: .folders, symbolName: "folder")
        }
    }

    // MARK: - Power

    static func power() -> [CatalogEntry] {
        PowerAction.allCases.map { action in
            CatalogEntry(
                action: .power(action),
                name: action.title,
                category: .power,
                symbolName: action.symbolName)
        }
    }
}
