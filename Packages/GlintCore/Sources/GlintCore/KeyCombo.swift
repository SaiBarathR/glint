import Foundation

/// A key press: a virtual key code plus modifiers. Parsed from strings like "command shift B",
/// "cmd+opt+return", "⌘⇧K", a raw key code number, or a dictionary {key code / key char, modifiers}.
public struct KeyCombo: Equatable, Hashable, Codable, CustomStringConvertible {
    public var keyCode: UInt16
    public var modifiers: ModifierFlags

    public struct ModifierFlags: OptionSet, Hashable, Codable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = ModifierFlags(rawValue: 1 << 17)
        public static let control = ModifierFlags(rawValue: 1 << 18)
        public static let option = ModifierFlags(rawValue: 1 << 19)
        public static let command = ModifierFlags(rawValue: 1 << 20)
    }

    public init(keyCode: UInt16, modifiers: ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init?(config: Any) {
        if let s = config as? String { self.init(string: s); return }
        if let n = config as? NSNumber { self.init(keyCode: n.uint16Value, modifiers: []); return }
        if let d = config as? [String: Any] {
            let c = ConfigDict(d)
            var code: UInt16?
            if let n = c["key code", "keycode"] as? NSNumber { code = n.uint16Value }
            if code == nil, let ch = c.string("key char", "keychar", "key") { code = KeyCombo.keyCode(forName: ch) }
            guard let code else { return nil }
            var mods = ModifierFlags()
            if let m = c["modifiers"] as? NSNumber {
                // PopClip-style numeric flags use the same NSEvent modifier bit layout.
                mods = ModifierFlags(rawValue: m.intValue & (ModifierFlags.shift.rawValue | ModifierFlags.control.rawValue
                                                              | ModifierFlags.option.rawValue | ModifierFlags.command.rawValue))
            } else if let m = c.string("modifiers") {
                mods = KeyCombo(string: m + " a")?.modifiers ?? []
            }
            self.init(keyCode: code, modifiers: mods)
            return
        }
        return nil
    }

    public init?(string: String) {
        var mods = ModifierFlags()
        var rest = string
        // Symbol form: ⌘⇧⌥⌃
        let symbols: [(Character, ModifierFlags)] = [("⌘", .command), ("⇧", .shift), ("⌥", .option), ("⌃", .control)]
        for (sym, flag) in symbols where rest.contains(sym) {
            mods.insert(flag)
            rest.removeAll { $0 == sym }
        }
        let tokens = rest.replacingOccurrences(of: "+", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(String.init)
        var keyToken: String?
        for token in tokens {
            switch token.lowercased() {
            case "command", "cmd", "meta", "super": mods.insert(.command)
            case "shift": mods.insert(.shift)
            case "option", "opt", "alt": mods.insert(.option)
            case "control", "ctrl", "ctl": mods.insert(.control)
            default: keyToken = token
            }
        }
        if keyToken == nil, string.hasSuffix("+") || string.hasSuffix("-") { keyToken = String(string.last!) }
        guard let keyToken, let code = KeyCombo.keyCode(forName: keyToken) else { return nil }
        self.init(keyCode: code, modifiers: mods)
    }

    public var description: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (KeyCombo.displayName(forKeyCode: keyCode) ?? "#\(keyCode)")
    }

    // MARK: - Key code tables (ANSI US layout virtual key codes)

    static let letterCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50,
    ]

    static let namedCodes: [String: UInt16] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126, "arrowleft": 123, "arrowright": 124, "arrowdown": 125,
        "arrowup": 126, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "keypadenter": 76,
    ]

    public static func keyCode(forName name: String) -> UInt16? {
        let lower = name.lowercased()
        if lower.count == 1, let c = lower.first, let code = letterCodes[c] { return code }
        if let code = namedCodes[normalizeKey(lower)] { return code }
        if let n = UInt16(lower), lower.count > 1 { return n }
        return nil
    }

    public static func displayName(forKeyCode code: UInt16) -> String? {
        if let entry = letterCodes.first(where: { $0.value == code }) { return String(entry.key).uppercased() }
        let symbols: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘",
                                         116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1",
                                         120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
                                         101: "F9", 109: "F10", 103: "F11", 111: "F12", 76: "⌤"]
        return symbols[code]
    }
}
