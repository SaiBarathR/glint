import AppKit
import Carbon.HIToolbox
import GlintCore

/// Posts synthetic key presses to the frontmost app.
enum KeySender {
    private static let source = CGEventSource(stateID: .hidSystemState)

    static func press(_ combo: KeyCombo) {
        press(keyCode: CGKeyCode(combo.keyCode), flags: cgFlags(combo.modifiers))
    }

    static func press(keyCode usKeyCode: CGKeyCode, flags inFlags: CGEventFlags) {
        // Codes are US-layout positions; type the same character on the user's layout (adding Shift when the
        // character lives on the shifted level there).
        let t = KeyLayout.translate(UInt16(usKeyCode), command: inFlags.contains(.maskCommand))
        let keyCode = CGKeyCode(t.code)
        var flags = inFlags
        if t.needsShift { flags.insert(.maskShift) }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        // Mark our events so the selection monitor can ignore them.
        down.setIntegerValueField(.eventSourceUserData, value: KeySender.marker)
        up.setIntegerValueField(.eventSourceUserData, value: KeySender.marker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static let marker: Int64 = 0x474C4E54 // "GLNT"

    static func cgFlags(_ m: KeyCombo.ModifierFlags) -> CGEventFlags {
        var f = CGEventFlags()
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        return f
    }

    static func command(_ cmd: StandardCommand) {
        switch cmd {
        case .cut: press(keyCode: CGKeyCode(kVK_ANSI_X), flags: .maskCommand)
        case .copy: press(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        case .paste: press(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        case .pasteMatchStyle: press(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskAlternate, .maskShift])
        case .selectAll: press(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        case .undo: press(keyCode: CGKeyCode(kVK_ANSI_Z), flags: .maskCommand)
        case .redo: press(keyCode: CGKeyCode(kVK_ANSI_Z), flags: [.maskCommand, .maskShift])
        }
    }
}
