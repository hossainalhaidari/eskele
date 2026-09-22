import Foundation

/// Reads back our own code signature, so `--diagnose` can explain permission problems.
enum Diagnostics {
    /// Where `--diagnose` leaves its report, so a LaunchServices-started run can be read back.
    static var reportPath: String {
        SupportDirectory.url.appendingPathComponent("diagnose.txt").path
    }

    /// Where `--diagnose-windows` leaves its report, for the same reason.
    static var windowReportPath: String {
        SupportDirectory.url.appendingPathComponent("diagnose-windows.txt").path
    }

    /// Where `--diagnose-progress` leaves its report, for the same reason.
    static var progressReportPath: String {
        SupportDirectory.url.appendingPathComponent("diagnose-progress.txt").path
    }

    /// Where `--diagnose-badges` leaves its report, for the same reason.
    static var badgeReportPath: String {
        SupportDirectory.url.appendingPathComponent("diagnose-badges.txt").path
    }

    static func writeReport(_ report: String, to path: String? = nil) {
        let url = URL(fileURLWithPath: path ?? reportPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The rule macOS matches this app against when deciding whether a granted permission still
    /// applies. An ad-hoc signature yields a bare `cdhash`, which changes on every build.
    static func designatedRequirement() -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code
        else { return "unknown" }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement
        else { return "unknown" }

        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else {
            return "unknown"
        }
        return text as String
    }

    static func signingSummary(requirement: String) -> String {
        if requirement.contains("cdhash") { return "ad-hoc (identity changes every build)" }
        if let range = requirement.range(of: #"leaf\[subject.CN\] = "([^"]+)""#, options: .regularExpression) {
            return String(requirement[range])
                .replacingOccurrences(of: "leaf[subject.CN] = ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return "certificate (stable identity)"
    }
}
