import Foundation
import Testing
@testable import Eskele

private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

private func parse(_ string: String) -> Result<ScriptCommand, ScriptCommand.ParseError> {
    ScriptCommand.parse(URL(string: string)!, home: home)
}

// MARK: - Commands

@Test func everyCommandParses() {
    #expect(parse("eskele://edge/left") == .success(.edge(.left)))
    #expect(parse("eskele://autohide/on") == .success(.autohide(.on)))
    #expect(parse("eskele://autohide/off") == .success(.autohide(.off)))
    #expect(parse("eskele://design/unity") == .success(.design(.unity)))
    #expect(parse("eskele://design/custom") == .success(.design(.custom)))
    #expect(parse("eskele://reveal") == .success(.reveal))
    #expect(parse("eskele://apps-menu") == .success(.appsMenu))
    #expect(parse("eskele://focus") == .success(.focus))
    #expect(parse("eskele://settings") == .success(.settings))
}

/// A bare `autohide` is the menu item: it flips.
@Test func autohideWithoutAnArgumentToggles() {
    #expect(parse("eskele://autohide") == .success(.autohide(.toggle)))
}

/// Typed by hand into a launcher, a URL comes in every case, with or without the slashes and with
/// a trailing slash some tools add.
@Test func theSpellingIsForgiving() {
    #expect(parse("ESKELE://Edge/RIGHT") == .success(.edge(.right)))
    #expect(parse("eskele:edge/bottom") == .success(.edge(.bottom)))
    #expect(parse("eskele://edge/left/") == .success(.edge(.left)))
}

@Test func whatIsNotACommandIsReportedAsSuch() {
    #expect(parse("eskele://quit") == .failure(.unknownCommand("quit")))
    #expect(parse("eskele://edge/top") == .failure(.badArgument(command: "edge", argument: "top")))
    #expect(parse("eskele://edge") == .failure(.badArgument(command: "edge", argument: "")))
    #expect(parse("eskele://autohide/maybe")
        == .failure(.badArgument(command: "autohide", argument: "maybe")))
    #expect(parse("https://eskele.app/edge/left") == .failure(.notEskele))
}

// MARK: - Pinning

@Test func pinTakesPathsAndApps() {
    #expect(parse("eskele://pin?path=/Applications/Safari.app&app=com.apple.mail")
        == .success(.pin([
            .path(URL(fileURLWithPath: "/Applications/Safari.app")),
            .app(bundleID: "com.apple.mail"),
        ])))
    #expect(parse("eskele://unpin?app=com.apple.mail") == .success(.unpin([.app(bundleID: "com.apple.mail")])))
}

/// A path in a query string is percent-encoded, and `~` is the user's home on this Mac.
@Test func pathsAreDecodedAndTildeIsHome() {
    #expect(parse("eskele://pin?path=~/My%20Projects") == .success(.pin([
        .path(URL(fileURLWithPath: "/Users/someone/My Projects")),
    ])))
}

/// Relative to what? A URL carries no working directory.
@Test func aRelativePathIsNotATarget() {
    #expect(parse("eskele://pin?path=Downloads") == .failure(.noTarget("pin")))
    #expect(parse("eskele://pin") == .failure(.noTarget("pin")))
    #expect(parse("eskele://pin?path=") == .failure(.noTarget("pin")))
}

// MARK: - What changes

@Test func onlyTheSettingsCommandsChangeSettings() {
    let settings = Settings()
    #expect(ScriptCommand.edge(.right).applied(to: settings)?.edge == .right)
    #expect(ScriptCommand.design(.classic).applied(to: settings)
        == DesignPreset.classic.applied(to: settings))
    for command: ScriptCommand in [.reveal, .appsMenu, .focus, .settings, .pin([]), .unpin([])] {
        #expect(command.applied(to: settings) == nil)
    }
}

/// As the menu does it: a reveal key left on for a bar that no longer hides would be a global
/// shortcut that does nothing.
@Test func turningAutohideOffTurnsTheRevealKeyOff() throws {
    var settings = Settings()
    settings.autohide = true
    settings.revealHotKeyEnabled = true
    let off = try #require(ScriptCommand.autohide(.off).applied(to: settings))
    #expect(!off.autohide)
    #expect(!off.revealHotKeyEnabled)
    let toggled = try #require(ScriptCommand.autohide(.toggle).applied(to: off))
    #expect(toggled.autohide)
}

/// The scheme in Info.plist is the one the code answers to; nothing else ties the two together.
@Test func infoPlistClaimsTheScheme() throws {
    let plist = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Info.plist")
    let info = try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
            as? [String: Any])
    let types = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
    let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    #expect(schemes == [ScriptCommand.scheme])
}

// MARK: - Shortcuts

/// The Shortcuts choices are their own enums, because App Intents wants its own conformances; these
/// keep them in step with the bar's, so a new edge or design cannot be missing from Shortcuts
/// without a failure saying so.
@Test func everyEdgeAndDesignHasAShortcutsChoice() {
    #expect(Set(EdgeChoice.allCases.map(\.edge)) == Set(BarEdge.allCases))
    #expect(Set(DesignChoice.allCases.map(\.preset)) == Set(DesignPreset.allCases))
    #expect(SwitchChoice.allCases.map(\.value) == [.on, .off, .toggle])
}

/// The URL and the action are one command, so they cannot come to mean different things.
@Test func aShortcutsChoiceIsTheURLsArgument() {
    for choice in EdgeChoice.allCases {
        #expect(parse("eskele://edge/\(choice.rawValue)") == .success(.edge(choice.edge)))
    }
    for choice in DesignChoice.allCases {
        #expect(parse("eskele://design/\(choice.rawValue)") == .success(.design(choice.preset)))
    }
    for choice in SwitchChoice.allCases {
        #expect(parse("eskele://autohide/\(choice.rawValue)") == .success(.autohide(choice.value)))
    }
}
