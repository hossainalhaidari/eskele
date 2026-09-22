import Foundation

/// What one app is costing, right now.
struct ActivitySample: Equatable, Sendable {
    /// Percent of one core, as Activity Monitor reports it — so a busy app can exceed 100.
    ///
    /// Nil until two samples exist to subtract. Memory needs no such wait, which is why the two are
    /// not reported together: the bar can show a figure immediately rather than an empty cell.
    var cpu: Double?
    /// Physical footprint in bytes — the figure Activity Monitor's Memory column shows, rather than
    /// resident size, which counts pages the app no longer owns.
    var memory: UInt64

    /// Rendered for a cell with room for two short lines.
    static func cpuText(_ percent: Double?) -> String {
        guard let percent else { return "—" }
        // Under 10% the first decimal is the whole story; above it, it is noise.
        if percent < 9.95 { return String(format: "%.1f%%", max(0, percent)) }
        return "\(Int(min(9999, percent.rounded())))%"
    }

    /// Bytes as a person would say them: three significant figures at most, and no decimal point
    /// where it would only add a digit that changes every sample.
    static func memoryText(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return "<1 MB" }
        if mb < 1000 { return "\(Int(mb.rounded())) MB" }
        let gb = mb / 1024
        return gb < 10 ? String(format: "%.1f GB", gb) : "\(Int(gb.rounded())) GB"
    }

    /// The same figure with the unit shortened to one letter, for a cell one icon thick.
    static func compactMemoryText(_ bytes: UInt64) -> String {
        memoryText(bytes)
            .replacingOccurrences(of: " MB", with: "M")
            .replacingOccurrences(of: " GB", with: "G")
    }
}
