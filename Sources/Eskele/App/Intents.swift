import AppIntents

/// The bar's actions in Shortcuts, which also makes them reachable from Spotlight, Siri and anything
/// else that runs App Intents. Each one is a `ScriptCommand` — the same commands an `eskele://` URL
/// sends — carried out by the same code, so the two routes cannot drift apart.
///
/// **Building them.** Shortcuts learns what an app can do from `Metadata.appintents` in its bundle,
/// which Xcode writes and SwiftPM, knowing nothing of bundles, does not. Swift Build — SwiftPM's
/// backend since 6.4 — already emits the compiler's const values for these types, so
/// `Scripts/build-app.sh` runs Xcode's `appintentsmetadataprocessor` over them. Without Xcode the
/// step is skipped and the app works as before, just without the actions.
///
/// **Titles.** Written as `LocalizedStringResource("…", comment:)` rather than bare literals, which
/// is what lets `LocalizationScanner` find them: a bare literal assigned to a `LocalizedStringResource`
/// is localizable all the same, but nothing at the call site would say so.
///
/// No action pins or unpins: a file Shortcuts hands over can be a copy in a temporary folder rather
/// than the file itself, and pinning that would pin a thing that is about to be deleted. The URL
/// scheme takes a path, which is the real thing.

/// Carries out commands for the intents, once the app has finished launching.
@MainActor
enum ScriptRunner {
    static var perform: ((ScriptCommand) -> Void)?

    /// Runs `command`, waiting out the launch if Shortcuts started Eskele to run it: the intent can
    /// arrive before `applicationDidFinishLaunching` has set `perform`.
    static func run(_ command: ScriptCommand) async throws {
        for _ in 0..<50 where perform == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let perform else { throw ScriptRunnerError.notReady }
        perform(command)
    }
}

enum ScriptRunnerError: Error, CustomLocalizedStringResourceConvertible {
    case notReady

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "Eskele did not finish starting. Try again in a moment.",
            comment: "Shortcuts error when the app was not ready to run an action")
    }
}

// MARK: - Choices

enum EdgeChoice: String, AppEnum {
    case left, bottom, right

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Edge", comment: "Shortcuts: the screen edge the bar sits on"))
    static let caseDisplayRepresentations: [EdgeChoice: DisplayRepresentation] = [
        .left: DisplayRepresentation(title: LocalizedStringResource("Left", comment: "Shortcuts: edge choice")),
        .bottom: DisplayRepresentation(title: LocalizedStringResource("Bottom", comment: "Shortcuts: edge choice")),
        .right: DisplayRepresentation(title: LocalizedStringResource("Right", comment: "Shortcuts: edge choice")),
    ]

    var edge: BarEdge {
        switch self {
        case .left: .left
        case .bottom: .bottom
        case .right: .right
        }
    }
}

enum SwitchChoice: String, AppEnum {
    case on, off, toggle

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Setting", comment: "Shortcuts: turn something on, off or toggle it"))
    static let caseDisplayRepresentations: [SwitchChoice: DisplayRepresentation] = [
        .on: DisplayRepresentation(title: LocalizedStringResource("On", comment: "Shortcuts: switch choice")),
        .off: DisplayRepresentation(title: LocalizedStringResource("Off", comment: "Shortcuts: switch choice")),
        .toggle: DisplayRepresentation(title: LocalizedStringResource("Toggle", comment: "Shortcuts: switch choice")),
    ]

    var value: ScriptCommand.Switch {
        switch self {
        case .on: .on
        case .off: .off
        case .toggle: .toggle
        }
    }
}

enum DesignChoice: String, AppEnum {
    case dock, classic, unity, custom

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Design", comment: "Shortcuts: one of the bar's designs"))
    static let caseDisplayRepresentations: [DesignChoice: DisplayRepresentation] = [
        .dock: DisplayRepresentation(title: LocalizedStringResource("Dock", comment: "Shortcuts: design choice")),
        .classic: DisplayRepresentation(title: LocalizedStringResource("Classic", comment: "Shortcuts: design choice")),
        .unity: DisplayRepresentation(title: LocalizedStringResource("Unity", comment: "Shortcuts: design choice")),
        .custom: DisplayRepresentation(title: LocalizedStringResource("Custom", comment: "Shortcuts: design choice")),
    ]

    var preset: DesignPreset {
        switch self {
        case .dock: .dock
        case .classic: .classic
        case .unity: .unity
        case .custom: .custom
        }
    }
}

// MARK: - Actions

struct MoveBarIntent: AppIntent {
    static let title = LocalizedStringResource("Move the Bar", comment: "Shortcuts action")
    static let description = IntentDescription(LocalizedStringResource(
        "Moves Eskele's bar to the left, bottom or right edge of the screen.",
        comment: "Shortcuts action description"))

    @Parameter(title: LocalizedStringResource("Edge", comment: "Shortcuts: the screen edge the bar sits on"))
    var edge: EdgeChoice

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ScriptRunner.run(.edge(edge.edge))
        return .result()
    }
}

struct SetAutoHideIntent: AppIntent {
    static let title = LocalizedStringResource("Set Auto-Hide", comment: "Shortcuts action")
    static let description = IntentDescription(LocalizedStringResource(
        "Turns hiding the bar until the pointer reaches the edge on or off.",
        comment: "Shortcuts action description"))

    @Parameter(
        title: LocalizedStringResource("Auto-Hide", comment: "Shortcuts: the auto-hide setting"),
        default: .toggle)
    var value: SwitchChoice

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ScriptRunner.run(.autohide(value.value))
        return .result()
    }
}

struct ApplyDesignIntent: AppIntent {
    static let title = LocalizedStringResource("Apply Design", comment: "Shortcuts action")
    static let description = IntentDescription(LocalizedStringResource(
        "Gives the bar the shape of one of its designs, as the tiles in Settings do.",
        comment: "Shortcuts action description"))

    @Parameter(title: LocalizedStringResource("Design", comment: "Shortcuts: one of the bar's designs"))
    var design: DesignChoice

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ScriptRunner.run(.design(design.preset))
        return .result()
    }
}

struct RevealBarIntent: AppIntent {
    static let title = LocalizedStringResource("Show or Hide the Bar", comment: "Shortcuts action")
    static let description = IntentDescription(LocalizedStringResource(
        "Slides an auto-hiding bar out, or away again — what the reveal shortcut does.",
        comment: "Shortcuts action description"))

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ScriptRunner.run(.reveal)
        return .result()
    }
}

struct OpenAppsMenuIntent: AppIntent {
    static let title = LocalizedStringResource("Open the Apps Menu", comment: "Shortcuts action")
    static let description = IntentDescription(LocalizedStringResource(
        "Opens Eskele's Apps Menu, or closes it if it is open.",
        comment: "Shortcuts action description"))

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ScriptRunner.run(.appsMenu)
        return .result()
    }
}

struct FocusBarIntent: AppIntent {
    static let title = LocalizedStringResource("Move Focus to the Bar", comment: "Shortcuts action")
    static let description = IntentDescription(LocalizedStringResource(
        "Puts the keyboard on the bar, for the arrow keys and VoiceOver.",
        comment: "Shortcuts action description"))

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ScriptRunner.run(.focus)
        return .result()
    }
}
