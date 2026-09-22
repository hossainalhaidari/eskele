import AppKit
import Carbon.HIToolbox

/// The four modifiers a hot key can carry.
///
/// Carbon's mask is the raw value because `RegisterEventHotKey` is the one consumer that takes
/// nothing else. It is written to disk as names rather than as that number: `settings.json` is
/// hand-editable, and `["control", "option"]` says what 6144 does not.
struct KeyModifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt32
    init(rawValue: UInt32) { self.rawValue = rawValue }

    static let control = KeyModifiers(rawValue: UInt32(controlKey))
    static let option = KeyModifiers(rawValue: UInt32(optionKey))
    static let shift = KeyModifiers(rawValue: UInt32(shiftKey))
    static let command = KeyModifiers(rawValue: UInt32(cmdKey))

    /// Apple's order, which is the order every menu in macOS writes them in.
    private static let ordered: [(modifier: KeyModifiers, symbol: String, name: String)] = [
        (.control, "⌃", "control"), (.option, "⌥", "option"), (.shift, "⇧", "shift"), (.command, "⌘", "command"),
    ]

    init(_ flags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, KeyModifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        self = pairs.reduce(into: []) { result, pair in
            if flags.contains(pair.0) { result.insert(pair.1) }
        }
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }

    var symbols: String {
        KeyModifiers.ordered.filter { contains($0.modifier) }.map(\.symbol).joined()
    }
}

extension KeyModifiers: Codable {
    /// A name this build does not know is dropped rather than failing the whole combination.
    init(from decoder: Decoder) throws {
        let names = try decoder.singleValueContainer().decode([String].self)
        self = KeyModifiers.ordered.reduce(into: []) { result, entry in
            if names.contains(entry.name) { result.insert(entry.modifier) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(KeyModifiers.ordered.filter { contains($0.modifier) }.map(\.name))
    }
}

/// A key and the modifiers held with it — one global hot key.
///
/// The key is a virtual key code: a *position* on the keyboard, not a character, because that is
/// what `RegisterEventHotKey` matches on. So the name shown for it is looked up in the current
/// keyboard layout at the moment it is drawn (`displayName`), and the same combination reads ⌃⌥D on
/// a US keyboard and ⌃⌥E on a Dvorak one — which is the key it actually is on each.
struct KeyCombination: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: KeyModifiers

    init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: Int, modifiers: KeyModifiers) {
        self.init(keyCode: UInt32(keyCode), modifiers: modifiers)
    }

    static let revealDefault = KeyCombination(keyCode: kVK_ANSI_D, modifiers: [.control, .option])

    /// ⌃⌥⇥. Tab because moving focus is what Tab means; ⌃⌥ because it is the bar's own chord, the
    /// one the slot keys use and the numbers appear under. macOS's own key for this job is ⌃F3,
    /// "Move focus to the Dock", which is switched on by default — and points at the Dock that
    /// Eskele hides.
    static let focusDefault = KeyCombination(keyCode: kVK_Tab, modifiers: [.control, .option])

    /// The number row, 1…9 then 0, which is how the tenth slot is addressed — the row's own order
    /// rather than its numeric one, as every taskbar that has done this reads it.
    ///
    /// Spelled out rather than counted up from `kVK_ANSI_1`, because the row is not consecutive:
    /// 5 is 23 and 6 is 22, so counting would silently swap that pair.
    static let slotKeyCodes: [UInt32] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0,
    ].map(UInt32.init)

    var isFunctionKey: Bool { KeyCombination.functionKeys[keyCode] != nil }

    /// Why this can never be a global shortcut, whoever else is using it — or nil if it can be.
    ///
    /// A global hot key is taken from every app, text fields included, so the rule is about what
    /// would be lost. With neither ⌃ nor ⌘ held, the key types a character: ⇧ gives capitals and ⌥
    /// gives é, ü and ™, which is how accents are typed on half the world's keyboards. ⌘ alone, or
    /// with ⇧, is the front app's own menu shortcut — ⌘W, ⌘⇧N — and a global one would take that
    /// shortcut away from every app at once. ⌃ with a letter and nothing else is the text system's:
    /// ⌃A, ⌃E and ⌃K move and delete in every Cocoa text field. What is left needs ⌃ with something
    /// more than a lone letter, or ⌥ and ⌘ together. A function key stands alone.
    var refusal: HotKeyProblem? {
        guard !isFunctionKey else { return nil }
        if modifiers.contains(.control) {
            let lone = modifiers == .control && KeyCombination.letters[keyCode] != nil
            return lone ? .editsText : nil
        }
        if modifiers.isSuperset(of: [.option, .command]) { return nil }
        return modifiers.contains(.command) ? .takesAppShortcut : .typesText
    }

    /// `layout` answers what a key is labelled on the keyboard in use, and may not know.
    func displayName(layout: (UInt32) -> String?) -> String {
        modifiers.symbols + KeyCombination.keyName(for: keyCode, layout: layout)
    }

    @MainActor var displayName: String { displayName(layout: KeyboardLayout.label(for:)) }

    /// Keys whose name is not a character — or not one the layout can be asked for — come from a
    /// table; everything else from the layout, falling back to what the key is on a US keyboard.
    static func keyName(for keyCode: UInt32, layout: (UInt32) -> String?) -> String {
        if let fixed = functionKeys[keyCode] ?? namedKeys[keyCode] { return fixed }
        if let label = layout(keyCode) { return label }
        if let label = letters[keyCode] ?? digits[keyCode] { return label }
        return String(localized: "Key \(Int(keyCode))", comment: "A key with no name, identified by its number")
    }

    private static func table(_ pairs: [(Int, String)]) -> [UInt32: String] {
        Dictionary(uniqueKeysWithValues: pairs.map { (UInt32($0.0), $0.1) })
    }

    private static let functionKeys = table([
        (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"), (kVK_F5, "F5"),
        (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"), (kVK_F10, "F10"),
        (kVK_F11, "F11"), (kVK_F12, "F12"), (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"),
        (kVK_F16, "F16"), (kVK_F17, "F17"), (kVK_F18, "F18"), (kVK_F19, "F19"), (kVK_F20, "F20"),
    ])

    /// The symbols macOS menus use, and the two words the Apps Menu picker already shows untranslated.
    private static let namedKeys = table([
        (kVK_Escape, "Esc"), (kVK_Space, "Space"), (kVK_Return, "↩"), (kVK_ANSI_KeypadEnter, "⌤"),
        (kVK_Tab, "⇥"), (kVK_Delete, "⌫"), (kVK_ForwardDelete, "⌦"), (kVK_ANSI_KeypadClear, "⌧"),
        (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
        (kVK_Home, "↖"), (kVK_End, "↘"), (kVK_PageUp, "⇞"), (kVK_PageDown, "⇟"),
    ])

    private static let letters = table([
        (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
        (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
        (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
        (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
        (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
        (kVK_ANSI_Z, "Z"),
    ])

    private static let digits = table([
        (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"),
        (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"), (kVK_ANSI_0, "0"),
    ])
}

/// What the slot keys are held with. The number row itself is fixed, since the keys *are* the
/// numbers; the choice is only which modifiers go with it.
///
/// Every choice includes ⌃, and that is the rule rather than a coincidence. The slot numbers appear
/// on the bar while this chord is held, so it is a chord people hold while looking at the bar — with
/// the pointer on it — and a chord you look with must not also be a click gesture. ⌃ never is:
/// ⌃-click is the context menu everywhere. ⌥⌘ would have been the obvious fifth choice, and it is
/// Show Only This on a click. The other near misses are taken: ⌘1…9 is every browser's tabs, ⌃1…9
/// is Mission Control's desktops, ⇧⌘3…5 are the screenshot keys, ⌥ and ⇧ alone type characters, and
/// ⇧⌥ is the activity overlay's chord.
enum SlotChord: String, Codable, CaseIterable, Sendable {
    case controlOption
    case controlCommand
    case controlShift
    case controlOptionCommand

    var modifiers: KeyModifiers {
        switch self {
        case .controlOption: [.control, .option]
        case .controlCommand: [.control, .command]
        case .controlShift: [.control, .shift]
        case .controlOptionCommand: [.control, .option, .command]
        }
    }

    var combinations: [KeyCombination] {
        KeyCombination.slotKeyCodes.map { KeyCombination(keyCode: $0, modifiers: modifiers) }
    }

    /// Symbols only, drawn the same in every language.
    var title: String { "\(modifiers.symbols)1…0" }
}

extension AppsMenuHotKey {
    /// The key combination this choice registers. Nil for the two that register nothing: "off" is
    /// nothing at all, and the right ⌘ tap is watched for instead.
    func combination(custom: KeyCombination?) -> KeyCombination? {
        switch self {
        case .controlEscape: KeyCombination(keyCode: kVK_Escape, modifiers: .control)
        case .optionSpace: KeyCombination(keyCode: kVK_Space, modifiers: .option)
        case .custom: custom
        case .off, .rightCommand: nil
        }
    }
}

// MARK: - Checking

/// The four things Eskele registers hot keys for.
enum HotKeyRole: Hashable, Sendable, CaseIterable {
    case reveal
    case slots
    case appsMenu
    /// Moving the keyboard onto the bar (§5.27).
    case focus
}

enum HotKeyProblem: Equatable, Sendable {
    /// No ⌃ or ⌘: a key you type with. See `KeyCombination.refusal`.
    case typesText
    /// ⌃ and a lone letter: a text-editing key.
    case editsText
    /// ⌘ or ⌘⇧ alone: the front app's own shortcut.
    case takesAppShortcut
    /// One of macOS's own shortcuts, switched on.
    case system(KeyCombination)
    /// One of Eskele's other hot keys.
    case ours(HotKeyRole, KeyCombination)
    /// macOS would not register it.
    case unavailable
}

extension Settings {
    /// What `role` registers with these settings — nothing, when it is switched off.
    func hotKeys(for role: HotKeyRole) -> [KeyCombination] {
        switch role {
        case .reveal: revealHotKeyEnabled ? [revealHotKey] : []
        case .slots: slotHotKeysEnabled ? slotChord.combinations : []
        case .appsMenu: appsMenuHotKey.combination(custom: appsMenuCustomHotKey).map { [$0] } ?? []
        case .focus: focusHotKeyEnabled ? [focusHotKey] : []
        }
    }
}

/// What can be said about a set of hot keys before anyone presses one.
///
/// Less than it looks. Measured on macOS 26: `RegisterEventHotKey` returns `noErr` for a combination
/// another process already holds — two processes registering ⌃⌥⌘T both succeed — and for ⌘Space and
/// ⌘Tab too. It fails only when the same process registers a combination twice. So "it failed to
/// register" catches almost nothing, and no public API lists what other apps have registered.
///
/// What *can* be checked is everything that is ours or the system's: the intrinsic rule
/// (`KeyCombination.refusal`), Eskele's own keys against each other, and macOS's own shortcuts
/// (`SystemShortcuts`), which are the collisions most likely to happen — ⌘Space, ⌃Space, the
/// screenshot keys. Another app's shortcut remains invisible, and the preferences say so.
struct HotKeyReview {
    var settings: Settings
    /// macOS's own shortcuts that are switched on.
    var system: Set<KeyCombination>
    /// The roles macOS refused to register, from `GlobalHotKey`.
    var unavailable: Set<HotKeyRole> = []

    /// What is wrong with `role` as the settings stand, if anything.
    ///
    /// A clash between two of Eskele's own keys is reported on both of them: whichever registers
    /// second is the one that fails, and that order is not the user's business.
    func problem(for role: HotKeyRole) -> HotKeyProblem? {
        let mine = settings.hotKeys(for: role)
        for combination in mine {
            if let clash = clash(combination, excluding: role) { return clash }
        }
        if let taken = mine.first(where: system.contains) { return .system(taken) }
        return unavailable.contains(role) ? .unavailable : nil
    }

    /// Why a combination just recorded for `role` cannot have it, or nil to accept it.
    func refusal(of candidate: KeyCombination, for role: HotKeyRole) -> HotKeyProblem? {
        if let refusal = candidate.refusal { return refusal }
        if let clash = clash(candidate, excluding: role) { return clash }
        return system.contains(candidate) ? .system(candidate) : nil
    }

    private func clash(_ combination: KeyCombination, excluding role: HotKeyRole) -> HotKeyProblem? {
        for other in HotKeyRole.allCases where other != role {
            if settings.hotKeys(for: other).contains(combination) { return .ours(other, combination) }
        }
        return nil
    }
}

extension HotKeyProblem {
    /// Drawn under the control it is about, so it names the key but not the setting.
    @MainActor var message: String {
        switch self {
        case .typesText:
            String(
                localized: """
                    Without ⌃ or ⌘ this is a key you type with, and it would stop typing in every \
                    app. Add ⌃ or ⌘.
                    """,
                comment: "Shortcut refused: it has no Control or Command key")
        case .editsText:
            String(
                localized: """
                    ⌃ and a letter moves the cursor in text fields — ⌃A, ⌃E, ⌃K. Add ⌥, ⇧ or ⌘ to it.
                    """,
                comment: "Shortcut refused: Control plus a single letter is a text-editing key")
        case .takesAppShortcut:
            String(
                localized: """
                    ⌘ shortcuts belong to the app in front — ⌘W, ⌘⇧N — and this would take one from \
                    every app. Add ⌃ or ⌥.
                    """,
                comment: "Shortcut refused: Command alone would steal an app's menu shortcut")
        case .system(let combination):
            String(
                localized: """
                    \(combination.displayName) is a macOS shortcut. Choose another, or turn it off in \
                    System Settings ▸ Keyboard ▸ Keyboard Shortcuts.
                    """,
                comment: "Shortcut clashes with a system shortcut. The argument is the key, e.g. ⌘Space.")
        case .ours(.reveal, let combination):
            String(
                localized: "\(combination.displayName) already shows and hides the bar.",
                comment: "Shortcut clashes with Eskele's reveal key. The argument is the key.")
        case .ours(.slots, let combination):
            String(
                localized: "\(combination.displayName) is already one of the slot keys.",
                comment: "Shortcut clashes with one of Eskele's ten slot keys. The argument is the key.")
        case .ours(.appsMenu, let combination):
            String(
                localized: "\(combination.displayName) already opens the Apps Menu.",
                comment: "Shortcut clashes with Eskele's Apps Menu key. The argument is the key.")
        case .ours(.focus, let combination):
            String(
                localized: "\(combination.displayName) already moves focus to the bar.",
                comment: "Shortcut clashes with Eskele's key for moving focus to the bar. The argument is the key.")
        case .unavailable:
            String(
                localized: "macOS would not register this shortcut. Choose another.",
                comment: "Registering the shortcut failed")
        }
    }
}
