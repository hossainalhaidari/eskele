import Foundation

/// What an `eskele://` URL asks for — the way Shortcuts, Raycast, Alfred, a shell script or anything
/// else that can open a URL drives the bar.
///
///     eskele://edge/left              left, bottom or right
///     eskele://autohide/on            on, off or toggle (the default)
///     eskele://design/classic         dock, classic, unity or custom
///     eskele://reveal                 show or hide an auto-hiding bar, as the reveal key does
///     eskele://apps-menu              open or close the Apps Menu
///     eskele://focus                  move the keyboard to the bar
///     eskele://settings               open Settings
///     eskele://pin?path=~/Downloads   pin a file, folder or app — or ?app=com.apple.Safari
///     eskele://unpin?app=com.apple.Safari
///
/// **What is left out, on purpose.** Any web page can open one of these — the browser asks first,
/// but the person clicking "Allow" may not read the link. So nothing here quits an app, empties the
/// Trash, sleeps the Mac or touches the system Dock: the worst a hostile link can do is move the bar
/// or pin something, and both are one click from undone.
///
/// Pure: parsing is tested here, and `applied(to:)` is the part that changes settings. Finding an
/// app by its bundle identifier, and everything else that needs the running app, is
/// `AppDelegate.perform`.
enum ScriptCommand: Equatable {
    case edge(BarEdge)
    case autohide(Switch)
    case design(DesignPreset)
    case reveal
    case appsMenu
    case focus
    case settings
    case pin([Target])
    case unpin([Target])

    enum Switch: String, Equatable { case on, off, toggle }

    enum Target: Equatable {
        case path(URL)
        case app(bundleID: String)
    }

    enum ParseError: Error, Equatable {
        case notEskele
        case unknownCommand(String)
        /// The command is known, but what follows it is not one of its choices.
        case badArgument(command: String, argument: String)
        /// `pin` or `unpin` with nothing to pin, or a path that is not absolute.
        case noTarget(String)
    }

    static let scheme = "eskele"

    static func parse(_ url: URL, home: URL) -> Result<ScriptCommand, ParseError> {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return .failure(.notEskele) }

        // `eskele://edge/left` puts the command in the host; `eskele:edge/left`, which some
        // launchers produce from a typed string, puts it in the path. Either reads the same.
        var parts = components.path.split(separator: "/").map(String.init)
        if let host = components.host, !host.isEmpty { parts.insert(host, at: 0) }
        guard let command = parts.first?.lowercased() else { return .failure(.unknownCommand("")) }
        let argument = parts.dropFirst().first?.lowercased()
        let query = components.queryItems ?? []

        func bad(_ value: String?) -> ParseError {
            .badArgument(command: command, argument: value ?? "")
        }

        switch command {
        case "edge":
            guard let edge = argument.flatMap(BarEdge.init(rawValue:)) else { return .failure(bad(argument)) }
            return .success(.edge(edge))
        case "autohide":
            guard let value = Switch(rawValue: argument ?? "toggle") else { return .failure(bad(argument)) }
            return .success(.autohide(value))
        case "design":
            guard let preset = argument.flatMap(DesignPreset.init(rawValue:)) else {
                return .failure(bad(argument))
            }
            return .success(.design(preset))
        case "reveal": return .success(.reveal)
        case "apps-menu": return .success(.appsMenu)
        case "focus": return .success(.focus)
        case "settings": return .success(.settings)
        case "pin", "unpin":
            let targets = query.compactMap { item -> Target? in
                guard let value = item.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty
                else { return nil }
                switch item.name {
                case "app": return .app(bundleID: value)
                case "path": return path(value, home: home).map(Target.path)
                default: return nil
                }
            }
            guard !targets.isEmpty else { return .failure(.noTarget(command)) }
            return .success(command == "pin" ? .pin(targets) : .unpin(targets))
        default:
            return .failure(.unknownCommand(command))
        }
    }

    /// Whether the command is for the keyboard — so Eskele stays in front after it rather than
    /// handing the front back to the app the user was in.
    var takesKeyboard: Bool {
        switch self {
        case .appsMenu, .focus, .settings: true
        case .edge, .autohide, .design, .reveal, .pin, .unpin: false
        }
    }

    /// The settings after this command, or nil for a command that changes none.
    func applied(to settings: Settings) -> Settings? {
        var result = settings
        switch self {
        case .edge(let edge):
            result.edge = edge
        case .autohide(let value):
            switch value {
            case .on: result.autohide = true
            case .off: result.autohide = false
            case .toggle: result.autohide.toggle()
            }
            // As the menu does: the reveal key exists for an auto-hiding bar, and left on for a bar
            // that no longer hides it would be a global shortcut that does nothing.
            if !result.autohide { result.revealHotKeyEnabled = false }
        case .design(let preset):
            result = preset.applied(to: result)
        case .reveal, .appsMenu, .focus, .settings, .pin, .unpin:
            return nil
        }
        return result
    }

    /// An absolute path, or one starting with `~`. A relative path means relative to whatever
    /// directory the sender happened to be in, which a URL does not carry, so it is refused.
    private static func path(_ value: String, home: URL) -> URL? {
        if value == "~" { return home }
        if value.hasPrefix("~/") { return home.appendingPathComponent(String(value.dropFirst(2))) }
        guard value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value)
    }
}
