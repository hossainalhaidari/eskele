import AppKit
import SwiftUI

/// The settings panes, in toolbar order.
///
/// Each pane carries its own size. A settings window that is one height for every pane has to be
/// as tall as its longest one, which leaves the short panes — System Dock is four controls — as a
/// small island of content in a lot of empty window. `NSTabViewController` animates between these
/// as the selection changes, which is what every first-party settings window does.
enum PreferencesPane: CaseIterable {
    case appearance
    case contents
    case behaviour
    case systemDock
    case general

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance", comment: "Settings tab: how the bar looks")
        case .contents: String(localized: "Contents", comment: "Settings tab: what goes on the bar")
        case .behaviour: String(localized: "Behaviour", comment: "Settings tab: how the bar acts")
        case .systemDock: String(localized: "System Dock", comment: "Settings tab: what to do with the macOS Dock")
        case .general: String(localized: "General", comment: "Settings tab: permissions, login item, updates")
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintbrush"
        case .contents: "square.grid.2x2"
        case .behaviour: "cursorarrow.motionlines"
        case .systemDock: "dock.rectangle"
        case .general: "gearshape"
        }
    }

    /// Chosen to fit the pane's content without scrolling at its default state, capped so no pane
    /// outgrows a laptop display. The window is resizable, so a pane that does scroll — Behaviour,
    /// once every conditional row is showing — can still be pulled taller.
    var size: NSSize {
        switch self {
        case .appearance: NSSize(width: 520, height: 640)
        case .contents: NSSize(width: 520, height: 600)
        case .behaviour: NSSize(width: 520, height: 640)
        case .systemDock: NSSize(width: 520, height: 210)
        case .general: NSSize(width: 520, height: 700)
        }
    }
}

/// Puts the panes in the title bar rather than in the content view.
///
/// SwiftUI's `TabView` only draws the toolbar-style tab strip inside a `Settings` scene, which needs
/// the SwiftUI app lifecycle; Eskele is an AppKit agent with its own `main.swift`, so `TabView` fell
/// back to a segmented control wedged under the title bar. `NSTabViewController` in its toolbar
/// style is the same chrome Xcode, Terminal and Mail use, and it brings the window title, the
/// keyboard tab loop and the per-pane resize with it.
@MainActor
final class PreferencesTabController: NSTabViewController {
    init(store: SettingsStore, actions: any PreferencesActions, updates: UpdateService) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []

        for pane in PreferencesPane.allCases {
            let item = NSTabViewItem(
                viewController: hosting(pane, store: store, actions: actions, updates: updates))
            item.label = pane.title
            item.image = NSImage(
                systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func hosting(
        _ pane: PreferencesPane, store: SettingsStore, actions: any PreferencesActions,
        updates: UpdateService
    ) -> NSViewController {
        let controller: NSViewController = switch pane {
        case .appearance: NSHostingController(rootView: AppearancePane(store: store))
        case .contents: NSHostingController(rootView: ContentsPane(store: store, actions: actions))
        case .behaviour: NSHostingController(rootView: BehaviourPane(store: store, actions: actions))
        case .systemDock: NSHostingController(rootView: SystemDockPane(store: store, actions: actions))
        case .general:
            NSHostingController(rootView: GeneralPane(store: store, actions: actions, updates: updates))
        }
        // What NSTabViewController resizes the window to when this pane is selected. Without it
        // every pane inherits the window's current size and the short ones sit in empty space.
        controller.preferredContentSize = pane.size
        return controller
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // The toolbar is installed by the superclass as the view appears, and .preference is what
        // turns it into the tall centred icon-over-label strip rather than an ordinary toolbar.
        view.window?.toolbarStyle = .preference
        retitle()
    }

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        retitle()
    }

    /// The window is named after the pane on show, the way a settings window is: the title bar
    /// already carries the panes, so repeating the app's name there says nothing.
    ///
    /// Set on the controller rather than on the window: `NSWindow(contentViewController:)` binds the
    /// window's title to the controller's, so assigning the window directly is overwritten — and a
    /// controller with no title of its own is where the stock "Untitled" comes from.
    private func retitle() {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return }
        title = tabViewItems[selectedTabViewItemIndex].label
    }
}
