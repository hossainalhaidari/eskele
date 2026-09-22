import SwiftUI

@MainActor
protocol PreferencesActions: AnyObject {
    func restoreSystemDock()
    func setLaunchAtLogin(_ enabled: Bool)
    func requestAccessibility()
    func revealBadgeConfiguration()
    func revealProgressConfiguration()
    func revealIconOverrides()
    func setHotKeysSuspended(_ suspended: Bool)
    func exportSettings()
    func importSettings()
    func restoreDefaultSettings()
}

/// Copy shared by more than one pane.
private enum PreferencesCopy {
    static let lastRoute = String(
        localized: """
            This is the last way left to reach these settings, so it stays on. Turn the other one back \
            on to free it.
            """,
        comment: "Why a toggle that would remove the last route to Settings is locked on")
}

/// A footer's house style. Grouped forms already draw footers small and secondary; saying so
/// explicitly keeps the conditional multi-paragraph footers below matching the one-liners.
private struct FooterText: View {
    private let lines: [String]

    init(_ lines: String?...) { self.lines = lines.compactMap { $0 } }

    @ViewBuilder
    var body: some View {
        // A section whose note is conditional passes nothing rather than an empty string; an empty
        // VStack still claims the footer's padding and leaves a gap under the group.
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @Bindable var store: SettingsStore

    private var settings: Settings { store.settings }

    var body: some View {
        Form {
            Section {
                DesignPresetPicker(settings: $store.settings)
            } header: {
                Text("Design")
            } footer: {
                FooterText(designNote)
            }

            Section {
                Picker("Position", selection: $store.settings.edge) {
                    ForEach(BarEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Scale", selection: $store.settings.barSize) {
                    ForEach(BarSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Size", selection: $store.settings.spanMode) {
                    ForEach(SpanMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Items", selection: $store.settings.itemStyle) {
                    ForEach(BarItemStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(settings.edge.isVertical)
                .help(settings.edge.isVertical
                    ? "A left or right bar has no room for labels."
                    : "Whether each item is an icon or an icon with its name.")

                if settings.itemStyle == .expanded && !settings.edge.isVertical {
                    Toggle("Give each window its own button", isOn: $store.settings.separateWindows)
                        .disabled(settings.spanMode != .fullSpan)
                        .help(settings.spanMode == .fullSpan
                            ? "One button per window instead of one per app."
                            : "Needs Size set to span the screen edge.")

                    LabeledContent(settings.spanMode == .fullSpan ? "Button width" : "Widest button") {
                        Stepper(value: $store.settings.expandedItemWidth, in: 72...320, step: 4) {
                            Text(verbatim: "\(Int(settings.expandedItemWidth)) pt").monospacedDigit()
                        }
                    }
                }

                LabeledContent(settings.edge.isVertical ? "Columns" : "Rows") {
                    Stepper(value: $store.settings.barRows, in: 1...BarLayout.maximumRows) {
                        Text(rowsLabel).monospacedDigit()
                    }
                }

                Picker("Align icons", selection: $store.settings.itemAlignment) {
                    ForEach(ItemAlignment.allCases, id: \.self) {
                        Text($0.title(for: settings.edge)).tag($0)
                    }
                }
                .disabled(settings.spanMode != .fullSpan)
                .help(settings.spanMode == .fullSpan
                    ? "Where the items sit along the bar."
                    : "A bar that hugs its icons has no spare room to align them in.")
            } header: {
                Text("Layout")
            } footer: {
                FooterText(settings.itemStyle == .expanded && settings.edge.isVertical
                    ? verticalLabelNote : nil)
            }

            Section {
                Picker("Material", selection: $store.settings.material) {
                    ForEach(BarMaterial.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Appearance", selection: $store.settings.appearance) {
                    ForEach(BarAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.material == .custom {
                    ColorPicker("Colour", selection: Binding(
                        get: { Color(nsColor: settings.tint.color).opacity(1) },
                        set: { colour in
                            store.settings.tint = BarTint(
                                color: NSColor(colour), opacity: store.settings.tint.opacity)
                        }
                    ), supportsOpacity: false)
                    LabeledContent("Opacity") {
                        HStack {
                            Slider(value: $store.settings.tint.opacity, in: 0.15...1, step: 0.05)
                            Text(verbatim: "\(Int((settings.tint.opacity * 100).rounded()))%")
                                .monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Material")
            } footer: {
                FooterText(settings.material == .custom ? customMaterialNote : nil)
            }

            Section {
                LabeledContent("Thickness") {
                    HStack {
                        Slider(value: $store.settings.thicknessNudge, in: -6...12, step: 1)
                        Text(nudgeLabel).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .trailing)
                    }
                }
                LabeledContent("Icon padding") {
                    Stepper(value: $store.settings.iconPadding, in: 0...8, step: 1) {
                        Text(verbatim: "\(Int(settings.iconPadding)) pt").monospacedDigit()
                    }
                }
                LabeledContent("Icon spacing") {
                    Stepper(value: $store.settings.itemSpacing, in: 0...16, step: 1) {
                        Text(verbatim: "\(Int(settings.itemSpacing)) pt").monospacedDigit()
                    }
                }
                LabeledContent("Corner radius") {
                    Stepper(value: $store.settings.cornerRadius, in: 0...16, step: 1) {
                        Text(verbatim: "\(Int(settings.cornerRadius)) pt").monospacedDigit()
                    }
                }
                .disabled(settings.spanMode == .fullSpan)
                .help(settings.spanMode == .fullSpan
                    ? "A bar that spans the screen edge squares off its corners."
                    : "How rounded the bar's corners are.")
            } header: {
                Text("Metrics")
            } footer: {
                FooterText(appearanceNote)
            }
        }
        .formStyle(.grouped)
    }

    private let designNote = String(
        localized: """
            One click sets the position, size, span, item style and alignment below, and turns the Trash \
            and the Apps Menu on. Everything else is left as you had it. Change any of those settings \
            afterwards and the bar becomes your Custom design, kept under the last tile — so you can \
            try one of the other three and click Custom to come straight back to it.
            """,
        comment: "Footer under the design tiles")

    private let verticalLabelNote = String(
        localized: """
            A left or right bar is only one icon wide, so there is no room for labels. Items stay \
            icons until you move the bar to the bottom.
            """,
        comment: "Footer: why labels are refused on a left or right bar")

    private let customMaterialNote = String(
        localized: """
            A flat colour instead of a blur. Appearance still decides whether the labels and icons are \
            drawn light or dark, so set it to match what you picked.
            """,
        comment: "Footer under the custom colour controls")

    private let appearanceNote = String(
        localized: """
            Small is 32 points thick; Big is half again as thick, for larger targets. Extra rows \
            stack that thickness again for each one, and the items spread across them — on a \
            left or right bar they are columns instead. A full-width bar squares off its \
            corners. With labels on, every running app becomes a button of the width above — exactly \
            that width when the bar spans the edge, at most that width when it hugs its icons. They \
            shrink together when the bar fills up, and fall back to plain icons when there is no room \
            left for text.
            """,
        comment: "Footer under the layout controls")

    private var rowsLabel: String {
        let rows = settings.rowCount
        // Two plurals rather than a count in front of a noun: a language that inflects the noun
        // with the number cannot be served by pasting an "s" on the end of either word.
        // Pluralised in Localizable.stringsdict.
        return settings.edge.isVertical
            ? String(localized: "\(rows) columns", comment: "How many columns a vertical bar has")
            : String(localized: "\(rows) rows", comment: "How many rows a horizontal bar has")
    }

    private var nudgeLabel: String {
        let nudge = Int(settings.thicknessNudge)
        guard nudge != 0 else {
            return String(
                localized: "default",
                comment: "Thickness slider at zero: the bar is its size's own thickness, Small or Big")
        }
        // "pt" is the typographic point, which is the abbreviation in every locale macOS ships.
        return nudge > 0 ? "+\(nudge) pt" : "\(nudge) pt"
    }
}

// MARK: - Contents

/// What goes on the bar: which cells appear, and what each one is allowed to draw on itself.
struct ContentsPane: View {
    @Bindable var store: SettingsStore
    weak var actions: (any PreferencesActions)?

    @State private var accessibility = PermissionsService.accessibilityStatus

    private var settings: Settings { store.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Show running apps that aren't pinned", isOn: $store.settings.showRunningUnpinned)
                Toggle("Show menu-bar apps while they have a window",
                       isOn: $store.settings.showAccessoryApps)
                    .disabled(!settings.showRunningUnpinned)
                    .help(settings.showRunningUnpinned
                        ? "A menu-bar app gets a cell only while a window of its own is open."
                        : "Only applies when running apps that aren't pinned are shown.")
                if settings.tracksAccessoryApps, accessibility != .granted {
                    PermissionPrompt(message: "Listing their windows needs Accessibility.") {
                        actions?.requestAccessibility()
                        accessibility = PermissionsService.accessibilityStatus
                    }
                }
                Toggle("Show the Trash", isOn: $store.settings.showTrash)
                Toggle("Keep pinned apps in their own group", isOn: $store.settings.separatePinGroup)
                    .disabled(!settings.drawsLabels)
                    .help(settings.drawsLabels
                        ? "Pinned apps that are not running sit together as compact icons."
                        : "Only applies when items show labels.")
            } header: {
                Text("Items")
            } footer: {
                FooterText(settings.showAccessoryApps ? accessoryNote : nil, pinGroupNote)
            }

            Section {
                Toggle("Show a clock at the end of the bar", isOn: $store.settings.showClock)
                if settings.showClock {
                    Picker("Style", selection: $store.settings.clockStyle) {
                        ForEach(ClockStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Shows", selection: $store.settings.clockFormat) {
                        ForEach(ClockFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .disabled(settings.clockStyle != .digital || settings.edge.isVertical)
                    .help(settings.clockStyle != .digital
                        ? "Only a digital clock has a date to show."
                        : "What the clock puts beside the time.")
                }
            } header: {
                Text("Clock")
            } footer: {
                FooterText(settings.showClock ? clockNote : nil)
            }

            Section {
                Toggle("Show number badges", isOn: $store.settings.showBadges)
                Button("Edit Badge Sources…") { actions?.revealBadgeConfiguration() }
                    .disabled(!settings.showBadges)
            } header: {
                Text("Badges")
            } footer: {
                FooterText(badgeNote)
            }

            Section {
                Toggle("Show progress bars", isOn: $store.settings.showProgress)
                Toggle("Ask media players where they are", isOn: $store.settings.mediaProgress)
                    .disabled(!settings.showProgress)
                Button("Edit Progress Sources…") { actions?.revealProgressConfiguration() }
                    .disabled(!settings.showProgress)
            } header: {
                Text("Progress")
            } footer: {
                FooterText(
                    progressNote,
                    settings.showProgress && settings.mediaProgress ? mediaProgressNote : nil)
            }

            Section {
                Button("Custom Icons Folder…") { actions?.revealIconOverrides() }
            } header: {
                Text("Icons")
            } footer: {
                FooterText(iconNote)
            }

            Section {
                Toggle("Highlight apps that need attention", isOn: $store.settings.highlightAttention)
                if accessibility != .granted {
                    PermissionPrompt(message: "Needs Accessibility.") {
                        actions?.requestAccessibility()
                        accessibility = PermissionsService.accessibilityStatus
                    }
                }
            } header: {
                Text("Attention")
            } footer: {
                FooterText(attentionNote)
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibility = PermissionsService.accessibilityStatus }
    }

    private var clockNote: String {
        if settings.clockStyle == .analog {
            return String(
                localized: """
                    A dial drawn from the current appearance. Hover it for the month; click it to \
                    open your calendar.
                    """,
                comment: "Footer under the clock controls, analogue style")
        }
        if settings.edge.isVertical {
            return String(
                localized: """
                    A side bar is only one icon wide, so the clock shows the time on two lines and \
                    no date. Hover it for the month; click it to open your calendar.
                    """,
                comment: "Footer under the clock controls, on a left or right bar")
        }
        return String(
            localized: """
                The 12- or 24-hour choice and the order of day and month come from System Settings \
                ▸ Language & Region, so it agrees with the menu bar's clock. Hover it for the month.
                """,
            comment: "Footer under the clock controls, digital style")
    }

    private let accessoryNote = String(
        localized: """
            Menu-bar apps have no Dock cell of their own, so a window one of them opens \
            — its settings, usually — can only be got back to by finding it on screen. This gives \
            such an app a cell for as long as the window is open, and takes it away again when the \
            window closes. Eskele's own settings window is included. Only ordinary windows count: \
            menu-bar icons, popovers and panels that float above your work do not, so an app that is \
            merely running stays hidden.
            """,
        comment: "Footer under the menu-bar apps toggle")

    private let pinGroupNote = String(
        localized: """
            With labels on, a pinned app that is not running is a shortcut rather than a task. Grouped, \
            those shortcuts sit together at the leading end of the bar as compact icons instead of \
            breaking up the run of buttons.
            """,
        comment: "Footer under the pin group toggle")

    private let badgeNote = String(
        localized: """
            The Trash badges itself with the number of items it holds. macOS gives no app a way to read \
            another app's Dock badge, so anything else comes from a command you supply in badges.json — \
            the file opens with worked examples for Mail and Reminders.
            """,
        comment: "Footer under the badges toggle")

    private let iconNote = String(
        localized: """
            Drop an image named after an app's bundle identifier — com.apple.Safari.png — to replace \
            its icon on the bar; “trash” and “apps-menu” name the other two. The folder opens with a \
            note explaining it, and changes show up straight away. Pinned folders and files are not \
            listed there because a path is not a filename: set those in Finder with Get Info, and the \
            bar draws whatever Finder reports.

            To rename a cell, right-click it and choose Rename.
            """,
        comment: "Footer under the custom icons button")

    private let progressNote = String(
        localized: """
            A cell that has something under way fills up: icons-only bars draw a bar where the running \
            dots go, labelled buttons fill from the left. Files landing in a folder that is on the bar \
            are found on their own and need no permission — they go on the folder's cell, because macOS \
            tells an observer which file is being written but never which app is writing it. Anything \
            else comes from a command you supply in progress.json.
            """,
        comment: "Footer under the progress toggle")

    private let mediaProgressNote = String(
        localized: """
            Music, Spotify and VLC are asked directly, which raises each one's Automation prompt the \
            first time. There is no longer any other way: the private interface the system uses has \
            needed an entitlement since macOS 15.4 and tells an ordinary app nothing. Refuse a prompt \
            and that player simply shows no bar.
            """,
        comment: "Footer under the media progress toggle")

    private let attentionNote = String(
        localized: """
            A bouncing Dock icon is private to the Dock and cannot be observed. What can: an app putting \
            a dialog or a sheet in front of you while you were working elsewhere. Those cells glow until \
            you visit the app.
            """,
        comment: "Footer under the attention toggle")
}

// MARK: - Behaviour

/// How the bar acts: the Apps Menu, hiding, shortcuts, displays and full screen.
struct BehaviourPane: View {
    @Bindable var store: SettingsStore
    weak var actions: (any PreferencesActions)?

    @State private var accessibility = PermissionsService.accessibilityStatus
    @State private var screenRecording = PermissionsService.screenRecordingStatus
    /// Read on appear and after each recording, since they can change in System Settings while this
    /// window is open.
    @State private var systemShortcuts: Set<KeyCombination> = []
    /// Why the key just pressed at a recorder was refused. Only while that recorder is listening.
    @State private var refusals: [HotKeyRole: HotKeyProblem] = [:]

    private var settings: Settings { store.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Show the Apps Menu", isOn: $store.settings.showAppsMenu)
                    .disabled(!settings.showStatusItem)
                Picker("List", selection: $store.settings.appsMenuSource) {
                    ForEach(AppsMenuSource.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!settings.showAppsMenu)
                Toggle("Also list System Settings, folders and power actions",
                       isOn: $store.settings.showSystemItems)
                    .disabled(settings.appsMenuSource != .allApps)
                    .help(settings.appsMenuSource == .allApps
                        ? "They sit after the applications and answer the same search."
                        : "Only the All Applications list has room for them.")
                Picker("Shortcut", selection: $store.settings.appsMenuHotKey) {
                    ForEach(AppsMenuHotKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.appsMenuHotKey == .custom {
                    LabeledContent("Custom shortcut") {
                        recorder(for: .appsMenu, settings.appsMenuCustomHotKey) {
                            store.settings.appsMenuCustomHotKey = $0
                        }
                    }
                }
                hotKeyWarning(for: .appsMenu)
            } header: {
                Text("Apps Menu")
            } footer: {
                FooterText(
                    settings.showStatusItem
                        ? settings.appsMenuSource.detail : PreferencesCopy.lastRoute,
                    settings.showSystemItems && settings.appsMenuSource == .allApps
                        ? systemItemsNote : nil,
                    appsMenuHotKeyNote)
            }

            Section {
                Toggle("Hide the bar until the pointer reaches the edge", isOn: $store.settings.autohide)
                Group {
                    LabeledContent("Reveal after") {
                        Slider(value: $store.settings.revealDelay, in: 0...1, step: 0.05) {
                            Text(String(format: "%.2fs", settings.revealDelay)).monospacedDigit()
                        }
                    }
                    LabeledContent("Hide after") {
                        Slider(value: $store.settings.hideDelay, in: 0.1...2, step: 0.05) {
                            Text(String(format: "%.2fs", settings.hideDelay)).monospacedDigit()
                        }
                    }
                    Toggle("Reveal with a shortcut", isOn: $store.settings.revealHotKeyEnabled)
                    if settings.revealHotKeyEnabled {
                        LabeledContent("Shortcut") {
                            recorder(for: .reveal, settings.revealHotKey) {
                                store.settings.revealHotKey = $0
                            }
                        }
                        hotKeyWarning(for: .reveal)
                    }
                }
                .disabled(!settings.autohide)
            } header: {
                Text("Auto-hide")
            }

            Section {
                Toggle("Move focus to the bar with a shortcut", isOn: $store.settings.focusHotKeyEnabled)
                if settings.focusHotKeyEnabled {
                    LabeledContent("Shortcut") {
                        recorder(for: .focus, settings.focusHotKey) {
                            store.settings.focusHotKey = $0
                        }
                    }
                    hotKeyWarning(for: .focus)
                }
                Toggle(
                    "Activate the first ten cells with \(settings.slotChord.title)",
                    isOn: $store.settings.slotHotKeysEnabled)
                if settings.slotHotKeysEnabled {
                    Picker("Keys", selection: $store.settings.slotChord) {
                        ForEach(SlotChord.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    }
                    hotKeyWarning(for: .slots)
                }
                Toggle(
                    "Show processor and memory use while \(BarOverlay.activityChordName) is held",
                    isOn: $store.settings.activityOverlayEnabled)
            } header: {
                Text("Keyboard")
            } footer: {
                FooterText(
                    settings.focusHotKeyEnabled ? focusNote : nil,
                    settings.slotHotKeysEnabled ? slotKeyNote : nil,
                    settings.activityOverlayEnabled ? activityNote : nil,
                    choosesHotKeys ? otherAppsNote : nil)
            }

            Section {
                Picker("Show the bar on", selection: $store.settings.screenMode) {
                    ForEach(ScreenMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Show a preview of the window when hovering", isOn: $store.settings.windowPreviews)
                Picker("Order apps", selection: $store.settings.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Displays")
            } footer: {
                FooterText(
                    settings.screenMode == .perDisplay ? perDisplayNote : nil,
                    settings.windowPreviews && screenRecording != .granted ? previewNote : nil,
                    settings.sortOrder != .manual ? sortOrderNote : nil)
            }

            Section {
                Picker("In full screen", selection: $store.settings.fullScreenBehavior) {
                    ForEach(FullScreenBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(accessibility != .granted)

                if accessibility != .granted {
                    PermissionPrompt(message: "Detecting full screen needs Accessibility.") {
                        actions?.requestAccessibility()
                        accessibility = PermissionsService.accessibilityStatus
                    }
                }
            } header: {
                Text("Full Screen")
            } footer: {
                FooterText(fullScreenNote)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibility = PermissionsService.accessibilityStatus
            screenRecording = PermissionsService.screenRecordingStatus
            systemShortcuts = SystemShortcuts.enabled()
        }
    }

    private var hotKeyReview: HotKeyReview {
        HotKeyReview(
            settings: settings, system: systemShortcuts, unavailable: store.unavailableHotKeys)
    }

    private func recorder(
        for role: HotKeyRole,
        _ combination: KeyCombination?,
        record: @escaping (KeyCombination) -> Void
    ) -> some View {
        ShortcutRecorder(
            combination: combination,
            check: { candidate in
                // Asked afresh for each key, against the settings and the system as they are now.
                HotKeyReview(settings: store.settings, system: SystemShortcuts.enabled())
                    .refusal(of: candidate, for: role)
            },
            onRecord: record,
            onRefuse: { refusals[role] = $0 },
            onRecordingChange: { recording in
                actions?.setHotKeysSuspended(recording)
                if !recording { systemShortcuts = SystemShortcuts.enabled() }
            })
            // Its own width, like every other control here, rather than the whole trailing column.
            .fixedSize()
    }

    /// Whether any shortcut beyond the defaults — ⌃Esc and ⌃⌥⇥ — is in play, which is when it is
    /// worth saying what cannot be checked. Said once, under Keyboard, however many there are.
    private var choosesHotKeys: Bool {
        settings.slotHotKeysEnabled
            || (settings.autohide && settings.revealHotKeyEnabled)
            || settings.appsMenuHotKey == .custom
            || (settings.focusHotKeyEnabled && settings.focusHotKey != .focusDefault)
    }

    private var focusNote: String {
        String(
            localized: """
                \(settings.focusHotKey.displayName) moves focus to the bar. The arrow keys move along \
                it, Return opens the item, ⌃Return shows its menu, and Escape goes back to the app \
                you were in. VoiceOver reads each item as you reach it.
                """,
            comment: "Footer under the move-focus shortcut. The argument is the key, e.g. ⌃⌥⇥.")
    }

    /// What is wrong with a role's key, said under it: the key just refused while recording, or
    /// failing that whatever is wrong with the one in place.
    @ViewBuilder
    private func hotKeyWarning(for role: HotKeyRole) -> some View {
        if let problem = refusals[role] ?? hotKeyReview.problem(for: role) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(problem.message).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private let otherAppsNote = String(
        localized: """
            A shortcut is checked against macOS’s own and Eskele’s others. Other apps’ cannot be \
            checked — macOS accepts a shortcut whether or not another app already uses it — so if \
            one does nothing, another app has it.
            """,
        comment: "Footer under a shortcut recorder: what is and is not checked for clashes")

    /// What the chosen Apps Menu key costs, said at the point of choosing it.
    ///
    /// The right-⌘ tap is the only one that can be picked and then quietly not work, because it is
    /// the only one that needs a permission — so the missing permission is reported here rather
    /// than left to be discovered.
    private var appsMenuHotKeyNote: String {
        let shortcut = settings.appsMenuHotKey
        guard shortcut.needsAccessibility, !AXIsProcessTrusted() else { return shortcut.detail }
        let warning = String(
            localized: """
                Accessibility has not been granted, so it will not fire until it is: \
                System Settings ▸ Privacy & Security ▸ Accessibility.
                """,
            comment: "Appended to the shortcut's note when the permission it needs is missing")
        return "\(shortcut.detail) \(warning)"
    }

    private var perDisplayNote: String {
        accessibility == .granted
            ? String(
                localized: """
                    Each display's bar lists only the apps with a window on it. Pinned shortcuts, the \
                    Apps Menu and the Trash stay on every bar, and so does anything with no window open.
                    """,
                comment: "Footer under the display mode picker, with Accessibility granted")
            : String(
                localized: """
                    Needs Accessibility. Until it is granted every display shows the same bar, which is \
                    what All Displays does.
                    """,
                comment: "Footer under the display mode picker, without Accessibility")
    }

    private let systemItemsNote = String(
        localized: """
            They sit after the applications and are found by the same search — type “displ” for \
            Displays, “downl” for Downloads, “restart” to restart.
            """,
        comment: "Footer under the system items toggle")

    private var slotKeyNote: String {
        let chord = settings.slotChord.modifiers.symbols
        return String(
            localized: """
                \(chord)1 is the first item on the bar and \(chord)0 the tenth, counting past the Apps \
                Menu. Holding \(chord) numbers them. Every choice includes ⌃, so the chord you hold to \
                read the numbers is never also a click gesture.
                """,
            comment: "Footer under the slot hot keys. Each argument is the modifier symbols, e.g. ⌃⌥.")
    }

    private let activityNote = String(
        localized: """
            Sampled only while the keys are down. An app's helper processes count towards it; Safari's \
            tabs cannot, because macOS gives them to launchd rather than to Safari.
            """,
        comment: "Footer under the activity overlay toggle")

    private let previewNote = String(
        localized: """
            Needs Screen Recording. Until it is granted the hover label stays as it is — the window's \
            title, in text.
            """,
        comment: "Footer under the window previews toggle")

    private let sortOrderNote = String(
        localized: """
            Dragging an item on the bar switches back to As Arranged. Separators are hidden while the \
            order is not yours, and come back with it.
            """,
        comment: "Footer under the sort order picker")

    private let fullScreenNote = String(
        localized: """
            macOS reserves no space inside a full-screen space for anything but the menu bar, so the bar \
            can only float over a full-screen window — it cannot push it out of the way. "Reveal on \
            Hover" does there what the menu bar itself does.
            """,
        comment: "Footer under the full-screen behaviour picker")
}

// MARK: - System Dock

struct SystemDockPane: View {
    @Bindable var store: SettingsStore
    weak var actions: (any PreferencesActions)?

    private var settings: Settings { store.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Hide the system Dock while Eskele runs", isOn: $store.settings.suppressSystemDock)
                Toggle("Reserve screen space for the bar", isOn: $store.settings.reserveScreenSpace)
                    .disabled(!settings.suppressSystemDock)
                    .help(settings.suppressSystemDock
                        ? "Maximised windows stop short of the bar."
                        : "Only applies while the system Dock is hidden.")
                Button("Restore the System Dock Now") { actions?.restoreSystemDock() }
            } footer: {
                FooterText("""
                    Your Dock settings are backed up before anything changes and restored when Eskele \
                    quits — including after a crash. Reserving screen space parks the Dock underneath \
                    the bar, sized to match, so maximised windows stop short of it — except while \
                    the bar auto-hides.
                    """)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable var store: SettingsStore
    weak var actions: (any PreferencesActions)?
    let updates: UpdateService

    @State private var launchAtLogin = LoginItemService.isEnabled
    @State private var automation = PermissionsService.automationStatus()
    @State private var accessibility = PermissionsService.accessibilityStatus
    @State private var screenRecording = PermissionsService.screenRecordingStatus

    private var settings: Settings { store.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Show the menu bar icon", isOn: $store.settings.showStatusItem)
                    .disabled(!settings.showAppsMenu)
                Toggle("Launch Eskele at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { launchAtLogin = $0; actions?.setLaunchAtLogin($0) }
                ))
            } footer: {
                FooterText(
                    settings.showAppsMenu ? statusItemNote : PreferencesCopy.lastRoute,
                    LoginItemService.requiresApproval ? loginApprovalNote : nil)
            }

            Section {
                Picker("Updates", selection: Binding(
                    get: { updates.policy },
                    set: { updates.setPolicy($0) }
                )) {
                    ForEach(UpdatePolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!updates.isAvailable)

                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(verbatim: UpdateService.version()).foregroundStyle(.secondary)
                        // An update a scheduled check held back: the same check brings its alert
                        // forward, so only the label changes.
                        if updates.isAvailable, updates.waitingVersion != nil {
                            Button("Show Update…") { updates.checkForUpdates() }
                        } else if updates.isAvailable {
                            Button("Check Now") { updates.checkForUpdates() }
                                .disabled(!updates.canCheck)
                        }
                    }
                }
            } footer: {
                if updates.isAvailable {
                    FooterText(waitingNote, updates.policy.detail, lastCheckNote)
                } else {
                    FooterText(sourceBuildNote)
                }
            }

            Section("Permissions") {
                permissionRow(
                    "Control Finder", "Needed only to empty the Trash.",
                    automation, PermissionsService.openAutomationSettings)
                permissionRow(
                    "Accessibility", "Needed only to list an app's windows.",
                    accessibility, { actions?.requestAccessibility() })
                permissionRow(
                    "Screen Recording", "Needed only to preview a window on hover.",
                    screenRecording, {
                        // The system prompt appears once and never again; after that only the
                        // settings pane can change the answer, so open it either way.
                        PermissionsService.requestScreenRecording()
                        PermissionsService.openScreenRecordingSettings()
                    })
            }

            Section {
                HStack(spacing: 8) {
                    Button("Export Settings…") { actions?.exportSettings() }
                    Button("Import Settings…") { actions?.importSettings() }
                    Spacer()
                    Button("Restore Defaults…") { actions?.restoreDefaultSettings() }
                }
            } header: {
                Text("Transfer and Reset")
            } footer: {
                FooterText(settingsFileNote)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshStatuses)
    }

    private func permissionRow(
        _ title: String,
        _ detail: String,
        _ status: PermissionsService.Status,
        _ open: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(status.summary).foregroundStyle(status == .granted ? .secondary : .primary)
                if status != .granted {
                    Button("Grant…") { open(); refreshStatuses() }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private let statusItemNote = """
        Hide it and the bar's Apps Menu becomes the way in: the gear beside its search field opens \
        this window, so you can bring the icon back.
        """

    private let loginApprovalNote = "Approve Eskele under System Settings ▸ General ▸ Login Items."

    private var waitingNote: String? {
        updates.waitingVersion.map {
            String(
                localized: "Eskele \($0) is available.",
                comment: "Footer under the update settings: a found update is waiting. The argument is its version")
        }
    }

    private var lastCheckNote: String? {
        updates.lastCheck.map {
            let when = $0.formatted(date: .abbreviated, time: .shortened)
            return String(
                localized: "Last checked \(when).",
                comment: "Footer under the update settings. The argument is a date and time")
        }
    }

    private let sourceBuildNote = String(
        localized: """
            This copy was built from source, so it does not update itself. Copies downloaded from the \
            releases page do.
            """,
        comment: "Footer under the update settings in a development build, which has no update feed")

    private let settingsFileNote = String(
        localized: """
            Export saves your settings as one file, to keep or to take to another Mac, and Import reads \
            one back. Neither importing nor restoring defaults changes the System Dock tab, or anything \
            kept in a file of its own: pinned items, names, icons, and badge and progress sources.
            """,
        comment: "Footer under the export, import and restore defaults buttons")

    private func refreshStatuses() {
        launchAtLogin = LoginItemService.isEnabled
        automation = PermissionsService.automationStatus()
        accessibility = PermissionsService.accessibilityStatus
        screenRecording = PermissionsService.screenRecordingStatus
    }
}

// MARK: - Shared rows

/// The inline "this needs a permission" row, wherever a control depends on one.
private struct PermissionPrompt: View {
    let message: String
    let grant: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            Button("Grant…", action: grant)
        }
    }
}
