import AppKit
import CoreServices

/// Sleep, log out, restart and shut down.
///
/// All four are Apple events to `loginwindow`. There is no Cocoa API for any of them and the shell
/// equivalents need root, so this is the route every launcher has used for thirty years — and, like
/// emptying the Trash, it raises the Automation prompt once. Measured: macOS reports
/// `errAEEventWouldRequireUserConsent` for `com.apple.loginwindow` before the first send.
///
/// The asking and the sending are both injectable, because the one thing that must never be got
/// wrong here is the order of them: a refused confirmation has to mean nothing is sent, and the only
/// way to assert that is to be able to refuse without shutting the machine down.
@MainActor
final class PowerService {
    private let ask: @MainActor (PowerAction) -> Bool
    private let dispatch: @MainActor (PowerAction) -> Void

    init(
        ask: @escaping @MainActor (PowerAction) -> Bool = PowerService.confirm,
        dispatch: @escaping @MainActor (PowerAction) -> Void = PowerService.send
    ) {
        self.ask = ask
        self.dispatch = dispatch
    }

    /// Asks first for anything that ends the session, then sends the event.
    ///
    /// Sleep is one keystroke from being undone. Log Out, Restart and Shut Down each close every
    /// running application, and a launcher you drive by typing is exactly where a mistyped Return
    /// lands one row off the one you meant.
    func perform(_ action: PowerAction) {
        guard !action.needsConfirmation || ask(action) else { return }
        dispatch(action)
    }

    /// The real dialog: a warning alert whose default button is the action itself.
    static func confirm(_ action: PowerAction) -> Bool {
        let alert = alert(for: action)
        // An agent owns no windows, so the alert has nothing to attach to and has to be brought
        // forward itself — otherwise it opens behind whatever the user was looking at.
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Built separately from being run, so its wording can be inspected without a modal loop.
    static func alert(for action: PowerAction) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = action.confirmationTitle
        alert.informativeText = action.confirmationDetail
        // Without this the alert shows the application icon, and Eskele has none — which leaves a
        // dialog about shutting the machine down illustrated with a generic blue folder. The
        // action's own symbol is both correct and different for each of the three.
        if let symbol = NSImage(
            systemSymbolName: action.symbolName, accessibilityDescription: action.searchName)?
            .withSymbolConfiguration(.init(pointSize: 44, weight: .light)) {
            alert.icon = symbol
        }
        alert.addButton(withTitle: action.searchName)
        let cancel = alert.addButton(withTitle: "Cancel")
        // Escape cancels, as it does in every other alert on the system. Without this the only way
        // out of a dialog you opened by accident is to click the one button you did not want.
        cancel.keyEquivalent = "\u{1b}"
        return alert
    }

    static func send(_ action: PowerAction) {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: action.eventID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        do {
            // No reply wanted: a machine that is shutting down is not going to send one.
            try event.sendEvent(options: [.noReply], timeout: 10)
        } catch {
            NSLog("Eskele: \(action.searchName) failed — \(error.localizedDescription)")
            NSSound.beep()
        }
    }
}
