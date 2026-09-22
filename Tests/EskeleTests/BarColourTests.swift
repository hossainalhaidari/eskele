import AppKit
import Testing
@testable import Eskele

// MARK: - Appearance

/// Following the system means inheriting, which is `nil` — not "aqua". Pinning it to aqua would
/// freeze the bar in light mode for everyone who never touched the setting.
@MainActor
@Test func matchingTheSystemInheritsRatherThanPickingOne() {
    #expect(Settings().appearance == .system)
    #expect(BarAppearance.system.nsAppearance == nil)
    #expect(BarAppearance.light.nsAppearance?.name == .aqua)
    #expect(BarAppearance.dark.nsAppearance?.name == .darkAqua)
}

// MARK: - Custom colour

/// The custom material is a flat colour, so the vibrancy view has to be out of the way. Drawing a
/// colour *over* a blur gives neither: 80% black over a blurred desktop is darker than 80% black
/// and moves when the wallpaper does.
@MainActor
@Test func onlyTheCustomMaterialTurnsVibrancyOff() {
    for material in BarMaterial.allCases {
        #expect(material.usesVibrancy == (material != .custom))
    }
    #expect(BarMaterial.custom.usesVibrancy == false)
}

@MainActor
@Test func aTintBecomesTheColourItDescribes() {
    let tint = BarTint(red: 0.2, green: 0.4, blue: 0.6, opacity: 0.5)
    let colour = tint.color.usingColorSpace(.sRGB)!
    #expect(abs(colour.redComponent - 0.2) < 0.001)
    #expect(abs(colour.greenComponent - 0.4) < 0.001)
    #expect(abs(colour.blueComponent - 0.6) < 0.001)
    #expect(abs(colour.alphaComponent - 0.5) < 0.001)
}

/// `settings.json` is meant to be hand-editable, so a number outside 0…1 has to mean something
/// rather than produce an invalid colour.
@MainActor
@Test func componentsOutsideTheRangeAreClamped() {
    let tint = BarTint(red: -3, green: 42, blue: 0.5, opacity: 9)
    let colour = tint.color.usingColorSpace(.sRGB)!
    #expect(colour.redComponent == 0)
    #expect(colour.greenComponent == 1)
    #expect(colour.alphaComponent == 1)
}

/// Round-tripping a picked colour must not shift it: the picker hands back an NSColor in whatever
/// space it likes, and storing that without converting is how a chosen grey comes back a shade off.
@MainActor
@Test func aPickedColourSurvivesBeingStored() throws {
    let picked = NSColor(calibratedRed: 0.3, green: 0.55, blue: 0.8, alpha: 1)
    let tint = BarTint(color: picked, opacity: 0.7)
    let stored = try JSONDecoder().decode(BarTint.self, from: JSONEncoder().encode(tint))
    #expect(stored == tint)

    let expected = picked.usingColorSpace(.sRGB)!
    let actual = stored.color.usingColorSpace(.sRGB)!
    #expect(abs(actual.redComponent - expected.redComponent) < 0.001)
    #expect(abs(actual.blueComponent - expected.blueComponent) < 0.001)
    // Opacity is the slider's, not the picked colour's.
    #expect(abs(actual.alphaComponent - 0.7) < 0.001)
}

// MARK: - Settings

@MainActor
@Test func theNewAppearanceKeysDefaultAndDecodeLeniently() throws {
    #expect(Settings().material == .menu)
    #expect(Settings().tint.opacity > 0)

    // A file written before any of this existed.
    let old = try #require(try? JSONDecoder().decode(
        Settings.self, from: Data(#"{"edge":"left"}"#.utf8)))
    #expect(old.appearance == .system)
    #expect(old.material == .menu)
    #expect(old.tint == BarTint())

    // A typo costs that key and nothing else.
    let typo = try #require(try? JSONDecoder().decode(
        Settings.self, from: Data(#"{"appearance":"gloomy","material":"custom"}"#.utf8)))
    #expect(typo.appearance == .system)
    #expect(typo.material == .custom)
}

@MainActor
@Test func appearanceAndTintRoundTrip() throws {
    var settings = Settings()
    settings.appearance = .dark
    settings.material = .custom
    settings.tint = BarTint(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.66)
    let decoded = try JSONDecoder().decode(
        Settings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
}
