import AppKit
import Carbon.HIToolbox
import Testing
@testable import Eskele

private func key(_ code: Int, _ modifiers: KeyModifiers) -> KeyCombination {
    KeyCombination(keyCode: code, modifiers: modifiers)
}

private func decodeSettings(_ json: String) throws -> Settings {
    try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
}

// MARK: - Modifiers

/// Carbon is the one consumer that takes nothing else, so the raw value has to be its mask exactly.
@Test func modifiersAreCarbonsMask() {
    #expect(KeyModifiers.control.rawValue == UInt32(controlKey))
    #expect(KeyModifiers.option.rawValue == UInt32(optionKey))
    #expect(KeyModifiers.shift.rawValue == UInt32(shiftKey))
    #expect(KeyModifiers.command.rawValue == UInt32(cmdKey))
}

/// Written as names, in Apple's order whatever order they were inserted in, so the file reads the
/// way the menu does and an export does not change between two saves of the same settings.
@Test func modifiersAreStoredAsNamesInMenuOrder() throws {
    let data = try JSONEncoder().encode(KeyModifiers([.command, .shift, .control]))
    #expect(String(decoding: data, as: UTF8.self) == #"["control","shift","command"]"#)
    #expect(try JSONDecoder().decode(KeyModifiers.self, from: data) == [.control, .shift, .command])
}

@Test func anUnknownModifierNameIsDropped() throws {
    let decoded = try JSONDecoder().decode(KeyModifiers.self, from: Data(#"["hyper","option"]"#.utf8))
    #expect(decoded == .option)
}

/// Caps Lock and Fn ride along on ordinary events and are not part of a shortcut.
@Test func eventFlagsKeepOnlyTheFourModifiers() {
    let modifiers = KeyModifiers([.control, .option, .capsLock, .function])
    #expect(modifiers == [.control, .option])
    #expect(modifiers.eventFlags == [.control, .option])
}

// MARK: - Names

@Test func modifierSymbolsFollowTheMenuOrder() {
    #expect(KeyModifiers([.command, .option, .control, .shift]).symbols == "⌃⌥⇧⌘")
}

/// The key code is a position. On Dvorak the key a US keyboard calls D types E, and the name has to
/// be the one on the key the user is actually pressing.
@Test func aKeyIsNamedByTheLayoutInUse() {
    let reveal = KeyCombination.revealDefault
    #expect(reveal.displayName(layout: { _ in nil }) == "⌃⌥D")
    #expect(reveal.displayName(layout: { $0 == UInt32(kVK_ANSI_D) ? "E" : nil }) == "⌃⌥E")
}

/// Keys whose name is not a character come from the table, whatever the layout says about them.
@Test func namedKeysDoNotAskTheLayout() {
    let layout: (UInt32) -> String? = { _ in "?" }
    #expect(key(kVK_Escape, .control).displayName(layout: layout) == "⌃Esc")
    #expect(key(kVK_Space, .option).displayName(layout: layout) == "⌥Space")
    #expect(key(kVK_F12, []).displayName(layout: layout) == "F12")
    #expect(key(kVK_LeftArrow, [.control, .option]).displayName(layout: layout) == "⌃⌥←")
}

// MARK: - What can never be a shortcut

@Test func combinationsWithRoomToBeGlobalAreAccepted() {
    #expect(KeyCombination.revealDefault.refusal == nil)
    #expect(key(kVK_Escape, .control).refusal == nil)
    #expect(key(kVK_ANSI_K, [.control, .shift]).refusal == nil)
    #expect(key(kVK_ANSI_K, [.option, .command]).refusal == nil)
    #expect(key(kVK_ANSI_T, [.control, .option, .command]).refusal == nil)
    #expect(key(kVK_ANSI_1, .control).refusal == nil)
}

/// Without ⌃ or ⌘ the key types something — ⇧ capitals, ⌥ accents — in every app at once.
@Test func aKeyYouTypeWithIsRefused() {
    #expect(key(kVK_ANSI_K, []).refusal == .typesText)
    #expect(key(kVK_ANSI_K, .shift).refusal == .typesText)
    #expect(key(kVK_ANSI_E, .option).refusal == .typesText)
    #expect(key(kVK_ANSI_K, [.option, .shift]).refusal == .typesText)
}

@Test func anAppsMenuShortcutIsRefused() {
    #expect(key(kVK_ANSI_W, .command).refusal == .takesAppShortcut)
    #expect(key(kVK_ANSI_N, [.command, .shift]).refusal == .takesAppShortcut)
}

/// ⌃A, ⌃E, ⌃K: the Cocoa text system's own keys.
@Test func controlAndALoneLetterIsRefused() {
    #expect(key(kVK_ANSI_A, .control).refusal == .editsText)
    #expect(key(kVK_ANSI_K, .control).refusal == .editsText)
}

/// A function key has no character to take away.
@Test func aFunctionKeyStandsAlone() {
    #expect(key(kVK_F6, []).refusal == nil)
    #expect(key(kVK_F19, .shift).refusal == nil)
}

// MARK: - Slot chords

/// The chord shows the numbers, so it is held with the pointer on the bar — and a look must not be
/// a click. ⌃-click is the context menu, whatever else is held, which is why every choice has ⌃.
@Test func noSlotChordIsAClickGesture() {
    let item = DockItem(
        kind: .app(AppRef(
            bundleID: "x", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            name: "Finder")),
        isRunning: true)
    for chord in SlotChord.allCases {
        #expect(chord.modifiers.contains(.control))
        #expect(ClickAction.resolve(modifiers: chord.modifiers.eventFlags, for: item) == nil)
    }
}

@Test func noSlotChordIsTheActivityChord() {
    for chord in SlotChord.allCases {
        #expect(chord.modifiers.eventFlags != BarOverlay.activityChord)
    }
}

@Test func eachSlotChordIsTenDistinctKeys() {
    for chord in SlotChord.allCases {
        #expect(Set(chord.combinations).count == 10)
        #expect(chord.combinations.allSatisfy { $0.refusal == nil })
    }
    #expect(SlotChord.controlOption.combinations.last == key(kVK_ANSI_0, [.control, .option]))
}

/// Holding the keys you are about to press is what shows their numbers.
@Test func theSlotOverlayFollowsTheSlotChord() {
    var settings = Settings()
    settings.slotHotKeysEnabled = true
    settings.slotChord = .controlCommand
    let chords = BarOverlay.chords(for: settings)
    #expect(BarOverlay.matching([.control, .command], chords: chords) == .slotNumbers)
    #expect(BarOverlay.matching([.control, .option], chords: chords) == nil)
}

// MARK: - Review

private let quiet: Set<KeyCombination> = []

@Test func theDefaultsHaveNothingToReport() {
    var settings = Settings()
    settings.revealHotKeyEnabled = true
    settings.slotHotKeysEnabled = true
    let review = HotKeyReview(settings: settings, system: quiet)
    for role in HotKeyRole.allCases { #expect(review.problem(for: role) == nil) }
}

/// Reported on both, because which one registers second — and so fails — is not the user's business.
@Test func twoOfOurOwnKeysClashOnBothSides() {
    var settings = Settings()
    settings.revealHotKeyEnabled = true
    settings.revealHotKey = key(kVK_ANSI_3, [.control, .option])
    settings.slotHotKeysEnabled = true
    let review = HotKeyReview(settings: settings, system: quiet)
    #expect(review.problem(for: .reveal) == .ours(.slots, settings.revealHotKey))
    #expect(review.problem(for: .slots) == .ours(.reveal, settings.revealHotKey))

    settings.slotChord = .controlShift
    #expect(HotKeyReview(settings: settings, system: quiet).problem(for: .reveal) == nil)
}

/// A key that is switched off registers nothing, so it clashes with nothing.
@Test func aSwitchedOffKeyClashesWithNothing() {
    var settings = Settings()
    settings.revealHotKey = key(kVK_ANSI_3, [.control, .option])
    settings.slotHotKeysEnabled = true
    #expect(settings.hotKeys(for: .reveal).isEmpty)
    #expect(HotKeyReview(settings: settings, system: quiet).problem(for: .slots) == nil)
}

@Test func aSystemShortcutIsNamed() {
    var settings = Settings()
    let inputSource = key(kVK_Space, .control)
    settings.appsMenuHotKey = .custom
    settings.appsMenuCustomHotKey = inputSource
    let review = HotKeyReview(settings: settings, system: [inputSource])
    #expect(review.problem(for: .appsMenu) == .system(inputSource))
}

/// The vetted choices are exempt from the recorder's rule — ⌥Space is offered knowing what it costs —
/// but not from the system's own shortcuts.
@Test func aVettedChoiceIsNotHeldToTheRecordersRule() {
    var settings = Settings()
    settings.appsMenuHotKey = .optionSpace
    #expect(HotKeyReview(settings: settings, system: quiet).problem(for: .appsMenu) == nil)
    let optionSpace = key(kVK_Space, .option)
    #expect(HotKeyReview(settings: settings, system: [optionSpace]).problem(for: .appsMenu)
        == .system(optionSpace))
}

@Test func aRecordedKeyIsRefusedForTheFirstReasonThatApplies() {
    var settings = Settings()
    settings.revealHotKeyEnabled = true
    let review = HotKeyReview(settings: settings, system: [key(kVK_ANSI_W, .command), key(kVK_Space, .control)])
    // The rule comes first, even when the system also has it.
    #expect(review.refusal(of: key(kVK_ANSI_W, .command), for: .appsMenu) == .takesAppShortcut)
    // Then our own keys.
    #expect(review.refusal(of: KeyCombination.revealDefault, for: .appsMenu)
        == .ours(.reveal, KeyCombination.revealDefault))
    // Then the system's.
    #expect(review.refusal(of: key(kVK_Space, .control), for: .appsMenu) == .system(key(kVK_Space, .control)))
    // Recording the key a role already has is not a clash with itself.
    #expect(review.refusal(of: KeyCombination.revealDefault, for: .reveal) == nil)
}

@Test func aFailedRegistrationIsReportedWhenNothingElseExplainsIt() {
    var settings = Settings()
    settings.revealHotKeyEnabled = true
    let review = HotKeyReview(settings: settings, system: quiet, unavailable: [.reveal])
    #expect(review.problem(for: .reveal) == .unavailable)
    #expect(review.problem(for: .appsMenu) == nil)
}

// MARK: - The system's table

/// Parsed from the shape `CopySymbolicHotKeys` returns, including its function-key bit on arrows.
@Test func systemShortcutsAreReadFromTheSymbolicTable() {
    let entries: [[String: Any]] = [
        ["kHISymbolicHotKeyCode": kVK_Space, "kHISymbolicHotKeyModifiers": cmdKey, "kHISymbolicHotKeyEnabled": true],
        ["kHISymbolicHotKeyCode": kVK_LeftArrow, "kHISymbolicHotKeyModifiers": 135168, "kHISymbolicHotKeyEnabled": true],
        ["kHISymbolicHotKeyCode": kVK_ANSI_1, "kHISymbolicHotKeyModifiers": controlKey, "kHISymbolicHotKeyEnabled": false],
        ["kHISymbolicHotKeyCode": 65535, "kHISymbolicHotKeyModifiers": 0, "kHISymbolicHotKeyEnabled": true],
        ["kHISymbolicHotKeyEnabled": true],
    ]
    #expect(SystemShortcuts.combinations(from: entries) == [
        key(kVK_Space, .command),
        key(kVK_LeftArrow, .control),
    ])
}

// MARK: - Settings

@Test func anOlderSettingsFileGetsTheDefaultKeys() throws {
    let settings = try decodeSettings(#"{"revealHotKeyEnabled": true, "slotHotKeysEnabled": true}"#)
    #expect(settings.revealHotKey == KeyCombination.revealDefault)
    #expect(settings.slotChord == .controlOption)
    #expect(settings.appsMenuCustomHotKey == nil)
}

@Test func recordedKeysSurviveARoundTrip() throws {
    var settings = Settings()
    settings.revealHotKey = key(kVK_ANSI_R, [.control, .option, .command])
    settings.slotChord = .controlShift
    settings.appsMenuHotKey = .custom
    settings.appsMenuCustomHotKey = key(kVK_F13, [])
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
}

/// A file that asks for a bare letter would stop that letter typing anywhere on the Mac, so a
/// hand-edited key is held to the recorder's rule.
@Test func aHandEditedKeyTheRecorderWouldRefuseIsNotRegistered() throws {
    let settings = try decodeSettings("""
        {"revealHotKey": {"keyCode": 40, "modifiers": []},
         "appsMenuHotKey": "custom",
         "appsMenuCustomHotKey": {"keyCode": 13, "modifiers": ["command"]}}
        """)
    #expect(settings.revealHotKey == KeyCombination.revealDefault)
    #expect(settings.appsMenuCustomHotKey == nil)
    #expect(settings.hotKeys(for: .appsMenu).isEmpty)
}

@Test func malformedKeysFallBackWithoutLosingTheFile() throws {
    let settings = try decodeSettings("""
        {"edge": "left", "revealHotKey": "ctrl-alt-d", "slotChord": "hyper",
         "appsMenuCustomHotKey": {"modifiers": ["control"]}}
        """)
    #expect(settings.edge == .left)
    #expect(settings.revealHotKey == KeyCombination.revealDefault)
    #expect(settings.slotChord == .controlOption)
    #expect(settings.appsMenuCustomHotKey == nil)
}

// MARK: - Registration

/// The one failure `RegisterEventHotKey` was measured to report: this process holding the same
/// combination twice. It has to reach the role that lost, not just the log.
@MainActor
@Test func aCombinationRegisteredTwiceIsReportedForTheSecondRole() {
    let hotKey = GlobalHotKey()
    defer { hotKey.unregisterAll() }
    let unusual = key(kVK_F19, [.control, .option, .shift, .command])
    hotKey.setReveal(unusual) {}
    hotKey.setAppsMenu(unusual) {}
    #expect(hotKey.unavailable == [.appsMenu])

    hotKey.setAppsMenu(nil) {}
    #expect(hotKey.unavailable.isEmpty)
}

// MARK: - Moving focus to the bar

/// On by default, so the default has to be a key the recorder itself would accept.
@Test func theFocusKeyIsOnByDefaultAndPassesTheRule() {
    #expect(KeyCombination.focusDefault.refusal == nil)
    #expect(Settings().hotKeys(for: .focus) == [KeyCombination.focusDefault])
    #expect(KeyCombination.focusDefault.displayName(layout: { _ in nil }) == "⌃⌥⇥")
}

/// macOS's own key for this is ⌃F3, switched on by default. Recording it is refused until the
/// system's is turned off — and then it is allowed, which is the way to give the bar the Dock's key.
@Test func theDocksOwnKeyIsTheSystems() {
    let dockFocus = key(kVK_F3, .control)
    var settings = Settings()
    #expect(HotKeyReview(settings: settings, system: [dockFocus]).refusal(of: dockFocus, for: .focus)
        == .system(dockFocus))
    #expect(HotKeyReview(settings: settings, system: quiet).refusal(of: dockFocus, for: .focus) == nil)

    settings.focusHotKey = dockFocus
    #expect(HotKeyReview(settings: settings, system: [dockFocus]).problem(for: .focus) == .system(dockFocus))
}

@Test func theFocusKeyClashesWithOurOthersOnBothSides() {
    var settings = Settings()
    settings.revealHotKeyEnabled = true
    settings.revealHotKey = KeyCombination.focusDefault
    let review = HotKeyReview(settings: settings, system: quiet)
    #expect(review.problem(for: .focus) == .ours(.reveal, KeyCombination.focusDefault))
    #expect(review.problem(for: .reveal) == .ours(.focus, KeyCombination.focusDefault))

    settings.focusHotKeyEnabled = false
    #expect(HotKeyReview(settings: settings, system: quiet).problem(for: .reveal) == nil)
}

@Test func theFocusKeyIsDecodedLikeTheOthers() throws {
    let older = try decodeSettings(#"{"edge": "left"}"#)
    #expect(older.focusHotKeyEnabled)
    #expect(older.focusHotKey == KeyCombination.focusDefault)

    let off = try decodeSettings(#"{"focusHotKeyEnabled": false}"#)
    #expect(off.hotKeys(for: .focus).isEmpty)

    // Held to the recorder's rule, as the reveal key is: a bare letter would stop it typing.
    let bare = try decodeSettings(#"{"focusHotKey": {"keyCode": 40, "modifiers": []}}"#)
    #expect(bare.focusHotKey == KeyCombination.focusDefault)

    var recorded = Settings()
    recorded.focusHotKey = key(kVK_F3, .control)
    let data = try JSONEncoder().encode(recorded)
    #expect(try JSONDecoder().decode(Settings.self, from: data).focusHotKey == recorded.focusHotKey)
}

@MainActor
@Test func aFailedFocusRegistrationIsReportedAsFocus() {
    let hotKey = GlobalHotKey()
    defer { hotKey.unregisterAll() }
    let unusual = key(kVK_F19, [.control, .option, .shift, .command])
    hotKey.setReveal(unusual) {}
    hotKey.setFocus(unusual) {}
    #expect(hotKey.unavailable == [.focus])
}
