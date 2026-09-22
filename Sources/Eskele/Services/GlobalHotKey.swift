import AppKit
import Carbon.HIToolbox

/// System-wide hot keys, via Carbon's `RegisterEventHotKey`.
///
/// Carbon because it is still the only way to get a global hot key without Accessibility: the
/// AppKit equivalent (`NSEvent.addGlobalMonitorForEvents` for key events) is gated behind it.
///
/// Which keys is the settings' business (`Settings.hotKeys(for:)`); this only registers what it is
/// handed and remembers what failed.
///
/// One handler serves every key. The event carries the `EventHotKeyID` that fired, and dispatching
/// on it is what tells the ten slot keys apart from each other and from the reveal key — with a
/// single key registered there was nothing to tell apart, so the handler used to run every action
/// it had.
@MainActor
final class GlobalHotKey {
    /// What to print on the cell a slot answers to: the character on the key you actually press, so
    /// the tenth slot reads "0" rather than "10". `nonisolated` so drawing code and tests can read it
    /// without hopping to the main actor.
    nonisolated static func slotLabel(_ slot: Int) -> String { "\((slot + 1) % 10)" }
    nonisolated static var slotCount: Int { KeyCombination.slotKeyCodes.count }

    /// Arbitrary but stable: an id only has to be distinct within this process.
    private static let revealID: UInt32 = 1
    private static let appsMenuID: UInt32 = 2
    private static let focusID: UInt32 = 3
    private static func slotID(_ index: Int) -> UInt32 { 100 + UInt32(index) }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    /// What each id is registered as, so a changed combination can give up the old one first.
    private var registered: [UInt32: KeyCombination] = [:]
    /// Ids macOS refused.
    private var failed: Set<UInt32> = []
    private var handlerRef: EventHandlerRef?

    /// The roles whose registration failed, for the preferences to report.
    ///
    /// Rarely anything. Measured on macOS 26, registration succeeds for a combination another
    /// process already holds and for the system's own ⌘Space; it fails when this process registers
    /// the same combination twice, which `HotKeyReview` reports by name before it gets here. This is
    /// for whatever is left.
    var unavailable: Set<HotKeyRole> {
        var roles: Set<HotKeyRole> = []
        if failed.contains(GlobalHotKey.revealID) { roles.insert(.reveal) }
        if failed.contains(GlobalHotKey.appsMenuID) { roles.insert(.appsMenu) }
        if failed.contains(GlobalHotKey.focusID) { roles.insert(.focus) }
        if failed.contains(where: { $0 >= GlobalHotKey.slotID(0) }) { roles.insert(.slots) }
        return roles
    }

    /// - Parameters:
    ///   - combination: nil to switch the key off.
    ///   - action: re-supplied on every call, so a caller need not care whether the key was already
    ///     registered; an unchanged combination is a no-op either way.
    func setReveal(_ combination: KeyCombination?, action: @escaping () -> Void) {
        set(id: GlobalHotKey.revealID, to: combination, action: action)
    }

    /// - Parameters:
    ///   - combination: nil for a choice that registers nothing — off, or the right ⌘ tap.
    ///   - action: re-supplied on every call, as for `setReveal`.
    func setAppsMenu(_ combination: KeyCombination?, action: @escaping () -> Void) {
        set(id: GlobalHotKey.appsMenuID, to: combination, action: action)
    }

    /// - Parameters:
    ///   - combination: nil to switch the key off.
    ///   - action: re-supplied on every call, as for `setReveal`.
    func setFocus(_ combination: KeyCombination?, action: @escaping () -> Void) {
        set(id: GlobalHotKey.focusID, to: combination, action: action)
    }

    /// - Parameters:
    ///   - modifiers: what the number row is held with, or nil to switch all ten off.
    ///   - action: given the zero-based slot, so ⌃⌥1 arrives as 0 and ⌃⌥0 as 9.
    func setSlots(_ modifiers: KeyModifiers?, action: @escaping (Int) -> Void) {
        for (index, keyCode) in KeyCombination.slotKeyCodes.enumerated() {
            let combination = modifiers.map { KeyCombination(keyCode: keyCode, modifiers: $0) }
            set(id: GlobalHotKey.slotID(index), to: combination) { action(index) }
        }
    }

    func unregisterAll() {
        for id in Set(refs.keys).union(failed) { unregister(id: id) }
    }

    private func set(id: UInt32, to combination: KeyCombination?, action: @escaping () -> Void) {
        guard let combination else {
            unregister(id: id)
            return
        }
        // A changed combination has to give up the old registration first: `register` keeps an
        // existing ref and only refreshes the action, which would otherwise leave the key the user
        // just moved away from still firing.
        if registered[id] != combination { unregister(id: id) }
        register(id: id, combination, action: action)
    }

    private func register(id: UInt32, _ combination: KeyCombination, action: @escaping () -> Void) {
        // Already held: keep the registration and just refresh what it does, so re-applying the
        // settings does not churn a key the window server has accepted.
        hotKeyActions[id] = action
        guard refs[id] == nil else { return }

        if handlerRef == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &handlerRef)
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4150_4252), id: id)   // 'APBR'
        let status = RegisterEventHotKey(
            combination.keyCode, combination.modifiers.rawValue, hotKeyID,
            GetApplicationEventTarget(), 0, &ref)
        // The action must not be left behind claiming a key that will never fire, and the failure
        // is kept so the preferences can say so beside the key rather than only in the log.
        guard status == noErr, let ref else {
            hotKeyActions[id] = nil
            failed.insert(id)
            NSLog("Eskele: hot key \(id) could not be registered (\(status))")
            return
        }
        refs[id] = ref
        registered[id] = combination
        failed.remove(id)
    }

    private func unregister(id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        registered[id] = nil
        failed.remove(id)
        hotKeyActions[id] = nil
    }
}

// The Carbon handler is a C function pointer and cannot capture, so the actions are reached through
// a file-scope global, keyed by hot key id. Only ever touched from the main thread.
private nonisolated(unsafe) var hotKeyActions: [UInt32: () -> Void] = [:]

private func hotKeyEventHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var fired = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &fired
    )
    guard status == noErr else { return noErr }
    let id = fired.id
    DispatchQueue.main.async { hotKeyActions[id]?() }
    return noErr
}
