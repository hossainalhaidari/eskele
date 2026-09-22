import Foundation
import Testing
import TrashKit
@testable import Eskele

/// The contract that makes a new language a copy-and-translate job rather than a hunt.
///
/// Three things have to hold, and none of them can be seen by running the app in English:
///
/// - every localizable string in the source has an entry in `en.lproj`, or it silently stays English
///   in every language;
/// - every entry in `en.lproj` is still used by some string in the source, or translators are paid
///   to translate dead text;
/// - every other `.lproj` holds exactly the keys English does, so a language is either complete or
///   says which lines are missing.
///
/// A failure prints the keys rather than a count, and `ESKELE_DUMP_STRINGS=1 swift test` writes a
/// ready-made catalogue to `/tmp` — which is how `en.lproj/Localizable.strings` was built in the
/// first place.
@Suite struct LocalizationTests {
    /// Interpolated keys are matched as patterns: the specifier Foundation generates depends on the
    /// interpolated type (`%lld` for a count, `%@` for a name), which the source text does not say.
    private static let specifier = "%(?:[0-9]+\\$)?(?:@|lld|ld|d|u|f|lf|\\.[0-9]+f)"

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EskeleTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
    }

    private static var englishDirectory: URL {
        repositoryRoot.appendingPathComponent("Resources/en.lproj")
    }

    /// Every localizable string the source contains, by pattern.
    private static let scanned: [LocalizableScan.Found] = {
        let sources = repositoryRoot.appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        var found: [LocalizableScan.Found] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            found += (try? LocalizableScan.scan(file: url)) ?? []
        }
        return found
    }()

    // MARK: - The catalogue covers the source

    @Test func everyLocalizableStringHasAnEnglishEntry() throws {
        let catalogue = try Self.keys(inStringsAt: Self.englishDirectory)
        let plurals = try Self.pluralKeys(at: Self.englishDirectory)
        let available = catalogue.union(plurals)

        Self.dumpIfAsked(existing: catalogue)

        let missing = Self.scanned.filter { found in
            !available.contains { Self.key($0, matches: found.pattern) }
        }
        #expect(
            missing.isEmpty,
            """
            \(missing.count) string(s) in the source have no entry in Resources/en.lproj. \
            Add them to Localizable.strings (or Localizable.stringsdict if one takes a count):
            \(missing.map { "  \($0.file):\($0.line)  \(Self.display($0.pattern))" }.joined(separator: "\n"))
            """)
    }

    /// The other direction. A key nobody asks for any more is a line every translator still pays
    /// for, and nothing in the running app would ever reveal it.
    @Test func theEnglishCatalogueHasNothingSpare() throws {
        let catalogue = try Self.keys(inStringsAt: Self.englishDirectory)
        let patterns = Set(Self.scanned.map(\.pattern))

        let orphans = catalogue.filter { key in
            !patterns.contains { Self.key(key, matches: $0) }
        }
        #expect(
            orphans.isEmpty,
            """
            \(orphans.count) entr(y/ies) in Resources/en.lproj/Localizable.strings match no string \
            in the source. Remove them:
            \(orphans.sorted().map { "  \($0)" }.joined(separator: "\n"))
            """)
    }

    /// English is the development language, so a value that is not simply the key back again means
    /// somebody has edited the wrong column.
    @Test func englishValuesAreTheirOwnKeys() throws {
        let entries = try Self.entries(inStringsAt: Self.englishDirectory)
        let edited = entries.filter { $0.key != $0.value }.map(\.key)
        #expect(
            edited.isEmpty,
            """
            In en.lproj the value is the English text, so it must equal the key. These differ:
            \(edited.sorted().map { "  \($0)" }.joined(separator: "\n"))
            """)
    }

    // MARK: - Every other language matches English

    /// What makes adding a language checkable: German is complete, or this says which lines are not.
    @Test func everyTranslationCoversTheSameKeysAsEnglish() throws {
        let english = try Self.keys(inStringsAt: Self.englishDirectory)

        for directory in try Self.localizationDirectories() {
            let language = directory.deletingPathExtension().lastPathComponent
            guard language != "en" else { continue }
            let translated = try Self.keys(inStringsAt: directory)

            let missing = english.subtracting(translated).sorted()
            let spare = translated.subtracting(english).sorted()
            #expect(
                missing.isEmpty,
                """
                \(language) is missing \(missing.count) key(s):
                \(missing.map { "  \($0)" }.joined(separator: "\n"))
                """)
            #expect(
                spare.isEmpty,
                """
                \(language) has \(spare.count) key(s) English does not:
                \(spare.map { "  \($0)" }.joined(separator: "\n"))
                """)
        }
    }

    /// A plural rule is per language — Polish needs three forms where English needs two — so the
    /// keys have to line up even though the number of forms behind each one does not.
    @Test func everyTranslationCoversTheSamePluralsAsEnglish() throws {
        let english = try Self.pluralKeys(at: Self.englishDirectory)

        for directory in try Self.localizationDirectories() {
            let language = directory.deletingPathExtension().lastPathComponent
            guard language != "en" else { continue }
            let translated = try Self.pluralKeys(at: directory)
            let missing = english.subtracting(translated).sorted()
            #expect(
                missing.isEmpty,
                """
                \(language) has no plural rule for \(missing.count) key(s):
                \(missing.map { "  \($0)" }.joined(separator: "\n"))
                """)
        }
    }

    /// The counted strings resolve through the catalogue rather than falling back to the key, and
    /// the two forms English declares are actually different. `1 items` is the kind of thing that
    /// makes a dialog look unfinished, and it is invisible until somebody has exactly one.
    @Test func theEnglishPluralFormsAreApplied() throws {
        let bundle = try #require(Bundle(url: Self.englishDirectory.deletingLastPathComponent()))
        let one = TrashPrompt.message(for: TrashSnapshot(count: 1, isExact: true), bundle: bundle)
        let many = TrashPrompt.message(for: TrashSnapshot(count: 4, isExact: true), bundle: bundle)

        #expect(one.contains("1 item in"))
        #expect(!one.contains("items"))
        #expect(many.contains("4 items in"))

        // What VoiceOver says of an app with one window open — `CellDescription`.
        let count = 1
        #expect(String(localized: "\(count) windows", bundle: bundle) == "1 window")
    }

    // MARK: - Reading the catalogues

    private static func localizationDirectories() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: repositoryRoot.appendingPathComponent("Resources"),
                                 includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func entries(inStringsAt directory: URL) throws -> [(key: String, value: String)] {
        let url = directory.appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        guard let table = try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: String]
        else { throw CocoaError(.propertyListReadCorrupt) }
        return table.map { (key: $0.key, value: $0.value) }
    }

    private static func keys(inStringsAt directory: URL) throws -> Set<String> {
        Set(try entries(inStringsAt: directory).map(\.key))
    }

    private static func pluralKeys(at directory: URL) throws -> Set<String> {
        let url = directory.appendingPathComponent("Localizable.stringsdict")
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let table = try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any]
        else { throw CocoaError(.propertyListReadCorrupt) }
        return Set(table.keys)
    }

    /// Whether a catalogue key is the same string as a scanned pattern, treating each interpolation
    /// as "some format specifier".
    private static func key(_ key: String, matches pattern: String) -> Bool {
        guard pattern.contains(LocalizableScan.interpolation) else { return key == pattern }
        let expression = pattern
            .split(separator: LocalizableScan.interpolation, omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: specifier)
        let range = NSRange(key.startIndex..., in: key)
        return (try? NSRegularExpression(pattern: "^" + expression + "$"))?
            .firstMatch(in: key, range: range) != nil
    }

    private static func display(_ pattern: String) -> String {
        pattern
            .replacingOccurrences(of: String(LocalizableScan.interpolation), with: "%@")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Writes what the catalogue would look like if it were generated from the source right now.
    /// Not a test — a way to start a catalogue, or to see a diff when one has drifted a long way.
    private static func dumpIfAsked(existing: Set<String>) {
        guard ProcessInfo.processInfo.environment["ESKELE_DUMP_STRINGS"] == "1" else { return }
        var lines: [String] = [
            "/* Generated by ESKELE_DUMP_STRINGS=1 swift test. Interpolated keys need their",
            "   specifier chosen by hand: %lld for a count, %@ for a name. */",
            "",
        ]
        // One entry per key, with every place it is used, because the same words in two panes are
        // one line for a translator rather than two.
        let sites = Dictionary(grouping: scanned, by: \.pattern)
        for pattern in sites.keys.sorted() {
            let key = escaped(pattern)
                .replacingOccurrences(of: String(LocalizableScan.interpolation), with: "%@")
            let uses = sites[pattern] ?? []
            let where_ = uses.map { "\($0.file):\($0.line)" }.sorted().joined(separator: ", ")
            // The note the author wrote for whoever translates this, where there was one.
            let note = uses.compactMap(\.comment).first
            lines.append(note.map { "/* \($0)\n   \(where_) */" } ?? "/* \(where_) */")
            lines.append("\"\(key)\" = \"\(key)\";")
            lines.append("")
        }
        let url = URL(fileURLWithPath: "/tmp/Eskele-Localizable.strings")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("wrote \(scanned.count) scanned keys (\(existing.count) already present) to \(url.path)")
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
