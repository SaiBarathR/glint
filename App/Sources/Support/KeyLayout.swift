import AppKit
import Carbon.HIToolbox

/// Maps characters to key codes on the user's current keyboard layout.
///
/// Glint describes shortcuts by character ("⌘C", "command B"), stored as US-ANSI key codes. Posting those
/// codes directly would type a different character on Dvorak, AZERTY, QWERTZ or Colemak (⌘X → ⌘Q on Dvorak),
/// so every synthetic key press is translated to the key that produces the same character on the active
/// layout. Layouts that switch while ⌘ is held ("Dvorak – QWERTY ⌘") are handled by translating with the
/// ⌘ modifier state.
enum KeyLayout {
    /// Built maps for one input source (main thread only, like every KeySender call).
    private static var cache: (sourceID: String, plain: [Character: UInt16], command: [Character: UInt16])?

    /// The key code that types the same character as `usKeyCode` does on a US keyboard.
    static func translate(_ usKeyCode: UInt16, command: Bool) -> UInt16 {
        guard let ch = usCharacter(for: usKeyCode) else { return usKeyCode } // Return, arrows, F-keys: physical
        // Digits stay on the top row: on AZERTY-like layouts they need Shift, and the only other keys typing
        // them are on the numeric keypad, which apps treat as different keys.
        if ch.isNumber { return usKeyCode }
        let maps = current()
        return (command ? maps.command[ch] : maps.plain[ch]) ?? maps.plain[ch] ?? usKeyCode
    }

    private static let usCharacters: [UInt16: Character] = {
        var out: [UInt16: Character] = [:]
        for (ch, code) in [("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8),
                           ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17),
                           ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24), ("9", 25),
                           ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33),
                           ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("'", 39), ("k", 40), (";", 41), ("\\", 42),
                           (",", 43), ("/", 44), ("n", 45), ("m", 46), (".", 47), ("`", 50)] {
            out[UInt16(code)] = Character(ch)
        }
        return out
    }()

    static func usCharacter(for code: UInt16) -> Character? { usCharacters[code] }

    /// Maps for the current layout. Checked against the active input source on every call (cheap), so a
    /// layout switch is never missed, even while notifications to Glint are suspended.
    private static func current() -> (plain: [Character: UInt16], command: [Character: UInt16]) {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return ([:], [:]) }
        let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? ""
        if let cache, cache.sourceID == id { return (cache.plain, cache.command) }
        let built = (sourceID: id, plain: build(source, modifiers: 0), command: build(source, modifiers: UInt32(cmdKey >> 8)))
        cache = built
        return (built.plain, built.command)
    }

    /// Keypad key codes (65–92): never chosen, apps treat them as different keys.
    private static let keypadCodes = UInt16(65)...UInt16(92)

    private static func build(_ source: TISInputSource, modifiers: UInt32) -> [Character: UInt16] {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var map: [Character: UInt16] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<UInt16(128) where !keypadCodes.contains(code) {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
                guard status == noErr, length > 0,
                      let ch = String(utf16CodeUnits: chars, count: length).lowercased().first else { continue }
                if map[ch] == nil { map[ch] = code } // keep the first (main block) key for a character
            }
        }
        return map
    }
}
