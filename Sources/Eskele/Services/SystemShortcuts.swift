import Carbon.HIToolbox
import Foundation

/// The shortcuts macOS itself answers to — Spotlight, input sources, the screenshot keys — so a hot
/// key can be checked against them before it is registered.
///
/// **Why not `com.apple.symbolichotkeys`.** That preference domain records only the entries a user
/// has changed. Measured on a real Mac: 28 entries, and neither ⌘Space nor any screenshot key among
/// them, because both were still at Apple's defaults. Checking against it would miss exactly the
/// collisions most worth catching.
///
/// **What is used instead.** `CopySymbolicHotKeys`, which returns the table macOS actually applies —
/// defaults and user changes merged, 234 entries on macOS 26, each with a key code, a Carbon modifier
/// mask and whether it is switched on. It was a documented Carbon call and is still exported from
/// HIToolbox, but it is no longer declared in the SDK's headers, so it is looked up by name. If a
/// later macOS removes it, the lookup fails, the set is empty, and hot keys are still recorded and
/// registered — only the warning about the system's shortcuts goes quiet. Reading it needs no
/// permission.
enum SystemShortcuts {
    private typealias Copy = @convention(c) (UnsafeMutablePointer<Unmanaged<CFArray>?>) -> OSStatus

    private static let copy: Copy? = {
        guard
            let carbon = dlopen("/System/Library/Frameworks/Carbon.framework/Carbon", RTLD_LAZY),
            let symbol = dlsym(carbon, "CopySymbolicHotKeys")
        else { return nil }
        return unsafeBitCast(symbol, to: Copy.self)
    }()

    /// The system shortcuts that are switched on right now. Read afresh each time: the user can
    /// change them in System Settings while the preferences window is open.
    static func enabled() -> Set<KeyCombination> {
        guard let copy else { return [] }
        var array: Unmanaged<CFArray>?
        guard copy(&array) == noErr, let entries = array?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return combinations(from: entries)
    }

    /// Split out so the parsing can be tested without the system's table.
    static func combinations(from entries: [[String: Any]]) -> Set<KeyCombination> {
        let four: KeyModifiers = [.control, .option, .shift, .command]
        var result: Set<KeyCombination> = []
        for entry in entries {
            guard
                entry["kHISymbolicHotKeyEnabled"] as? Bool == true,
                let code = entry["kHISymbolicHotKeyCode"] as? Int,
                let mask = entry["kHISymbolicHotKeyModifiers"] as? Int,
                // 0xFFFF marks an entry with no key assigned.
                (0..<0xFFFF).contains(code)
            else { continue }
            // Arrow and function keys carry the function-key bit (1 << 17) in this table; a
            // registered hot key never does, so it would stop them from ever comparing equal.
            let modifiers = KeyModifiers(rawValue: UInt32(truncatingIfNeeded: mask)).intersection(four)
            result.insert(KeyCombination(keyCode: UInt32(code), modifiers: modifiers))
        }
        return result
    }
}
