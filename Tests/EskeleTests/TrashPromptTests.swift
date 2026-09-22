import Testing
import TrashKit
@testable import Eskele

/// The count may only be stated when it is a count rather than an inference. Without Full Disk
/// Access it comes from directory metadata, and a dialog about permanent deletion is the last place
/// to present a guess as a fact.
@Test func anInexactCountIsNotQuoted() {
    let message = TrashPrompt.message(for: TrashSnapshot(count: 12, isExact: false))
    #expect(!message.contains("12"))
    #expect(message.contains("the items in the Trash"))
}

@Test func anExactCountIsQuoted() {
    #expect(TrashPrompt.message(for: TrashSnapshot(count: 12, isExact: true)).contains("12 items"))
}

/// The singular reading — "1 item", not "1 items" — is no longer decided here. It is a plural rule
/// in `Localizable.stringsdict`, so that a language needing three forms can have three; what this
/// type still owns is whether a count is quoted at all. `LocalizationTests.theEnglishPluralFormsAreApplied`
/// loads the catalogue and checks the forms.
@Test func theCountReachesTheSentence() {
    let message = TrashPrompt.message(for: TrashSnapshot(count: 1, isExact: true))
    #expect(message.contains("1"))
    #expect(message.contains("in the Trash"))
}

@Test func theConfirmationSaysItCannotBeUndone() {
    #expect(TrashPrompt.detail.contains("undo"))
}
