import Carbon.HIToolbox
import Foundation

/// What a key is labelled on the keyboard in use.
///
/// A hot key is a key *position* (`KeyCombination.keyCode`), so the character to show for it depends
/// on the layout: the key a US keyboard calls D is E on Dvorak. The ASCII-capable layout is the one
/// asked, as macOS menus do, so someone typing Russian still sees ⌃⌥D rather than ⌃⌥В.
///
/// Main actor because the Text Input Sources calls are main-thread only.
@MainActor
enum KeyboardLayout {
    static func label(for keyCode: UInt32) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                characters.count, &length, &characters)
            guard status == noErr, length > 0 else { return nil }
            let label = String(utf16CodeUnits: characters, count: length).uppercased()
            // A control character or a blank is no name for a key.
            let printable = label.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value != 0x7F }
            return printable ? label : nil
        }
    }
}
