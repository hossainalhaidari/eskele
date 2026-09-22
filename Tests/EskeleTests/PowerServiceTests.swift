import AppKit
import Testing
@testable import Eskele

/// Records what was asked and what was sent, so the order of the two can be asserted without
/// shutting the machine down.
@MainActor
private final class Recorder {
    var asked: [PowerAction] = []
    var sent: [PowerAction] = []
    var answer = true

    func service() -> PowerService {
        PowerService(
            ask: { action in
                self.asked.append(action)
                return self.answer
            },
            dispatch: { action in self.sent.append(action) })
    }
}

/// The guarantee the whole thing rests on: saying no sends nothing at all.
@MainActor
@Test func refusingTheConfirmationSendsNothing() {
    for action in [PowerAction.logOut, .restart, .shutDown] {
        let recorder = Recorder()
        recorder.answer = false
        recorder.service().perform(action)

        #expect(recorder.asked == [action], "\(action) did not ask")
        #expect(recorder.sent.isEmpty, "\(action) was sent after being refused")
    }
}

@MainActor
@Test func acceptingTheConfirmationSendsThatSameAction() {
    for action in [PowerAction.logOut, .restart, .shutDown] {
        let recorder = Recorder()
        recorder.service().perform(action)

        #expect(recorder.asked == [action])
        // The action that was confirmed is the action that goes — not the one next to it.
        #expect(recorder.sent == [action])
    }
}

/// Sleep is undone by moving the mouse, so a dialog for it would be nothing but friction.
@MainActor
@Test func sleepGoesStraightThroughWithoutAsking() {
    let recorder = Recorder()
    recorder.answer = false      // would refuse, if it were ever asked
    recorder.service().perform(.sleep)

    #expect(recorder.asked.isEmpty)
    #expect(recorder.sent == [.sleep])
}

/// Every action that ends the session asks; the one that does not, does not.
@MainActor
@Test func exactlyTheSessionEndingActionsAsk() {
    for action in PowerAction.allCases {
        let recorder = Recorder()
        recorder.service().perform(action)
        #expect(recorder.asked.isEmpty != action.needsConfirmation)
    }
}

// MARK: - The dialog itself

@MainActor
@Test func theDialogNamesTheActionAndDefaultsToIt() {
    for action in [PowerAction.logOut, .restart, .shutDown] {
        let alert = PowerService.alert(for: action)

        #expect(alert.alertStyle == .warning)
        // Eskele ships no application icon, so an alert left to its default is illustrated with a
        // generic blue folder — which is what a dialog about shutting the machine down showed
        // until this was set.
        #expect(alert.icon != nil)
        #expect(!alert.messageText.isEmpty)
        #expect(alert.messageText == action.confirmationTitle)
        #expect(alert.informativeText.contains("unsaved"))

        // Two buttons: the action, then Cancel.
        #expect(alert.buttons.count == 2)
        #expect(alert.buttons[0].title == action.searchName)
        #expect(alert.buttons[1].title == "Cancel")
        // Return is the action, Escape is Cancel — the standard bindings. Without the second one
        // the only way out of a dialog opened by accident is the button you did not want.
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
    }
}

/// The title has to name which action is about to happen: three dialogs reading "Are you sure?"
/// would be three ways to shut the machine down by mistake.
@MainActor
@Test func eachDialogTitleIsDistinct() {
    let titles = [PowerAction.logOut, .restart, .shutDown].map(\.confirmationTitle)
    #expect(Set(titles).count == titles.count)
    #expect(PowerAction.restart.confirmationTitle.localizedCaseInsensitiveContains("restart"))
    #expect(PowerAction.shutDown.confirmationTitle.localizedCaseInsensitiveContains("shut down"))
    #expect(PowerAction.logOut.confirmationTitle.localizedCaseInsensitiveContains("log out"))
}
