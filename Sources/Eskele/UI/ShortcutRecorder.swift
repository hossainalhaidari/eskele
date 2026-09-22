import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that records one key combination: click it, press the keys.
///
/// While it listens, each key pressed is put to `check`. A refusal is reported through `onRefuse`
/// and listening goes on, so the answer to "⌘ shortcuts belong to the app in front" can be the next
/// key rather than another click. Escape, a click anywhere else, or the window losing focus ends it
/// with nothing changed.
///
/// Keys are caught with a local event monitor rather than by being first responder, because a
/// monitor sees a key before anything can claim it as a menu or button shortcut. Eskele's own hot
/// keys are still registered with the window server, which would take them before any monitor, so
/// `onRecordingChange` is where the owner suspends them — otherwise re-recording the key already
/// assigned would fire it instead.
struct ShortcutRecorder: NSViewRepresentable {
    var combination: KeyCombination?
    var check: (KeyCombination) -> HotKeyProblem?
    var onRecord: (KeyCombination) -> Void
    /// The reason the last key was refused, or nil once there is nothing to refuse.
    var onRefuse: (HotKeyProblem?) -> Void
    var onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.check = check
        button.onRecord = onRecord
        button.onRefuse = onRefuse
        button.onRecordingChange = onRecordingChange
        button.combination = combination
    }

    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) {
        button.stopRecording()
    }
}

/// AppKit underneath, because the button has to know its own bounds: a click on it while recording
/// must be left to its action — which ends the recording — rather than ending it in the monitor,
/// after which the action would start it again.
@MainActor
final class RecorderButton: NSButton {
    var combination: KeyCombination? {
        didSet { if combination != oldValue { refreshTitle() } }
    }
    var check: ((KeyCombination) -> HotKeyProblem?)?
    var onRecord: ((KeyCombination) -> Void)?
    var onRefuse: ((HotKeyProblem?) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private(set) var isRecording = false
    /// The modifiers down right now, shown while recording so the user can see the chord build.
    private var held: KeyModifiers = []
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Wide enough for the prompt, so the row does not reflow as the title changes under the pointer.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = max(size.width, 128)
        return size
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        held = []
        refreshTitle()
        onRecordingChange?(true)

        let mask: NSEvent.EventTypeMask = [
            .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let passes = MainActor.assumeIsolated { self?.handle(event) ?? true }
            return passes ? event : nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRecording() }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        held = []
        refreshTitle()
        onRecordingChange?(false)
    }

    /// Whether the event goes on to wherever it was going.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            held = KeyModifiers(event.modifierFlags)
            refreshTitle()
            return true
        case .keyDown:
            // Swallowed either way: a key pressed at a recorder was meant for the recorder.
            guard !event.isARepeat else { return false }
            let candidate = KeyCombination(
                keyCode: UInt32(event.keyCode), modifiers: KeyModifiers(event.modifierFlags))
            if candidate.modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
                onRefuse?(nil)
                stopRecording()
                return false
            }
            if let problem = check?(candidate) {
                onRefuse?(problem)
                return false
            }
            onRefuse?(nil)
            onRecord?(candidate)
            stopRecording()
            return false
        default:
            // A click on this button is its action's to handle; anywhere else ends the recording
            // and still does whatever the click was for.
            if event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)) {
                return true
            }
            onRefuse?(nil)
            stopRecording()
            return true
        }
    }

    private func refreshTitle() {
        let text: String
        if isRecording {
            text = held.isEmpty
                ? String(localized: "Type Shortcut", comment: "Shortcut recorder, waiting for keys")
                : "\(held.symbols)…"
        } else {
            text = combination?.displayName
                ?? String(localized: "Record Shortcut", comment: "Shortcut recorder with nothing recorded")
        }
        title = text
        // Accent-coloured while listening, the way a focused field reads as live.
        if isRecording {
            attributedTitle = NSAttributedString(
                string: text, attributes: [.foregroundColor: NSColor.controlAccentColor])
        }
        setAccessibilityHelp(isRecording
            ? String(
                localized: "Press the keys for the new shortcut, or Escape to cancel.",
                comment: "VoiceOver help for the shortcut recorder while it listens")
            : String(
                localized: "Click to record a new shortcut.",
                comment: "VoiceOver help for the shortcut recorder"))
        invalidateIntrinsicContentSize()
    }
}
