import AppKit

enum BarEdge: String, Codable, CaseIterable, Sendable {
    case left, bottom, right

    var isVertical: Bool { self != .bottom }

    /// The matching `com.apple.dock orientation` value, for reserved-space mode.
    var dockOrientation: String { rawValue }
    var title: String {
        switch self {
        case .left: String(localized: "Left", comment: "Screen edge the bar sits on")
        case .bottom: String(localized: "Bottom", comment: "Screen edge the bar sits on")
        case .right: String(localized: "Right", comment: "Screen edge the bar sits on")
        }
    }
}

/// Whether the bar hugs its icons or stretches the whole edge like the menu bar.
enum SpanMode: String, Codable, CaseIterable, Sendable {
    case hugContents
    case fullSpan

    var title: String {
        switch self {
        case .hugContents: String(localized: "Fit to Icons", comment: "Bar length: only as long as its contents")
        case .fullSpan: String(localized: "Full Width", comment: "Bar length: the whole screen edge")
        }
    }
}

/// What the Apps Menu lists when it opens.
enum AppsMenuSource: String, Codable, CaseIterable, Sendable {
    case favorites
    case allApps
    case recentApps

    var title: String {
        switch self {
        case .favorites: String(localized: "Favourites", comment: "Apps Menu contents")
        case .allApps: String(localized: "All Apps", comment: "Apps Menu contents")
        case .recentApps: String(localized: "Recent Apps", comment: "Apps Menu contents")
        }
    }

    var detail: String {
        switch self {
        case .favorites: String(
            localized: "The apps you have pinned to the bar.",
            comment: "Explains what the Favourites source lists")
        case .allApps: String(
            localized: "Everything in your Applications folders.",
            comment: "Explains what the All Apps source lists")
        case .recentApps: String(
            localized: "Apps you have used most recently.",
            comment: "Explains what the Recent Apps source lists")
        }
    }
}

/// The key that opens the Apps Menu — the Windows key's job, on a keyboard that has no Windows key.
///
/// macOS leaves no lone key for this the way Windows does, so the choice is between a two-key
/// combination it does not use and a bare modifier nothing else claims. Measured against this
/// machine's `com.apple.symbolichotkeys`, the near misses are all taken: `⌃Space` and `⌃⌥Space` are
/// input-source switching, `⌘Space` is Spotlight and `⌥⌘Space` is Finder search.
enum AppsMenuHotKey: String, Codable, CaseIterable, Sendable {
    case off
    /// The default. Unassigned on macOS, and on Windows it is literally the Start-menu shortcut —
    /// so it already means this. Escape has no text-input role, so it shadows nothing.
    case controlEscape
    /// What most launchers use, so it is the one people arrive with. It does shadow the
    /// non-breaking space, which is what `⌥Space` types into a text field.
    case optionSpace
    /// The closest thing to a Windows key: a lone modifier macOS assigns nothing, tapped and
    /// released on its own. Costs the Accessibility permission — see `RightCommandWatcher`.
    case rightCommand
    /// A combination the user recorded, in `Settings.appsMenuCustomHotKey`. Last, because the three
    /// above are the vetted answer and this is the way out when one of them is taken.
    case custom

    var title: String {
        switch self {
        case .off: String(localized: "Off", comment: "Apps Menu shortcut: none assigned")
        // The three key names are symbols macOS draws identically in every language, so only the
        // word wrapped around one of them is worth translating.
        case .controlEscape: "⌃Esc"
        case .optionSpace: "⌥Space"
        case .rightCommand: String(
            localized: "Tap right ⌘",
            comment: "Apps Menu shortcut: tap the right-hand Command key on its own")
        case .custom: String(
            localized: "Custom Shortcut",
            comment: "Apps Menu shortcut: a combination the user records")
        }
    }

    var detail: String {
        switch self {
        case .off: String(
            localized: "No shortcut. The Apps Menu opens from its cell on the bar.",
            comment: "Trade-off of the Off shortcut choice")
        case .controlEscape: String(
            localized: "Unused by macOS, and the Start-menu shortcut on Windows.",
            comment: "Trade-off of the ⌃Esc shortcut choice")
        case .optionSpace: String(
            localized: "Familiar from other launchers. Replaces ⌥Space's non-breaking space.",
            comment: "Trade-off of the ⌥Space shortcut choice")
        case .rightCommand: String(
            localized: "Tapped on its own, like the Windows key. Needs Accessibility.",
            comment: "Trade-off of the right-Command shortcut choice")
        case .custom: String(
            localized: "A combination you record, for when the others are taken.",
            comment: "Trade-off of the custom shortcut choice")
        }
    }

    /// Whether this one is watched for rather than registered, which is what makes it the only
    /// choice that depends on a permission.
    var needsAccessibility: Bool { self == .rightCommand }
}

/// Overall scale of the bar.
///
/// Two fixed sizes, the same on every display. `small` is 32pt, with 27pt icons. `big` is 1.5x
/// that, a 48pt bar with 40pt icons — near enough the macOS Dock's own 42pt default, i.e. the
/// platform's idea of a comfortable target. Neither follows the menu bar, whose height differs from
/// one display to the next.
enum BarSize: String, Codable, CaseIterable, Sendable {
    case small
    case big

    var title: String {
        switch self {
        case .small: String(localized: "Small", comment: "Bar scale: the slimmer of the two, 32pt")
        case .big: String(localized: "Big", comment: "Bar scale: half again as thick as Small, 48pt")
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .small: 1.0
        case .big: 1.5
        }
    }

    /// One row's thickness, before the user's nudge.
    var thickness: CGFloat { 32 * multiplier }
}

/// How each cell is drawn.
///
/// `compact` is the dock idiom: a square per item, icon only. `expanded` is the classic taskbar
/// idiom: every running app becomes a labelled button that grows up to a fixed width, shares the
/// space when the bar fills up, and falls back to a plain icon when there is nothing left to give.
enum BarItemStyle: String, Codable, CaseIterable, Sendable {
    case compact
    case expanded

    var title: String {
        switch self {
        case .compact: String(localized: "Icons Only", comment: "How each cell is drawn")
        case .expanded: String(localized: "Icons with Labels", comment: "How each cell is drawn")
        }
    }
}

/// Where the icons sit once the bar is wider than they are. Only meaningful in `.fullSpan`.
enum ItemAlignment: String, Codable, CaseIterable, Sendable {
    case leading, center, trailing

    /// Named for the bar's own axis: on a vertical bar "leading" is the top.
    func title(for edge: BarEdge) -> String {
        switch (self, edge.isVertical) {
        case (.leading, false): String(localized: "Left", comment: "Screen edge the bar sits on")
        case (.trailing, false): String(localized: "Right", comment: "Screen edge the bar sits on")
        case (.leading, true): String(localized: "Top", comment: "Where the icons sit along a vertical bar")
        case (.trailing, true): String(localized: "Bottom", comment: "Screen edge the bar sits on")
        case (.center, _): String(localized: "Centre", comment: "Where the icons sit along the bar")
        }
    }
}

/// What the bar does when the display is showing a native full-screen space.
///
/// Reserving space is not an option here: no mechanism exists to hold space inside a full-screen
/// space for anything but the menu bar, so the honest choices are to float over the window, to get
/// out of the way, or to do what the menu bar itself does and come back on hover.
enum FullScreenBehavior: String, Codable, CaseIterable, Sendable {
    case show
    case revealOnHover
    case hide

    var title: String {
        switch self {
        case .show: String(localized: "Always Show", comment: "What the bar does in a full-screen space")
        case .revealOnHover: String(
            localized: "Reveal on Hover", comment: "What the bar does in a full-screen space")
        case .hide: String(localized: "Hide", comment: "What the bar does in a full-screen space")
        }
    }
}

/// The order the apps run in along the bar.
///
/// Only the apps are affected. Pinned folders and files keep their place after them, and the Trash
/// keeps its end — those are not tasks, and sorting them among the apps would answer a question
/// nobody asked.
enum SortOrder: String, Codable, CaseIterable, Sendable {
    /// Exactly where the user put things. The default, and the only one that reads `layout.json`'s
    /// order as an instruction rather than as a tie-break.
    case manual
    case alphabetical
    /// Oldest first, so the bar reads as a history of the session. Apps that are not running have no
    /// launch time and keep their stored order after the ones that do.
    case launch

    var title: String {
        switch self {
        case .manual: String(localized: "As Arranged", comment: "Order of the apps along the bar")
        case .alphabetical: String(localized: "By Name", comment: "Order of the apps along the bar")
        case .launch: String(localized: "By Launch Time", comment: "Order of the apps along the bar")
        }
    }
}

/// Which displays get a bar, and what goes on it.
enum ScreenMode: String, Codable, CaseIterable, Sendable {
    /// The same bar on every display — what uBar calls Mirror, and our default.
    case allScreens
    /// A bar on every display, each showing only the tasks whose windows are on it. uBar's own
    /// default; ours is the other way round, because this one is worth nothing without
    /// Accessibility and quietly degrades to `allScreens` without it.
    case perDisplay
    case menuBarScreen

    var title: String {
        switch self {
        case .allScreens: String(localized: "All Displays", comment: "Which displays get a bar")
        case .perDisplay: String(
            localized: "Each Display's Own Windows", comment: "Which displays get a bar")
        case .menuBarScreen: String(localized: "Main Display Only", comment: "Which displays get a bar")
        }
    }
}

/// Whether the bar follows the system's light/dark setting or is pinned to one of them.
///
/// The piece people actually ask for: a light menu bar with a dark strip under it, or the reverse.
/// It is an `NSAppearance` on the panel, so the material, the labels and the icons all move
/// together — setting a colour and leaving the text to the system is how you get black on black.
enum BarAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: String(localized: "Match System", comment: "Bar follows the system light/dark setting")
        case .light: String(localized: "Light", comment: "Bar is always light, whatever the system does")
        case .dark: String(localized: "Dark", comment: "Bar is always dark, whatever the system does")
        }
    }

    /// `nil` means "inherit", which is what following the system is.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// A colour the user picked, stored in a form that survives a round trip through JSON.
///
/// Components rather than a hex string: a hex string has to be parsed, and a malformed one in a
/// hand-edited file would have to fail somehow. Numbers clamp.
struct BarTint: Codable, Equatable, Sendable {
    var red: Double = 0.12
    var green: Double = 0.12
    var blue: Double = 0.14
    /// 0 is invisible, 1 is a solid slab. Kept apart from the colour so the picker and the slider
    /// are two controls rather than one four-dimensional one.
    var opacity: Double = 0.85

    var color: NSColor {
        NSColor(
            srgbRed: red.clamped(), green: green.clamped(), blue: blue.clamped(),
            alpha: opacity.clamped())
    }

    init() {}

    init(red: Double, green: Double, blue: Double, opacity: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(color: NSColor, opacity: Double) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            opacity: opacity)
    }
}

private extension Double {
    func clamped() -> CGFloat { CGFloat(Swift.min(1, Swift.max(0, self))) }
}

enum BarMaterial: String, Codable, CaseIterable, Sendable {
    case menu, headerView, popover, hudWindow, opaque
    /// A flat colour of the user's choosing, at the opacity they chose. No vibrancy: the point of
    /// picking a colour is to get that colour rather than the desktop tinted towards it.
    case custom

    var title: String {
        switch self {
        case .menu: String(localized: "Menu", comment: "Bar material, named after the system menu's")
        case .headerView: String(localized: "Header", comment: "Bar material, named after a window header's")
        case .popover: String(localized: "Popover", comment: "Bar material, named after a popover's")
        case .hudWindow: String(localized: "HUD", comment: "Bar material, named after a HUD panel's")
        case .opaque: String(localized: "Opaque", comment: "Bar material: no vibrancy at all")
        case .custom: String(localized: "Custom Colour", comment: "Bar material: a colour the user picked")
        }
    }

    /// Whether the bar is drawn by a vibrancy view at all.
    var usesVibrancy: Bool { self != .custom }

    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .menu: .menu
        case .headerView: .headerView
        case .popover: .popover
        case .hudWindow: .hudWindow
        case .opaque, .custom: .windowBackground
        }
    }
}

/// Decoded leniently, key by key.
///
/// A single malformed value — a typo in a hand-edited file, a setting removed in a later version —
/// must cost only that setting. Plain `decodeIfPresent` throws on a present-but-invalid value, which
/// would take the whole file down with it.
struct Settings: Codable, Equatable, Sendable {
    var edge: BarEdge = .bottom
    var spanMode: SpanMode = .hugContents
    /// Defaults to `big` so that a fresh install *is* the Dock design (`DesignPreset.dock`), which
    /// the preset picker then shows as selected. Small is the Classic design's size and one click
    /// away either way.
    var barSize: BarSize = .big
    var itemStyle: BarItemStyle = .compact
    /// Width of one labelled button.
    ///
    /// In full-width mode this is the exact width every button takes, taskbar-style, and they shrink
    /// together only when the bar runs out of room. When the bar hugs its icons it is a ceiling
    /// instead — sizing to the text there keeps a short list compact.
    ///
    /// Scaled by `barSize` like the rest of the bar's metrics, so the default gives 140pt buttons at
    /// Small and 210pt at Big.
    var expandedItemWidth: Double = 140
    var itemAlignment: ItemAlignment = .center
    /// How many rows of cells the bar stacks, as uBar's draggable edge does. Clamped by `rowCount`.
    ///
    /// The bar is always this many rows thick, whether or not the cells need them all. A thickness
    /// that followed the contents would resize the bar every time an app opened — and with screen
    /// space reserved, re-park the system Dock underneath it each time. So the rows are asked for
    /// rather than earned, and `BarLayoutSolver.rows` spreads the cells evenly across the ones that
    /// were asked for rather than filling each in turn.
    ///
    /// On a left- or right-hand bar they are columns; the arithmetic is the same, only the axis
    /// swaps. See `BarContentView.rowBand`.
    var barRows: Int = 1
    var thicknessNudge: Double = 0
    var iconPadding: Double = 2
    var itemSpacing: Double = 4
    var autohide: Bool = false
    /// How long the pointer must rest on the edge before the bar slides out.
    var revealDelay: Double = 0.10
    /// Grace period after the pointer leaves, so crossing the bar does not make it vanish.
    var hideDelay: Double = 0.45
    var revealHotKeyEnabled: Bool = false
    /// Recorded in the preferences; ⌃⌥D until then.
    var revealHotKey: KeyCombination = .revealDefault
    /// ⌃⌥1…0 activate the first ten cells of the bar.
    ///
    /// Off by default, and deliberately not tied to auto-hide the way the reveal key is: these ten
    /// combinations are far more likely to collide with something the user already has bound, so
    /// they are opted into rather than acquired.
    var slotHotKeysEnabled: Bool = false
    /// What the slot keys are held with. Picked from a list rather than recorded: the keys are the
    /// number row whatever happens, and the list is the chords that are safe to look at the bar
    /// with — see `SlotChord`.
    var slotChord: SlotChord = .controlOption
    /// The key that moves focus to the bar: the arrows then move along it, Return opens, Escape
    /// gives focus back (§5.27).
    ///
    /// On by default, like the Apps Menu's key and for the same reason — one combination macOS does
    /// not use. Unlike the others it is not a shortcut to somewhere the mouse also reaches: without
    /// it the bar has no keyboard route at all, and Eskele has hidden the Dock that ⌃F3 would
    /// otherwise have gone to.
    var focusHotKeyEnabled: Bool = true
    /// Recorded in the preferences; ⌃⌥⇥ until then.
    var focusHotKey: KeyCombination = .focusDefault
    var sortOrder: SortOrder = .manual
    /// Show a live thumbnail of the window in the hover label.
    ///
    /// The only thing in Eskele that costs Screen Recording, so it is asked for rather than assumed.
    /// Without the permission it does nothing and the label stays text, which is what it has always
    /// been.
    var windowPreviews: Bool = false
    /// Hold ⇧⌥ to read each app's processor and memory use off the bar.
    ///
    /// Off by default for the same reason the slot keys are: watching for a chord means a timer, and
    /// a timer for a feature nobody asked for is a battery cost nobody agreed to.
    var activityOverlayEnabled: Bool = false
    var fullScreenBehavior: FullScreenBehavior = .show
    /// In full-width labelled mode, give every window its own button instead of one per app.
    ///
    /// The Windows "never combine" behaviour. Only meaningful where there is room for a title, so it
    /// has no effect on a hugging bar or an icons-only one.
    var separateWindows: Bool = true
    var showAppsMenu: Bool = true
    /// The key that opens the Apps Menu. On by default, unlike the other two hot keys: this one is
    /// a single combination macOS does not use, rather than ten that are likely to collide.
    var appsMenuHotKey: AppsMenuHotKey = .controlEscape
    /// Used only while `appsMenuHotKey` is `.custom`, and kept when it is not, so trying one of the
    /// vetted keys does not throw away the one that was recorded.
    var appsMenuCustomHotKey: KeyCombination?
    var appsMenuSource: AppsMenuSource = .allApps
    /// Whether All Apps also lists System Settings panes, the common folders and the power actions —
    /// the Start-menu half of the launcher.
    var showSystemItems: Bool = true
    /// Whether the menu-bar icon is installed.
    ///
    /// It is the app's only always-visible affordance, so it may only be hidden while the Apps
    /// Menu — whose launcher carries a settings button — is on. See `hasSettingsRoute`.
    var showStatusItem: Bool = true
    var showRunningUnpinned: Bool = true
    /// Give menu-bar apps — and Eskele itself — a tile while they have an ordinary window open.
    ///
    /// An app with no Dock tile has nowhere to put a window it opens, which is why a settings window
    /// belonging to an agent cannot be got back to once it is behind something. The tile is
    /// transient: it arrives with the window and leaves with it, because a permanent tile for every
    /// agent on the machine would be noise rather than a feature.
    ///
    /// Off by default. It changes what the bar shows, it needs Accessibility to list the windows,
    /// and it is the kind of thing a user should opt into rather than discover. See
    /// `AccessoryAppsService`.
    var showAccessoryApps: Bool = false
    var showTrash: Bool = true
    /// A clock at the trailing end of the bar.
    ///
    /// Off by default, and the one feature here that duplicates something macOS already gives you:
    /// the menu bar's own clock survives Eskele hiding the Dock. It earns its place on a full-width
    /// bar, where the far end is empty anyway.
    var showClock: Bool = false
    var clockStyle: ClockStyle = .digital
    var clockFormat: ClockFormat = .timeAndDay
    /// Draw unread-style number badges on the cells that have one.
    var showBadges: Bool = true
    /// Draw a progress bar across a cell that has something under way.
    ///
    /// On by default: the sources that need no permission — a file landing in a folder on the bar,
    /// a command in `progress.json` — cost nothing until there is something to show.
    var showProgress: Bool = true
    /// Ask Music, Spotify and VLC where they are in the current track.
    ///
    /// Off by default, and the second thing in Eskele that trades a permission for a feature: each
    /// player raises its own Automation consent the first time it is asked. Without the consent
    /// nothing is drawn and nothing else changes. See `ProgressService` for why asking is the only
    /// route left.
    var mediaProgress: Bool = false
    /// Light a cell up when its app has put a dialog in front of you while you were elsewhere.
    var highlightAttention: Bool = true
    /// In labelled mode, keep pinned apps that are not running as compact launchers at the leading
    /// end of the bar instead of letting them sit among the task buttons.
    var separatePinGroup: Bool = true
    var screenMode: ScreenMode = .allScreens
    var suppressSystemDock: Bool = false
    /// Parks the system Dock on the same edge, still showing but covered by the bar and sized to
    /// match, so its screen-space reservation becomes ours. Off by default: it rewrites the user's
    /// Dock position and size. Has no effect while `autohide` is on — see `applyDockRequest`.
    var reserveScreenSpace: Bool = false
    var material: BarMaterial = .menu
    var appearance: BarAppearance = .system
    /// Only drawn when `material` is `.custom`.
    var tint = BarTint()
    var cornerRadius: Double = 9
    /// The design the user tuned for themselves, kept so the Custom tile can put it back after a
    /// trip through one of the shipped three. `nil` until they have moved a setting a design owns.
    ///
    /// It is a copy of settings that also live above, which is the point: these are the values the
    /// bar had *last time it was custom*, not the ones it has now. See `captureCustomDesign()`.
    var customDesign: DesignFields?
    var hasCompletedOnboarding: Bool = false

    /// How many rows the bar is actually drawn with. Clamped, so a hand-edited file cannot ask for
    /// a bar eleven rows thick — or for none at all.
    var rowCount: Int { min(BarLayout.maximumRows, max(1, barRows)) }

    /// One row's thickness: the size's own plus the nudge, clamped so a hand-edited file cannot ask
    /// for a bar too thin to hold an icon. The same on every display.
    var rowThickness: CGFloat { min(96, max(18, barSize.thickness + thicknessNudge)) }

    /// The bar's whole thickness, every row of it.
    var totalThickness: CGFloat { rowThickness * CGFloat(rowCount) }

    /// Whether menu-bar apps are actually being tracked.
    ///
    /// An accessory app's tile is by definition an unpinned running app, so it has nowhere to appear
    /// while the run of running apps is switched off — and scanning for it would be work for a tile
    /// that could never be drawn.
    var tracksAccessoryApps: Bool { showAccessoryApps && showRunningUnpinned }

    /// Whether media players are worth asking at all: the setting, and the switch that turns the
    /// whole drawing off.
    var tracksMediaProgress: Bool { showProgress && mediaProgress }

    /// Labels need horizontal room. A left- or right-hand bar is one icon wide, so expanded mode
    /// would mean abandoning the thing that makes this bar what it is; there it stays compact.
    var drawsLabels: Bool { itemStyle == .expanded && !edge.isVertical }

    /// One button per window rather than per app. Needs both the room for a title and the space of
    /// a full-width bar; grouped buttons stay the behaviour everywhere else.
    var splitsWindows: Bool { separateWindows && drawsLabels && spanMode == .fullSpan }

    /// Whether pinned launchers are hoisted into their own leading group. Only in labelled mode:
    /// an icons-only bar draws a launcher and a task identically, so there is nothing to separate.
    var groupsPins: Bool { separatePinGroup && drawsLabels }

    /// Whether a settings window can still be reached. The status menu and the launcher's settings
    /// button are the two routes in; hiding both would leave the file on disk as the only way back,
    /// so each toggle is locked while it is the last one standing.
    var hasSettingsRoute: Bool { showStatusItem || showAppsMenu }

    /// A bar that spans the whole edge should meet the screen corners squarely, the way the menu bar
    /// does; rounding only makes sense when the bar is a floating slab.
    var effectiveCornerRadius: Double { spanMode == .fullSpan ? 0 : cornerRadius }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        edge = c.lenient(.edge, d.edge)
        spanMode = c.lenient(.spanMode, d.spanMode)
        barSize = c.lenient(.barSize, d.barSize)
        itemStyle = c.lenient(.itemStyle, d.itemStyle)
        expandedItemWidth = c.lenient(.expandedItemWidth, d.expandedItemWidth)
        itemAlignment = c.lenient(.itemAlignment, d.itemAlignment)
        barRows = c.lenient(.barRows, d.barRows)
        thicknessNudge = c.lenient(.thicknessNudge, d.thicknessNudge)
        iconPadding = c.lenient(.iconPadding, d.iconPadding)
        itemSpacing = c.lenient(.itemSpacing, d.itemSpacing)
        autohide = c.lenient(.autohide, d.autohide)
        revealDelay = c.lenient(.revealDelay, d.revealDelay)
        hideDelay = c.lenient(.hideDelay, d.hideDelay)
        revealHotKeyEnabled = c.lenient(.revealHotKeyEnabled, d.revealHotKeyEnabled)
        // A hand-edited combination is held to the recorder's rule. Registered as written, a bare
        // letter would stop that letter typing anywhere on the Mac.
        revealHotKey = c.lenient(.revealHotKey, d.revealHotKey)
        if revealHotKey.refusal != nil { revealHotKey = d.revealHotKey }
        slotHotKeysEnabled = c.lenient(.slotHotKeysEnabled, d.slotHotKeysEnabled)
        slotChord = c.lenient(.slotChord, d.slotChord)
        focusHotKeyEnabled = c.lenient(.focusHotKeyEnabled, d.focusHotKeyEnabled)
        focusHotKey = c.lenient(.focusHotKey, d.focusHotKey)
        if focusHotKey.refusal != nil { focusHotKey = d.focusHotKey }
        sortOrder = c.lenient(.sortOrder, d.sortOrder)
        windowPreviews = c.lenient(.windowPreviews, d.windowPreviews)
        activityOverlayEnabled = c.lenient(.activityOverlayEnabled, d.activityOverlayEnabled)
        fullScreenBehavior = c.lenient(.fullScreenBehavior, d.fullScreenBehavior)
        separateWindows = c.lenient(.separateWindows, d.separateWindows)
        showAppsMenu = c.lenient(.showAppsMenu, d.showAppsMenu)
        appsMenuHotKey = c.lenient(.appsMenuHotKey, d.appsMenuHotKey)
        appsMenuCustomHotKey = c.lenient(.appsMenuCustomHotKey, d.appsMenuCustomHotKey)
        if appsMenuCustomHotKey?.refusal != nil { appsMenuCustomHotKey = nil }
        appsMenuSource = c.lenient(.appsMenuSource, d.appsMenuSource)
        showSystemItems = c.lenient(.showSystemItems, d.showSystemItems)
        showStatusItem = c.lenient(.showStatusItem, d.showStatusItem)
        showRunningUnpinned = c.lenient(.showRunningUnpinned, d.showRunningUnpinned)
        showAccessoryApps = c.lenient(.showAccessoryApps, d.showAccessoryApps)
        showTrash = c.lenient(.showTrash, d.showTrash)
        showClock = c.lenient(.showClock, d.showClock)
        clockStyle = c.lenient(.clockStyle, d.clockStyle)
        clockFormat = c.lenient(.clockFormat, d.clockFormat)
        showBadges = c.lenient(.showBadges, d.showBadges)
        showProgress = c.lenient(.showProgress, d.showProgress)
        mediaProgress = c.lenient(.mediaProgress, d.mediaProgress)
        highlightAttention = c.lenient(.highlightAttention, d.highlightAttention)
        separatePinGroup = c.lenient(.separatePinGroup, d.separatePinGroup)
        screenMode = c.lenient(.screenMode, d.screenMode)
        suppressSystemDock = c.lenient(.suppressSystemDock, d.suppressSystemDock)
        reserveScreenSpace = c.lenient(.reserveScreenSpace, d.reserveScreenSpace)
        material = c.lenient(.material, d.material)
        appearance = c.lenient(.appearance, d.appearance)
        tint = c.lenient(.tint, d.tint)
        cornerRadius = c.lenient(.cornerRadius, d.cornerRadius)
        customDesign = c.lenient(.customDesign, d.customDesign)
        hasCompletedOnboarding = c.lenient(.hasCompletedOnboarding, d.hasCompletedOnboarding)
    }
}

extension Settings {
    /// How many of the keys `decoder` holds name a setting, whether or not their values would
    /// decode. Here rather than in `SettingsFile`, which asks it, because the synthesized
    /// `CodingKeys` is private to this file.
    static func recognisedKeyCount(in decoder: Decoder) throws -> Int {
        try decoder.container(keyedBy: CodingKeys.self).allKeys.count
    }
}


extension KeyedDecodingContainer {
    /// Absent *or* malformed both fall back to `fallback`.
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        // `try?` flattens here, so a thrown error and an absent key both arrive as nil — which is
        // exactly the behaviour we want: either way, fall back.
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
