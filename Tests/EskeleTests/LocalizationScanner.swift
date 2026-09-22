import Foundation

/// Finds every string in the source tree that macOS will try to translate.
///
/// The catalogue is the one thing here that cannot be checked by using the app: a missing entry
/// looks exactly like a translation nobody has got to yet, in a language the author does not read.
/// So the source is scanned instead, and `LocalizationTests` asserts that what the scan finds and
/// what `en.lproj` holds are the same set.
///
/// Two shapes are localizable, and they are localizable for different reasons:
///
/// 1. `String(localized:)` and `NSLocalizedString`, which say so outright. Everything outside
///    SwiftUI uses these.
/// 2. A bare literal in a SwiftUI label position — `Text("…")`, `Toggle("…", isOn:)`, `.help("…")`.
///    These are `LocalizedStringKey`, so SwiftUI looks them up in `Bundle.main` whether or not the
///    author was thinking about translation. They are the ones worth scanning for: nothing at the
///    call site marks them, so nothing but a scan would notice one going missing.
///
/// A literal carrying `\(…)` becomes a *pattern* rather than a key, because the format specifier
/// Foundation generates depends on the interpolated type — `%lld` for a count, `%@` for a name —
/// and the type is not knowable from the text. The matching in `LocalizationTests` is by pattern
/// accordingly.
enum LocalizableScan {
    /// Marks where an interpolation stood, so the key can be turned into a pattern later. A control
    /// character, because no real key contains one.
    static let interpolation: Character = "\u{1}"

    struct Found: Hashable {
        /// The literal with each `\(…)` replaced by ``interpolation``.
        var pattern: String
        /// What the `comment:` argument said, where there was one. A SwiftUI literal has no such
        /// argument, so this is nil for those and the catalogue falls back to naming the file.
        var comment: String?
        var file: String
        var line: Int

        /// Whether the key is a plain string, which is what lets the test tell a missing
        /// `Localizable.strings` entry from a missing `.stringsdict` rule.
        var isPlain: Bool { !pattern.contains(LocalizableScan.interpolation) }
    }

    /// Call shapes whose *first* argument macOS treats as a localizable key.
    ///
    /// `.help` is in the list because every one in this codebase picks between two literals with a
    /// ternary, so there is no single first argument to take — all the literals in the call are
    /// keys.
    private static let callShapes = [
        "String(", "NSLocalizedString(",
        "Text(", "Toggle(", "Button(", "Picker(", "LabeledContent(", "Label(", "Section(",
        "Stepper(", "TextField(", "Link(", ".help(",
    ]

    /// Argument labels whose literal is never a key: a symbol name, an identifier, the translator's
    /// comment, or a string the author explicitly marked as not for translation.
    private static let skippedLabels = [
        "verbatim:", "systemName:", "systemSymbolName:", "accessibilityDescription:",
        "identifier:", "named:", "forKey:", "comment:", "table:", "tableName:", "bundle:",
        "value:", "key:",
    ]

    static func scan(file url: URL) throws -> [Found] {
        let source = try String(contentsOf: url, encoding: .utf8)
        let name = url.lastPathComponent
        let literals = self.literals(in: source)
        let lineStarts = self.lineStarts(in: source)
        // Comments are blanked rather than deleted, so every offset still refers to the same place
        // in the original text.
        let skeleton = Array(blankingCommentsAndStrings(source))

        var found: Set<Found> = []
        for shape in callShapes {
            for start in ranges(of: shape, in: skeleton) {
                guard let end = endOfCall(from: start + shape.count - 1, in: skeleton) else { continue }
                let inCall = literals.filter { $0.start > start && $0.end <= end }
                // The `comment:` argument of this same call, which is the note the translator reads.
                let comment = inCall.first { $0.label == "comment:" }?.pattern

                for literal in inCall {
                    guard !literal.isSkipped else { continue }
                    // A key may open with a letter, an opening quote, a modifier key's symbol, or
                    // the value itself — "%lld items" is a key; "launcher" as a table-column
                    // identifier is not. The modifier symbols are here because a sentence about a
                    // shortcut starts with one ("⌘ shortcuts belong to…"), and without them such a
                    // sentence went uncatalogued with nothing to say so.
                    guard let first = literal.pattern.first,
                          first.isLetter || "“⌃⌥⇧⌘".contains(first) || first == interpolation
                    else { continue }
                    guard literal.pattern.count > 1 else { continue }
                    found.insert(
                        Found(
                            pattern: literal.pattern,
                            comment: comment,
                            file: name,
                            line: line(of: literal.start, in: lineStarts)))
                }
            }
        }
        return found.sorted { ($0.file, $0.line, $0.pattern) < ($1.file, $1.line, $1.pattern) }
    }

    // MARK: - Literals

    private struct Literal {
        var pattern: String
        var start: Int
        var end: Int
        /// The argument label in front of it, where there is one.
        var label: String?
        var isSkipped: Bool { label.map(skippedLabels.contains) ?? false }
    }

    /// Every string literal in the file, with `\(…)` collapsed to ``interpolation`` and a multi-line
    /// literal reduced to the string Swift would actually build from it.
    private static func literals(in source: String) -> [Literal] {
        let characters = Array(source)
        var result: [Literal] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    while index < characters.count, characters[index] != "\n" { index += 1 }
                    continue
                }
                if characters[index + 1] == "*" {
                    index += 2
                    while index + 1 < characters.count,
                          !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                    index = min(index + 2, characters.count)
                    continue
                }
            }

            guard character == "\"" else { index += 1; continue }

            let start = index
            let isMultiline = characters.count >= index + 3
                && characters[index + 1] == "\"" && characters[index + 2] == "\""
            index += isMultiline ? 3 : 1

            var body = ""
            while index < characters.count {
                if characters[index] == "\\", index + 1 < characters.count {
                    if characters[index + 1] == "(" {
                        index += 2
                        var depth = 1
                        while index < characters.count, depth > 0 {
                            if characters[index] == "(" { depth += 1 }
                            if characters[index] == ")" { depth -= 1 }
                            index += 1
                        }
                        body.append(interpolation)
                        continue
                    }
                    // A line continuation inside a multi-line literal joins the lines with nothing.
                    if isMultiline, characters[index + 1] == "\n" {
                        index += 2
                        while index < characters.count, characters[index] == " " { index += 1 }
                        continue
                    }
                    body.append(escape(characters[index + 1]))
                    index += 2
                    continue
                }
                if isMultiline {
                    if characters[index] == "\"", index + 2 < characters.count,
                       characters[index + 1] == "\"", characters[index + 2] == "\"" {
                        index += 3
                        break
                    }
                } else if characters[index] == "\"" {
                    index += 1
                    break
                } else if characters[index] == "\n" {
                    break
                }
                body.append(characters[index])
                index += 1
            }

            result.append(
                Literal(
                    pattern: isMultiline ? trimMultiline(body) : body,
                    start: start,
                    end: index,
                    label: label(before: start, in: characters)))
        }
        return result
    }

    private static func escape(_ character: Character) -> String {
        switch character {
        case "n": "\n"
        case "t": "\t"
        default: String(character)
        }
    }

    /// Swift strips the closing delimiter's indentation from every line of a `"""` literal, and the
    /// literal opens and closes on lines of its own.
    private static func trimMultiline(_ body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        guard lines.count >= 2 else { return body.trimmingCharacters(in: .whitespaces) }
        let closing = lines.removeLast()
        let indent = closing.prefix { $0 == " " }.count
        if lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        return lines
            .map { String($0.dropFirst(min(indent, $0.prefix { $0 == " " }.count))) }
            .joined(separator: "\n")
    }

    /// The argument label immediately in front of this literal, which is what says whether it is a
    /// key, a translator's comment, or a symbol name that is neither.
    private static func label(before start: Int, in characters: [Character]) -> String? {
        var index = start - 1
        while index >= 0, characters[index] == " " || characters[index] == "\n" { index -= 1 }
        guard index >= 0, characters[index] == ":" else { return nil }
        var name = ":"
        index -= 1
        while index >= 0, characters[index].isLetter || characters[index] == "_" {
            name = String(characters[index]) + name
            index -= 1
        }
        return name.count > 1 ? name : nil
    }

    // MARK: - Calls

    /// Comments and the insides of string literals, blanked to spaces, so searching for a call shape
    /// cannot match text that only looks like code.
    private static func blankingCommentsAndStrings(_ source: String) -> String {
        var result = ""
        let all = Array(source)
        var index = 0

        func blank(_ count: Int) { result += String(repeating: " ", count: count) }
        while index < all.count {
            if all[index] == "/", index + 1 < all.count, all[index + 1] == "/" {
                let start = index
                while index < all.count, all[index] != "\n" { index += 1 }
                blank(index - start)
                continue
            }
            if all[index] == "\"" {
                let isMultiline = index + 2 < all.count && all[index + 1] == "\"" && all[index + 2] == "\""
                let start = index
                index += isMultiline ? 3 : 1
                while index < all.count {
                    if all[index] == "\\" { index += 2; continue }
                    if isMultiline, all[index] == "\"", index + 2 < all.count,
                       all[index + 1] == "\"", all[index + 2] == "\"" { index += 3; break }
                    if !isMultiline, all[index] == "\"" { index += 1; break }
                    if !isMultiline, all[index] == "\n" { break }
                    index += 1
                }
                // The quotes are kept so a literal still reads as an argument; only the text goes.
                result += "\""
                blank(max(0, index - start - 2))
                result += "\""
                continue
            }
            result.append(all[index])
            index += 1
        }
        return result
    }

    private static func ranges(of needle: String, in haystack: [Character]) -> [Int] {
        let target = Array(needle)
        guard !target.isEmpty, haystack.count >= target.count else { return [] }
        var result: [Int] = []
        for start in 0...(haystack.count - target.count)
        where Array(haystack[start..<(start + target.count)]) == target {
            // `.help(` is a member call; the rest must not be the tail of a longer identifier.
            if !needle.hasPrefix("."), start > 0 {
                let before = haystack[start - 1]
                if before.isLetter || before.isNumber || before == "_" || before == "." { continue }
            }
            result.append(start)
        }
        return result
    }

    /// The offset of the `)` closing the call that opens at `open`.
    private static func endOfCall(from open: Int, in characters: [Character]) -> Int? {
        var depth = 0
        var index = open
        while index < characters.count {
            if characters[index] == "(" { depth += 1 }
            if characters[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    /// Offsets of the first character of each line, so a literal's line is a binary search rather
    /// than a count from the top of the file.
    private static func lineStarts(in source: String) -> [Int] {
        var starts = [0]
        for (offset, character) in source.enumerated() where character == "\n" {
            starts.append(offset + 1)
        }
        return starts
    }

    private static func line(of offset: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low + 1
    }
}
