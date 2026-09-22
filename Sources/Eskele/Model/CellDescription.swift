import Foundation

/// What VoiceOver says about one cell: what kind of control it is, what it is called, and what
/// state it is in.
///
/// The bar says all of this in drawing — dashes for windows, a fill for the app in front, stripes
/// for one that has stopped answering, a red capsule, a dimmed icon — and none of it reaches someone
/// who cannot see it. Pure, and kept out of `ItemView`, for the reason `ClickAction` is: written out
/// as a table it can be asserted, rather than discovered by running VoiceOver over every kind of cell.
struct CellDescription: Equatable {
    enum Role: Equatable {
        /// Does something when pressed.
        case button
        /// Opens a list when pressed: a folder's stack, or the Apps Menu.
        case menuButton
    }

    var role: Role
    /// What the cell is called. The tooltip's name, without the tooltip's extra context — for an
    /// app, the app rather than the page it is on, since a sighted user already has the icon to say
    /// which app it is and a VoiceOver user has only this.
    var label: String
    /// Everything the drawing says about the cell, most urgent first.
    var states: [String]

    /// `nil` rather than empty, so VoiceOver moves on instead of pausing over nothing.
    var value: String? { states.isEmpty ? nil : states.joined(separator: ", ") }

    /// - Returns: `nil` for a separator, which is a gap rather than a place.
    init?(item: DockItem, progress: ProgressReport? = nil, now: Date = Date()) {
        switch item.kind {
        case .separator:
            return nil

        case .app:
            role = .button
            label = item.displayName
            states = CellDescription.condition(of: item)
            // Not running says nothing, as in the system Dock: a pinned app that is not open is the
            // ordinary case, and hearing so on every one of them would bury the cells that are.
            if item.isRunning && !item.isLaunching && !item.isUnresponsive {
                states.append(String(localized: "running", comment: "VoiceOver: the app is open"))
            }
            if item.isFrontmost { states.append(CellDescription.active) }
            if item.isHidden {
                states.append(String(localized: "hidden", comment: "VoiceOver: the app is hidden"))
            }
            // Zero is "unknown" as well as "none" — see `DockItem.windowCount` — so it is not said.
            if item.isRunning && item.windowCount > 0 {
                // Pluralised in Localizable.stringsdict.
                states.append(String(
                    localized: "\(item.windowCount) windows",
                    comment: "VoiceOver: how many windows the app has open"))
            }
            if item.isFullScreen { states.append(CellDescription.fullScreen) }

        case .window(let app, let window):
            role = .button
            label = window.title.isEmpty ? app.name : window.title
            // A window button's name is its title, so the app it belongs to is the first thing said
            // after it — a row of them is otherwise a row of document names with no owner.
            states = [app.name] + CellDescription.condition(of: item)
            if item.isFrontmost { states.append(CellDescription.active) }
            if window.isMinimized {
                states.append(String(localized: "minimised", comment: "VoiceOver: the window is minimised"))
            }
            if window.isFullScreen { states.append(CellDescription.fullScreen) }
            if window.isOffSpace {
                states.append(String(
                    localized: "on another Space", comment: "VoiceOver: the window is on another desktop"))
            }

        case .folder:
            role = .menuButton
            label = item.displayName
            states = []

        case .file:
            role = .button
            label = item.displayName
            states = []

        case .trash(let isEmpty):
            role = .button
            label = String(localized: "Trash", comment: "VoiceOver: the Trash cell's name")
            if isEmpty {
                states = [String(localized: "empty", comment: "VoiceOver: there is nothing in the Trash")]
            } else if let count = item.badge, count > 0 {
                // The Trash's badge is a count of what is in it, so it is said as one. Pluralised in
                // Localizable.stringsdict, shared with the Trash's menu.
                states = [String(
                    localized: "\(count) items",
                    comment: "How many things are in the Trash, shown greyed out under its menu")]
            } else {
                states = [String(localized: "not empty", comment: "VoiceOver: the Trash has something in it")]
            }

        case .appsMenu:
            role = .menuButton
            label = String(localized: "Apps", comment: "VoiceOver: the Apps Menu cell's name")
            states = []

        case .clock:
            role = .button
            label = String(localized: "Clock", comment: "VoiceOver: the clock cell's name")
            // The reading in full, date included: a face or a time drawn to fit the bar is what the
            // cell shows, but what someone asking a clock wants is what it says.
            states = [ClockContent.description(at: now)]
        }

        // The Trash has said its count already; everything else's badge is only a number, and what
        // it counts is the app's business, so it is read as exactly that.
        if !item.isTrash, let badge = item.badge, badge > 0 {
            states.append(String(
                localized: "badge \(badge)", comment: "VoiceOver: the number on the cell's badge, e.g. 'badge 3'"))
        }
        if let progress {
            if let detail = progress.detail { states.append(detail) }
            states.append(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
        }
        // Last, because it can be long: a page title is context, and the state words are what a
        // listener stopping part-way through should already have heard.
        if case .app = item.kind, let title = item.windowTitle, !title.isEmpty, title != label {
            states.append(title)
        }
    }

    /// Starting or stalled, and asking for attention: the states that are news, said first.
    private static func condition(of item: DockItem) -> [String] {
        var states: [String] = []
        if item.isUnresponsive {
            states.append(String(localized: "not responding", comment: "VoiceOver: the app has stopped answering"))
        } else if item.isLaunching {
            states.append(String(localized: "opening", comment: "VoiceOver: the app is still starting"))
        }
        if item.needsAttention {
            states.append(String(
                localized: "needs attention", comment: "VoiceOver: the app has put a dialog up behind other windows"))
        }
        return states
    }

    private static var active: String {
        String(localized: "active", comment: "VoiceOver: the app, or window, in front")
    }

    private static var fullScreen: String {
        String(localized: "full screen", comment: "VoiceOver: in a full-screen space of its own")
    }
}
