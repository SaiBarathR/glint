import AppKit
import Carbon.HIToolbox

enum SelectionTrigger: Equatable {
    case drag, doubleClick, tripleClick, shiftClick, longPress, keyboard, hotKey
    /// The selection came from mouse input (anchor near the mouse is reasonable).
    var isMouse: Bool { self != .keyboard && self != .hotKey }
}

protocol SelectionMonitorDelegate: AnyObject {
    func selectionMonitor(_ monitor: SelectionMonitor, didDetect trigger: SelectionTrigger, at mouse: CGPoint,
                          iBeam: Bool)
    /// Any input that should hide the bar (click elsewhere, typing, scrolling).
    func selectionMonitorShouldDismiss(_ monitor: SelectionMonitor, reason: SelectionMonitor.DismissReason)
    func selectionMonitor(_ monitor: SelectionMonitor, mouseMovedTo point: CGPoint)
    func selectionMonitor(_ monitor: SelectionMonitor, modifiersChanged flags: NSEvent.ModifierFlags)
}

/// Watches global mouse and keyboard input and decides when a selection was likely made.
final class SelectionMonitor {
    enum DismissReason { case mouseDown, key, scroll, appSwitch }

    weak var delegate: SelectionMonitorDelegate?
    private var monitors: [Any] = []
    private let prefs = Preferences.shared

    private var downPoint: CGPoint = .zero
    private var downTime: Date = .distantPast
    private var downClickCount = 0
    private var downFlags: NSEvent.ModifierFlags = []
    private var downIBeam = false
    private var maxDistance: CGFloat = 0
    private var longPressTimer: Timer?
    private var longPressFired = false
    private var keyboardTimer: Timer?

    static let dragThreshold: CGFloat = 5

    func start() {
        stop()
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown,
                                                .otherMouseDown, .scrollWheel, .mouseMoved]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] e in self?.handleMouse(e) }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged],
                                                     handler: { [weak self] e in self?.handleKey(e) }) {
            monitors.append(m)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appChanged(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
            delegate?.selectionMonitorShouldDismiss(self, reason: .appSwitch)
        }
    }

    private var suppressed: Bool {
        let raw = prefs.suppressModifier
        guard raw != 0 else { return false }
        return NSEvent.modifierFlags.contains(NSEvent.ModifierFlags(rawValue: UInt(raw)))
    }

    private func handleMouse(_ e: NSEvent) {
        let point = NSEvent.mouseLocation
        switch e.type {
        case .leftMouseDown:
            // A click in the menu bar may be Edit ▸ Copy: let it win over a pending late-⌘C restore.
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }), point.y > screen.visibleFrame.maxY {
                Clipboard.noteClickHint()
            }
            delegate?.selectionMonitorShouldDismiss(self, reason: .mouseDown)
            downPoint = point
            downTime = Date()
            downClickCount = e.clickCount
            downFlags = e.modifierFlags
            downIBeam = CursorProbe.isIBeam
            maxDistance = 0
            longPressFired = false
            longPressTimer?.invalidate()
            if prefs.enabled, prefs.activateOnLongPress, e.clickCount == 1, downIBeam {
                longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                    guard let self, self.maxDistance < Self.dragThreshold else { return }
                    self.longPressFired = true
                    self.delegate?.selectionMonitor(self, didDetect: .longPress, at: self.downPoint, iBeam: true)
                }
            }
        case .leftMouseDragged:
            maxDistance = max(maxDistance, hypot(point.x - downPoint.x, point.y - downPoint.y))
            if maxDistance >= Self.dragThreshold {
                longPressTimer?.invalidate()
                // Held, then started dragging: it's a selection after all, not a paste request.
                if longPressFired {
                    longPressFired = false
                    delegate?.selectionMonitorShouldDismiss(self, reason: .mouseDown)
                }
            }
        case .leftMouseUp:
            longPressTimer?.invalidate()
            guard prefs.enabled, !longPressFired, !suppressed else { return }
            var trigger: SelectionTrigger?
            if maxDistance >= Self.dragThreshold, prefs.activateOnDrag {
                // Ignore long drags that clearly moved something rather than selecting (very slow, huge distance is fine).
                trigger = .drag
            } else if downClickCount == 2, prefs.activateOnDoubleClick {
                trigger = .doubleClick
            } else if downClickCount >= 3, prefs.activateOnTripleClick {
                trigger = .tripleClick
            } else if downClickCount == 1, downFlags.contains(.shift), prefs.activateOnShiftClick {
                trigger = .shiftClick
            }
            if let trigger { delegate?.selectionMonitor(self, didDetect: trigger, at: point, iBeam: downIBeam) }
        case .rightMouseDown, .otherMouseDown:
            Clipboard.noteClickHint() // context menus offer Copy
            delegate?.selectionMonitorShouldDismiss(self, reason: .mouseDown)
        case .scrollWheel:
            if abs(e.scrollingDeltaY) > 2 || abs(e.scrollingDeltaX) > 2 {
                delegate?.selectionMonitorShouldDismiss(self, reason: .scroll)
            }
        case .mouseMoved:
            delegate?.selectionMonitor(self, mouseMovedTo: point)
        default:
            break
        }
    }

    /// Matches the character the key types (layout-aware), with or without the ⌘-layout switch.
    static func typed(_ e: NSEvent, oneOf chars: Set<String>) -> Bool {
        // With ⌘ held, `characters` reflects layouts that switch to QWERTY under ⌘; fall back to the plain
        // character only when it's empty or a control character.
        if let typed = e.characters?.lowercased(), let scalar = typed.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar) {
            return chars.contains(typed)
        }
        return e.charactersIgnoringModifiers.map { chars.contains($0.lowercased()) } ?? false
    }

    private func handleKey(_ e: NSEvent) {
        if e.cgEvent?.getIntegerValueField(.eventSourceUserData) == KeySender.marker { return }
        switch e.type {
        case .flagsChanged:
            delegate?.selectionMonitor(self, modifiersChanged: e.modifierFlags)
        case .keyDown:
            if e.modifierFlags.contains(.command), Self.typed(e, oneOf: ["c", "x"]) {
                Clipboard.noteUserCopy()
            }
            delegate?.selectionMonitorShouldDismiss(self, reason: .key)
            keyboardTimer?.invalidate()
        case .keyUp:
            guard prefs.enabled, prefs.activateOnKeyboardSelection, !suppressed else { return }
            let code = Int(e.keyCode)
            let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End]
            let isShiftArrow = arrows.contains(code) && e.modifierFlags.contains(.shift)
            let isSelectAll = e.modifierFlags.contains(.command) && Self.typed(e, oneOf: ["a"])
            guard isShiftArrow || isSelectAll else { return }
            keyboardTimer?.invalidate()
            keyboardTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.delegate?.selectionMonitor(self, didDetect: .keyboard, at: NSEvent.mouseLocation, iBeam: false)
            }
        default:
            break
        }
    }
}
