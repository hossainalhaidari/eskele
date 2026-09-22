import Carbon.HIToolbox
import Foundation
import Testing
@testable import Eskele

/// The Windows key's job needs a key macOS is not already using. Measured against
/// `com.apple.symbolichotkeys`: ⌃Space and ⌃⌥Space are input-source switching, ⌘Space is Spotlight
/// and ⌥⌘Space is Finder search — so the two registerable choices are what is left.
@Test func theTwoRegisterableShortcutsAreTheOnesMacOSDoesNotUse() {
    let control = AppsMenuHotKey.controlEscape.combination(custom: nil)
    #expect(control?.keyCode == UInt32(kVK_Escape))
    #expect(control?.modifiers.rawValue == UInt32(controlKey))

    let option = AppsMenuHotKey.optionSpace.combination(custom: nil)
    #expect(option?.keyCode == UInt32(kVK_Space))
    #expect(option?.modifiers.rawValue == UInt32(optionKey))
}

/// Neither of these is a key combination, so neither has anything for Carbon to register: "off" is
/// nothing at all, and the right ⌘ tap is watched for instead.
@Test func theOtherTwoChoicesRegisterNothing() {
    let recorded = KeyCombination(keyCode: kVK_ANSI_L, modifiers: [.control, .option])
    #expect(AppsMenuHotKey.off.combination(custom: recorded) == nil)
    #expect(AppsMenuHotKey.rightCommand.combination(custom: recorded) == nil)
}

/// The recorded key is used only when chosen, and a vetted choice ignores it rather than losing it.
@Test func aCustomShortcutRegistersWhatWasRecorded() {
    let recorded = KeyCombination(keyCode: kVK_ANSI_L, modifiers: [.control, .option])
    #expect(AppsMenuHotKey.custom.combination(custom: recorded) == recorded)
    #expect(AppsMenuHotKey.custom.combination(custom: nil) == nil)
    #expect(AppsMenuHotKey.controlEscape.combination(custom: recorded) != recorded)
}

/// The permission is the one thing that separates the choices, so it has to be reported per choice
/// — the preferences pane says so at the moment of choosing.
@Test func onlyTheLoneModifierCostsAPermission() {
    #expect(AppsMenuHotKey.rightCommand.needsAccessibility)
    #expect(!AppsMenuHotKey.controlEscape.needsAccessibility)
    #expect(!AppsMenuHotKey.optionSpace.needsAccessibility)
    #expect(!AppsMenuHotKey.off.needsAccessibility)
    #expect(!AppsMenuHotKey.custom.needsAccessibility)
}

/// ⌃Esc out of the box: a single combination macOS does not use, unlike the ten slot keys that are
/// opted into because they are likely to collide.
@Test func theAppsMenuShortcutIsOnByDefault() {
    #expect(Settings().appsMenuHotKey == .controlEscape)
}

/// Every choice needs a label the picker can show and a line saying what it costs.
@Test func everyShortcutChoiceDescribesItself() {
    for shortcut in AppsMenuHotKey.allCases {
        #expect(!shortcut.title.isEmpty)
        #expect(!shortcut.detail.isEmpty)
    }
}

/// A settings file written before this existed has no key for it, and must come back with the
/// default rather than nothing.
@Test func anOlderSettingsFileGetsTheDefaultShortcut() throws {
    let json = #"{"edge":"bottom"}"#
    let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    #expect(settings.appsMenuHotKey == .controlEscape)
}

/// A file naming a choice this build does not have must not throw the rest of the settings away.
@Test func anUnknownShortcutFallsBackWithoutLosingTheFile() throws {
    let json = #"{"edge":"right","appsMenuHotKey":"middleClickTheMoon"}"#
    let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    #expect(settings.appsMenuHotKey == .controlEscape)
    #expect(settings.edge == .right)
}
