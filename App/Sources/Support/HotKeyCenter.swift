import AppKit
import Carbon.HIToolbox
import GlintCore

/// Registers system-wide shortcuts with the Carbon hot key API (no Accessibility permission needed).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var combos: [UInt32: KeyCombo] = [:]
    private var suspendCount = 0
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
        combos.removeAll()
    }

    /// Temporarily releases all shortcuts (e.g. while the user records a new one), keeping them for `resume()`.
    func suspend() {
        suspendCount += 1
        guard suspendCount == 1 else { return }
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        guard suspendCount == 0 else { return }
        for (id, combo) in combos { refs[id] = carbonRegister(combo, id: id) }
    }

    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        combos[id] = combo
        handlers[id] = handler
        if suspendCount > 0 { return true }
        guard let ref = carbonRegister(combo, id: id) else {
            combos.removeValue(forKey: id)
            handlers.removeValue(forKey: id)
            return false
        }
        refs[id] = ref
        return true
    }

    private func carbonRegister(_ combo: KeyCombo, id: UInt32) -> EventHotKeyRef? {
        var mods: UInt32 = 0
        if combo.modifiers.contains(.command) { mods |= UInt32(cmdKey) }
        if combo.modifiers.contains(.shift) { mods |= UInt32(shiftKey) }
        if combo.modifiers.contains(.option) { mods |= UInt32(optionKey) }
        if combo.modifiers.contains(.control) { mods |= UInt32(controlKey) }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(combo.keyCode), mods, EventHotKeyID(signature: OSType(0x474C4E54), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }
}
