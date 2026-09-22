import AppKit
import Testing
@testable import Eskele

// MARK: - Settings panes

/// Read from the live system: the whole point of enumerating rather than hard-coding is that the
/// list is right for whatever macOS this is, and only the real directory can show that.
@MainActor
@Test func settingsPanesAreFoundAndNamedTheWaySystemSettingsNamesThem() {
    let panes = SystemCatalog.settingsPanes()
    #expect(panes.count > 20, "found \(panes.count) panes — enumeration is probably broken")

    let names = Set(panes.map(\.name))
    // Names that come from the localised dictionary. Unlocalised these read
    // "AccessibilitySettingsExtension" and "WiFiSettings".
    for expected in ["Accessibility", "Displays", "Sound", "Keyboard"] {
        #expect(names.contains(expected), "missing \(expected); got \(names.sorted().prefix(8))")
    }
    // The one that has no localised name at all, and reads "PowerPreferences" without the
    // sidebar-name fallback.
    #expect(names.contains("Battery"))

    // No internal-looking leftovers.
    #expect(!names.contains { $0.hasSuffix("Extension") || $0.hasSuffix("SettingsExtension") })
}

/// Every pane has to be openable, and by the scheme we claim to use.
@MainActor
@Test func everyPaneOpensBySettingsURL() {
    for pane in SystemCatalog.settingsPanes() {
        guard case .open(let url) = pane.action else {
            Issue.record("\(pane.name) is not an open action")
            continue
        }
        #expect(url.scheme == "x-apple.systempreferences")
        #expect(!(url.absoluteString.dropFirst("x-apple.systempreferences:".count)).isEmpty)
        #expect(pane.category == .systemSettings)
        #expect(pane.url != nil)
    }
}

/// A pane Apple has retired outright declares every representation hidden.
@MainActor
@Test func panesRetiredOutrightAreLeftOut() {
    let names = Set(SystemCatalog.settingsPanes().map(\.name))
    // "Extensions" was folded into Login Items; its extension is present but fully hidden.
    #expect(!names.contains("DefaultExtensionEnablement"))
}

@MainActor
@Test func aMissingExtensionsDirectoryYieldsNothingRatherThanFailing() {
    let nowhere = URL(fileURLWithPath: "/var/empty/eskele-does-not-exist")
    #expect(SystemCatalog.settingsPanes(in: nowhere).isEmpty)
}

/// Only applied to the fallback name, and only to a genuine suffix.
@MainActor
@Test func internalSuffixesAreTrimmedWithoutEatingRealNames() {
    #expect(SystemCatalog.tidy("HeadphoneSettingsExtension") == "Headphone")
    #expect(SystemCatalog.tidy("CDs & DVDs Settings Extension") == "CDs & DVDs")
    #expect(SystemCatalog.tidy("Displays") == "Displays")
    // A name that *is* the suffix keeps itself rather than becoming empty.
    #expect(SystemCatalog.tidy("Settings") == "Settings")
    #expect(SystemCatalog.tidy("Extension") == "Extension")
}

// MARK: - Folders

@MainActor
@Test func foldersAreOnesThatExist() {
    let folders = SystemCatalog.folders()
    let names = folders.map(\.name)
    #expect(names.contains("Home"))
    #expect(names.contains("Applications"))
    for folder in folders {
        let url = try! #require(folder.url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(folder.category == .folders)
        #expect(folder.symbolName == "folder")
    }
}

// MARK: - Power

@MainActor
@Test func everyPowerActionIsOfferedAndCarriesNoFile() {
    let power = SystemCatalog.power()
    #expect(power.count == PowerAction.allCases.count)
    for entry in power {
        guard case .power = entry.action else {
            Issue.record("\(entry.name) is not a power action")
            continue
        }
        // No file behind it, which is why the row needs a symbol.
        #expect(entry.url == nil)
        #expect(entry.symbolName != nil)
        #expect(entry.category == .power)
    }
}

/// Sleep is one keystroke from being undone; the other three end the session and can lose work.
/// A launcher you drive by typing is exactly where a mistyped Return lands one row off.
@MainActor
@Test func onlyTheDisruptivePowerActionsAskFirst() {
    #expect(PowerAction.sleep.needsConfirmation == false)
    #expect(PowerAction.logOut.needsConfirmation)
    #expect(PowerAction.restart.needsConfirmation)
    #expect(PowerAction.shutDown.needsConfirmation)
    // The ones that ask say so in their title.
    for action in PowerAction.allCases {
        #expect(action.title.hasSuffix("…") == action.needsConfirmation)
        #expect(!action.searchName.hasSuffix("…"))
    }
}

/// Four distinct Apple events. A copy-paste slip here would offer Restart and shut the Mac down.
@MainActor
@Test func eachPowerActionSendsItsOwnEvent() {
    let ids = PowerAction.allCases.map(\.eventID)
    #expect(Set(ids).count == PowerAction.allCases.count)
    #expect(PowerAction.sleep.eventID == AEEventID(kAESleep))
    #expect(PowerAction.logOut.eventID == AEEventID(kAELogOut))
    #expect(PowerAction.restart.eventID == AEEventID(kAERestart))
    #expect(PowerAction.shutDown.eventID == AEEventID(kAEShutDown))
}

// MARK: - Placement in the list

/// The launcher has always opened on applications. System rows are appended, so they must sort
/// after every application category — including "Other", which is still applications.
@MainActor
@Test func systemSectionsSortAfterEveryApplicationSection() {
    let categories: [AppCategory] = [
        .power, .folders, .systemSettings, .other,
        AppCategory(title: "Utilities"), AppCategory(title: "Developer Tools"),
    ]
    let sorted = categories.sorted()
    // Applications A–Z, then Other (still applications), then the system sections in their own
    // deliberate order — Power last.
    #expect(sorted.map(\.title) == [
        "Developer Tools", "Utilities", "Other", "System Settings", "Folders", "Power",
    ])
}

/// One search has to reach all of it — that is the reason for appending rather than adding a mode.
@MainActor
@Test func oneSearchReachesApplicationsPanesFoldersAndPower() {
    let entries = [
        CatalogEntry(url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari"),
    ] + SystemCatalog.settingsPanes() + SystemCatalog.folders() + SystemCatalog.power()

    func firstMatch(_ query: String) -> String? {
        LauncherContent.matches(in: entries, query: query).first?.name
    }
    #expect(firstMatch("safa") == "Safari")
    #expect(firstMatch("displ") == "Displays")
    #expect(firstMatch("downl") == "Downloads")
    #expect(firstMatch("restart") == "Restart…")
}

/// The button row is laid out straight from `allCases`, so that order *is* the on-screen order.
/// Least destructive first, so Shut Down is at the far end from Sleep rather than beside it.
@MainActor
@Test func thePowerButtonsRunLeastToMostDestructive() {
    #expect(PowerAction.allCases.first == .sleep)
    #expect(PowerAction.allCases.last == .shutDown)
    #expect(PowerAction.allCases == [.sleep, .logOut, .restart, .shutDown])
    // Every button needs a symbol to draw and a tooltip to name itself; icon-only controls that
    // cannot say what they are would be four indistinguishable glyphs.
    for action in PowerAction.allCases {
        #expect(!action.symbolName.isEmpty)
        #expect(!action.title.isEmpty)
    }
}

/// The folders keep the Finder's sidebar order rather than becoming an alphabetical list starting
/// with Applications.
@MainActor
@Test func theFolderSectionKeepsTheFinderOrder() {
    let sections = LauncherContent.sections(
        source: .allApps, entries: SystemCatalog.folders(), query: "")
    let folders = try! #require(sections.first { $0.title == "Folders" })
    #expect(folders.entries.first?.name == "Home")
    #expect(folders.entries.map(\.name) == SystemCatalog.folders().map(\.name))
}

/// Applications are still sorted by name — the exception is only for the system sections.
@MainActor
@Test func applicationSectionsAreStillAlphabetical() {
    let category = AppCategory(title: "Productivity")
    let entries = ["Zed", "Alpha", "Mid"].map {
        CatalogEntry(url: URL(fileURLWithPath: "/Applications/\($0).app"), name: $0, category: category)
    }
    let sections = LauncherContent.sections(source: .allApps, entries: entries, query: "")
    #expect(sections.first?.entries.map(\.name) == ["Alpha", "Mid", "Zed"])
}
