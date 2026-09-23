import AppKit
import SwiftUI

/// Hosts the preferences window.
///
/// An agent app owns no windows by default, so this has to activate the app explicitly to come to
/// the front — otherwise it opens behind whatever the user was using.
@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?

    func show(store: SettingsStore, actions: any PreferencesActions, updates: UpdateService) {
        if window == nil {
            let tabs = PreferencesTabController(store: store, actions: actions, updates: updates)
            let window = NSWindow(contentViewController: tabs)
            // The tab controller renames the window after the selected pane, the way every
            // first-party settings window does, so no title is set here.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // Turns the tab controller's toolbar into the tall centred icon-over-label strip in the
            // title bar rather than an ordinary toolbar row.
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The standard About panel, the one every Mac app opens from its app menu. Eskele has no app menu,
/// so the bar's menu and the menu-bar icon's open it instead.
///
/// AppKit fills in the icon, the name, the version with its build and the copyright line
/// (`NSHumanReadableCopyright`) from the bundle; only the credits under them are written here.
@MainActor
enum AboutPanel {
    static let developer = "Hossain Alhaidari"
    static let website = URL(string: "https://eskele.app")!
    static let sourceCode = URL(string: "https://github.com/hossainalhaidari/eskele")!

    static func show() {
        // Like the settings window: an agent app is never frontmost on its own, so without this the
        // panel opens behind whatever the user was using.
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    private static func credits() -> NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        centred.paragraphSpacing = 6
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        func text(_ string: String, _ colour: NSColor = .labelColor) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: colour, .paragraphStyle: centred,
            ])
        }
        func link(_ title: String, _ url: URL) -> NSAttributedString {
            NSAttributedString(string: title, attributes: [
                .font: font, .link: url, .paragraphStyle: centred,
            ])
        }

        // The licences are the copies build-app.sh puts inside the bundle, so they open offline and
        // always match the version that is running. A binary run straight from .build has none,
        // and gets the repository's copy of Eskele's instead.
        func bundledLicense(_ name: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses")
        }
        let ownLicense = bundledLicense("Eskele") ?? sourceCode.appendingPathComponent("blob/main/LICENSE")
        let sparkleLicense = bundledLicense("Sparkle")

        var links = [
            link(String(localized: "Website", comment: "About window: link to Eskele's website"), website),
            link(
                String(localized: "Source Code", comment: "About window: link to Eskele's repository"),
                sourceCode),
        ]
        if let sparkleLicense {
            links.append(link(
                String(
                    localized: "Acknowledgements",
                    comment: "About window: link to the licences of the software Eskele includes"),
                sparkleLicense))
        }

        let credits = NSMutableAttributedString()
        credits.append(text(String(
            localized: "Developed by \(developer)",
            comment: "About window. The argument is the developer's name") + "\n"))

        // The licence's name is its title, so it is passed in untranslated and becomes the link.
        let licenseName = "MIT License"
        let licenseLine = NSMutableAttributedString(attributedString: text(
            String(
                localized: "Free and open source under the \(licenseName).",
                comment: "About window. The argument is the licence's name, “MIT License”") + "\n",
            .secondaryLabelColor))
        let nameRange = (licenseLine.string as NSString).range(of: licenseName)
        if nameRange.location != NSNotFound {
            licenseLine.addAttribute(.link, value: ownLicense, range: nameRange)
        }
        credits.append(licenseLine)

        for (index, link) in links.enumerated() {
            if index > 0 { credits.append(text(" · ", .tertiaryLabelColor)) }
            credits.append(link)
        }
        return credits
    }
}

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(onChoose: @escaping (Bool, Bool) -> Void) {
        let hosting = NSHostingController(rootView: OnboardingView { [weak self] hide, reserve in
            onChoose(hide, reserve)
            self?.close()
        })
        let window = NSWindow(contentViewController: hosting)
        window.title = String(
            localized: "Welcome to Eskele", comment: "Title of the first-run window")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}
