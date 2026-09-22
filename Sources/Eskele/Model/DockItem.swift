import AppKit

struct AppRef: Equatable, Sendable {
    var bundleID: String
    var url: URL
    var name: String
}

/// One cell in the bar. Value type, rebuilt wholesale on every change; identity comes from `id`
/// (derived from the underlying thing, not a random UUID) so views survive a rebuild.
struct DockItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case app(AppRef)
        /// One window of an app, shown as its own task in full-width labelled mode.
        case window(AppRef, WindowRef)
        case folder(URL)
        case file(URL)
        case separator(String)
        case trash(isEmpty: Bool)
        /// The launcher button. Always first, never reorderable — the Start-button convention.
        case appsMenu
        /// The clock. Always last, for the same reason.
        case clock
    }

    /// Token of the divider the bar inserts between the pin group and the task run. Reserved, so a
    /// user-added separator can never collide with it.
    static let pinDividerToken = "__pins"

    var kind: Kind
    var isPinned: Bool = false
    var isRunning: Bool = false
    var isFrontmost: Bool = false
    var isHidden: Bool = false
    /// 0 means "unknown" as well as "none" — without Accessibility we cannot tell them apart.
    var windowCount: Int = 0
    var pid: pid_t?
    /// The process this cell stands for, when it is not the first copy of its app.
    ///
    /// Some apps run as several processes under one bundle ID — Godot's editor and the game it
    /// launches, anything started with `open -n`. Each copy gets a cell, as in the system Dock, and
    /// every copy after the first is keyed by its process. Sharing the bundle's identity is what
    /// gave two cells one id, and had both describe whichever copy the workspace listed first.
    var instance: pid_t?
    /// Unread-style count drawn over the icon. Nil for "no badge"; zero is never shown.
    var badge: Int?
    /// The app has put a dialog in front of the user while they were working elsewhere.
    var needsAttention: Bool = false
    /// This item, or the window it stands for, is in a native full-screen space.
    var isFullScreen: Bool = false
    /// Title of the window the app is currently on, when we know it. Drives the hover label, where
    /// what the user wants is the page they are looking at rather than the app's name again.
    var windowTitle: String?
    /// A pinned launcher hoisted out of the task run — see `Settings.groupsPins`. Drawn compact
    /// whatever the item style, because it is a shortcut rather than something that is running.
    var isPinLauncher: Bool = false
    /// Started, but not yet finished starting.
    var isLaunching: Bool = false
    /// Not answering. Only ever known with Accessibility — see `WindowInfoService`.
    var isUnresponsive: Bool = false
    /// When the app started, for `SortOrder.launch`. Nil for anything that is not running.
    var launchDate: Date?
    /// The positional hot key this cell answers to, counting from zero, or `nil` for the cells no
    /// key addresses. Assigned over the whole strip rather than per bar, so a bar filtered by
    /// display numbers its cells with the numbers the keys actually carry — non-contiguous ones,
    /// truthfully, rather than a second numbering that would disagree with the keyboard.
    var slotNumber: Int?
    /// A name the user gave this cell, from `PersistedItem.customName`.
    ///
    /// Not consulted for a window button: the name belongs to the app, and a window button is
    /// showing the window's title. The app's own name reaches those through `AppRef.name`, which is
    /// built from the same field.
    var customName: String?
    /// The displays this task's windows are on, for `ScreenMode.perDisplay`.
    ///
    /// Empty means "every bar": a pin, the Trash and the clock belong on all of them, and so does a
    /// task whose windows could not be placed — without Accessibility, with nothing open, or on a
    /// Space we cannot reach. Showing it everywhere is the mirror behaviour; showing it nowhere
    /// would lose an app the user can plainly see.
    var displays: Set<CGDirectDisplayID> = []

    var id: String {
        switch kind {
        // The first copy keeps the bundle's own id, which is what pins and stored arrangements are
        // matched against; only further copies carry their process.
        case .app(let ref): instance.map { "app:\(ref.bundleID)#\($0)" } ?? "app:\(ref.bundleID)"
        case .window(_, let window): window.id
        case .folder(let url): "folder:\(url.path)"
        case .file(let url): "file:\(url.path)"
        case .separator(let token): "sep:\(token)"
        case .trash: "trash"
        case .appsMenu: "apps-menu"
        case .clock: "clock"
        }
    }

    /// The key a `ProgressReport` for this cell is filed under, or `nil` for a cell that can never
    /// have one.
    ///
    /// A window button answers to its app's key, so an app playing a track shows the same bar on
    /// every one of its windows: the track is the app's, not any one window's.
    var progressKey: String? {
        switch kind {
        case .app(let ref), .window(let ref, _): "app:\(ref.bundleID)"
        case .folder(let url), .file(let url): "path:\(url.path)"
        case .separator, .trash, .appsMenu, .clock: nil
        }
    }

    /// What a file in `Icons/` replacing this cell would be called, or `nil` for a cell no filename
    /// can address — see `IconOverrideService`.
    var iconOverrideKey: String? {
        switch kind {
        case .app(let ref), .window(let ref, _): ref.bundleID
        case .trash: IconOverrideService.trashKey
        case .appsMenu: IconOverrideService.appsMenuKey
        // A path is not a filename. Finder's own Get Info overrides these, and we draw what it says.
        case .folder, .file, .separator, .clock: nil
        }
    }

    var displayName: String {
        switch kind {
        case .app(let ref): customName ?? ref.name
        case .window(_, let window): window.title
        case .folder(let url), .file(let url): customName ?? url.lastPathComponent
        case .separator: ""
        case .trash(let isEmpty): isEmpty ? "Trash" : "Trash — not empty"
        case .appsMenu: "Apps"
        case .clock: "Clock"
        }
    }

    /// What the hover label says: the page or document you are looking at, falling back to the name
    /// of the thing itself when nothing is open.
    ///
    /// A stalled or starting app says so instead. Diagonal stripes are a signal you have to have
    /// learned; the label is where someone who has not learned them finds out what they mean.
    var hoverTitle: String {
        if isUnresponsive { return "\(displayName) — not responding" }
        if isLaunching { return "\(displayName) — opening…" }
        return unstyledHoverTitle
    }

    private var unstyledHoverTitle: String {
        switch kind {
        case .window(let ref, let window):
            window.title.isEmpty ? ref.name : window.title
        case .app:
            windowTitle.map { $0.isEmpty ? displayName : $0 } ?? displayName
        case .folder, .file:
            displayName
        case .separator:
            ""
        case .trash:
            displayName
        case .appsMenu:
            "Apps"
        case .clock:
            ClockContent.description(at: Date())
        }
    }

    var isSeparator: Bool {
        if case .separator = kind { return true }
        return false
    }

    /// The divider the bar draws for itself. It has no stored counterpart, so it must not offer
    /// "Remove Separator" the way a user-added one does.
    var isImplicitSeparator: Bool {
        if case .separator(let token) = kind { return token == DockItem.pinDividerToken }
        return false
    }

    var isApp: Bool {
        if case .app = kind { return true }
        return false
    }

    var isWindow: Bool {
        if case .window = kind { return true }
        return false
    }

    /// Things that become labelled buttons: an app, or one window of one.
    var isTask: Bool { isApp || isWindow }

    var windowReference: WindowRef? {
        if case .window(_, let window) = kind { return window }
        return nil
    }

    var isTrash: Bool {
        if case .trash = kind { return true }
        return false
    }

    var isAppsMenu: Bool {
        if case .appsMenu = kind { return true }
        return false
    }

    var isClock: Bool {
        if case .clock = kind { return true }
        return false
    }

    /// Items that open a menu on a plain click rather than launching something.
    var opensMenuOnClick: Bool {
        if case .folder = kind { return true }
        return isAppsMenu
    }

    /// Whether a file dragged onto this cell means something (open-with, or trash).
    var acceptsFileDrops: Bool { isTask || isTrash }

    /// Whether ⌘-click has somewhere to go. The Trash keeps no URL of its own but does have a
    /// folder behind it; a separator and the launcher have nothing to show.
    var canRevealInFinder: Bool { url != nil || isTrash }

    var url: URL? {
        switch kind {
        case .app(let ref): ref.url
        case .window(let ref, _): ref.url
        case .folder(let url), .file(let url): url
        case .separator: nil
        case .trash: nil
        case .appsMenu, .clock: nil
        }
    }
}
