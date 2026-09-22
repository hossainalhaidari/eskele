/// The settings a design owns, lifted out of `Settings` so one can be held, compared and stored on
/// its own.
///
/// It exists for `DesignPreset.custom`: "the design you tuned for yourself" has to be kept
/// somewhere, and `Settings` cannot hold another `Settings`. Having the list in one place is also
/// what keeps writing a design and recognising one from ever drifting apart — they are the same
/// eight fields, read one way and written the other.
struct DesignFields: Codable, Equatable, Sendable {
    var edge: BarEdge
    var spanMode: SpanMode
    var itemStyle: BarItemStyle
    var itemAlignment: ItemAlignment
    var barSize: BarSize
    var showTrash: Bool
    var showAppsMenu: Bool
    var appsMenuSource: AppsMenuSource

    /// The three shipped designs differ only in layout, so the Trash and the Apps Menu default to
    /// on here rather than being restated by each of them.
    init(
        edge: BarEdge,
        spanMode: SpanMode,
        itemStyle: BarItemStyle,
        itemAlignment: ItemAlignment,
        barSize: BarSize,
        showTrash: Bool = true,
        showAppsMenu: Bool = true,
        appsMenuSource: AppsMenuSource = .allApps
    ) {
        self.edge = edge
        self.spanMode = spanMode
        self.itemStyle = itemStyle
        self.itemAlignment = itemAlignment
        self.barSize = barSize
        self.showTrash = showTrash
        self.showAppsMenu = showAppsMenu
        self.appsMenuSource = appsMenuSource
    }

    /// The design `settings` currently reads as.
    init(_ settings: Settings) {
        self.init(
            edge: settings.edge,
            spanMode: settings.spanMode,
            itemStyle: settings.itemStyle,
            itemAlignment: settings.itemAlignment,
            barSize: settings.barSize,
            showTrash: settings.showTrash,
            showAppsMenu: settings.showAppsMenu,
            appsMenuSource: settings.appsMenuSource)
    }

    /// Decoded field by field like `Settings` itself, so one bad value in a hand-edited file costs
    /// that field rather than the whole custom design.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DesignFields(Settings())
        edge = c.lenient(.edge, d.edge)
        spanMode = c.lenient(.spanMode, d.spanMode)
        itemStyle = c.lenient(.itemStyle, d.itemStyle)
        itemAlignment = c.lenient(.itemAlignment, d.itemAlignment)
        barSize = c.lenient(.barSize, d.barSize)
        showTrash = c.lenient(.showTrash, d.showTrash)
        showAppsMenu = c.lenient(.showAppsMenu, d.showAppsMenu)
        appsMenuSource = c.lenient(.appsMenuSource, d.appsMenuSource)
    }

    /// These fields written over `settings`; everything a design does not own is carried through.
    func applied(to settings: Settings) -> Settings {
        var result = settings
        result.edge = edge
        result.spanMode = spanMode
        result.itemStyle = itemStyle
        result.itemAlignment = itemAlignment
        result.barSize = barSize
        result.showTrash = showTrash
        result.showAppsMenu = showAppsMenu
        result.appsMenuSource = appsMenuSource
        return result
    }
}

/// A one-click starting point: the handful of settings that decide what kind of bar this is.
///
/// Every other setting — padding, material, auto-hide, badges — is a refinement of whichever of
/// these shapes you picked, so a design deliberately leaves them alone. What it owns is only what
/// `DesignFields` lists, and `matches(_:)` is defined as "writing it would change nothing".
///
/// Three of them ship with the app. The fourth, `custom`, has no fields of its own: it is whatever
/// the user tuned, and it is *defined* as "none of the other three" — so the moment you move a
/// setting a design owns, the bar is a custom one, and that shape is kept under the Custom tile for
/// you to come back to.
enum DesignPreset: String, CaseIterable, Identifiable, Sendable {
    /// The macOS idiom, and the app's own defaults: a floating slab centred on the bottom edge.
    case dock
    /// The Windows idiom: a full-width taskbar of labelled buttons, left-aligned.
    case classic
    /// The Ubuntu idiom: a full-height launcher down the left edge, icons from the top.
    case unity
    /// Whatever shape the user made for themselves, remembered in `Settings.customDesign`. Last in
    /// the list because it is the one you arrive at rather than start from.
    case custom

    var id: String { rawValue }

    /// The designs that have fields of their own, in picker order.
    static let shippedCases: [DesignPreset] = allCases.filter { $0.shipped != nil }

    var title: String {
        switch self {
        case .dock: String(localized: "Dock", comment: "Design named after the macOS Dock")
        case .classic: String(localized: "Classic", comment: "Design named after a classic taskbar")
        case .unity: String(localized: "Unity", comment: "Design named after Ubuntu's Unity launcher")
        case .custom: String(localized: "Custom", comment: "The design the user arranged themselves")
        }
    }

    var detail: String {
        switch self {
        case .dock: String(
            localized: "A big bar on the bottom edge, only as wide as its icons.",
            comment: "What the Dock design looks like")
        case .classic: String(
            localized: "A taskbar across the bottom, every running app a labelled button.",
            comment: "What the Classic design looks like")
        case .unity: String(
            localized: "A full-height column of big icons down the left edge.",
            comment: "What the Unity design looks like")
        case .custom: String(
            localized: "The bar you arranged yourself. Kept as you left it.",
            comment: "What the Custom design is")
        }
    }

    /// What this design writes, for the ones the app ships. `nil` is what makes Custom custom.
    private var shipped: DesignFields? {
        switch self {
        case .dock:
            DesignFields(
                edge: .bottom, spanMode: .hugContents, itemStyle: .compact,
                itemAlignment: .center, barSize: .big)
        case .classic:
            DesignFields(
                edge: .bottom, spanMode: .fullSpan, itemStyle: .expanded,
                itemAlignment: .leading, barSize: .small)
        case .unity:
            DesignFields(
                edge: .left, spanMode: .fullSpan, itemStyle: .compact,
                itemAlignment: .leading, barSize: .big)
        case .custom:
            nil
        }
    }

    /// The fields this design would write, given what `settings` remembers.
    ///
    /// Custom's come from the stored design — or, when the bar already is a custom one and nothing
    /// has been stored yet, from the bar itself. That second case is what makes the Custom tile draw
    /// the right thing on a settings file written before this design existed, without waiting for
    /// `captureCustomDesign()` to run.
    func fields(in settings: Settings) -> DesignFields? {
        switch self {
        case .custom: settings.customDesign ?? (matches(settings) ? DesignFields(settings) : nil)
        default: shipped
        }
    }

    /// The design's fields written over `settings`. Picking a design that has nothing to write —
    /// a Custom nobody has made yet — changes nothing.
    func applied(to settings: Settings) -> Settings {
        fields(in: settings)?.applied(to: settings) ?? settings
    }

    /// True when `settings` already reads as this design — so tuning a padding or a delay does not
    /// deselect the design it was tuning.
    func matches(_ settings: Settings) -> Bool {
        guard let shipped else {
            // Custom is defined by exclusion rather than by a set of values. Anything that is not
            // one of the shipped designs is a custom one, whether or not it has been stored yet.
            return !DesignPreset.shippedCases.contains { $0.matches(settings) }
        }
        return shipped.applied(to: settings) == settings
    }

    /// The design `settings` reads as. Always answers: a bar that is none of the shipped three is a
    /// custom one, which is the honest answer and the one the picker shows.
    static func matching(_ settings: Settings) -> DesignPreset {
        allCases.first { $0.matches(settings) } ?? .custom
    }

    /// Whether picking this design would do anything. Only ever false for a Custom design the user
    /// has not made yet — there is nothing to go back to.
    func isAvailable(in settings: Settings) -> Bool { fields(in: settings) != nil }

    /// A design shown on its own, with none of the user's other tuning behind it. `nil` when there
    /// is no design to draw.
    func preview(in settings: Settings) -> Settings? {
        fields(in: settings)?.applied(to: Settings())
    }
}

extension Settings {
    /// Keeps the Custom design in step with the bar.
    ///
    /// Called on every settings change, it gives the four tiles the behaviour they promise with one
    /// rule: *a bar that is none of the shipped designs is the custom one*. Tune a setting a design
    /// owns and this stores the result, overwriting whatever was under Custom before; click one of
    /// the shipped three and it leaves the stored design alone, waiting to be picked again.
    mutating func captureCustomDesign() {
        guard DesignPreset.matching(self) == .custom else { return }
        let fields = DesignFields(self)
        guard customDesign != fields else { return }
        customDesign = fields
    }
}
