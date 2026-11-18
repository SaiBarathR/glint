import AppKit
import ApplicationServices

/// Thin helpers over the Accessibility C API.
enum AX {
    static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.3)
        return el
    }()

    static func attribute(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? { attribute(el, name) as? String }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attribute(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        (attribute(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func isSettable(_ el: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(el, name as CFString, &settable) == .success && settable.boolValue
    }

    static func pid(_ el: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(el, &pid) == .success ? pid : nil
    }

    static func parameterized(_ el: AXUIElement, _ name: String, _ param: AnyObject) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(el, name as CFString, param, &value) == .success else { return nil }
        return value
    }

    static func focusedElement() -> AXUIElement? {
        if let el = element(systemWide, kAXFocusedUIElementAttribute) { return el }
        // Some apps only answer through their application element.
        if let app = NSWorkspace.shared.frontmostApplication {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            return element(appEl, kAXFocusedUIElementAttribute)
        }
        return nil
    }

    /// Chromium and Electron apps only build their accessibility tree when asked.
    static func enableEnhancedAccessibility(pid: pid_t) {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    // MARK: Selection

    static func selectedText(_ el: AXUIElement) -> String? {
        if let s = string(el, kAXSelectedTextAttribute) { return s }
        // Web views expose selection through text markers.
        if let range = attribute(el, "AXSelectedTextMarkerRange"),
           let s = parameterized(el, "AXStringForTextMarkerRange", range) as? String {
            return s
        }
        return nil
    }

    /// Screen rect (Cocoa coordinates, bottom-left origin) of the current selection.
    static func selectionBounds(_ el: AXUIElement) -> CGRect? {
        var rect: CGRect?
        if let rangeValue = attribute(el, kAXSelectedTextRangeAttribute), CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length > 0,
               let b = parameterized(el, kAXBoundsForRangeParameterizedAttribute, rangeValue) {
                rect = cgRect(b)
            }
        }
        if rect == nil, let markers = attribute(el, "AXSelectedTextMarkerRange"),
           let b = parameterized(el, "AXBoundsForTextMarkerRange", markers) {
            rect = cgRect(b)
        }
        guard let r = rect, r.width > 0 || r.height > 0, r.width < 10_000 else { return nil }
        return toCocoa(r)
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let posV = attribute(el, kAXPositionAttribute), let sizeV = attribute(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(posV as! AXValue, .cgPoint, &p), AXValueGetValue(sizeV as! AXValue, .cgSize, &s) else { return nil }
        return toCocoa(CGRect(origin: p, size: s))
    }

    static func cgRect(_ value: AnyObject) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &r) ? r : nil
    }

    /// AX uses a top-left origin on the primary screen; AppKit uses bottom-left.
    static func toCocoa(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.origin.x, y: primaryHeight - r.origin.y - r.height, width: r.width, height: r.height)
    }

    // MARK: Element traits

    static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]

    static func isSecure(_ el: AXUIElement) -> Bool {
        string(el, kAXSubroleAttribute) == kAXSecureTextFieldSubrole || string(el, kAXRoleAttribute) == "AXSecureTextField"
    }

    /// True when the focused element accepts typing.
    static func isEditable(_ el: AXUIElement) -> Bool {
        let role = string(el, kAXRoleAttribute) ?? ""
        if textRoles.contains(role) {
            return isSettable(el, kAXValueAttribute) || isSettable(el, kAXSelectedTextAttribute)
                || (attribute(el, "AXEditable") as? Bool ?? true)
        }
        if element(el, "AXEditableAncestor") != nil { return true }
        if let editable = attribute(el, "AXEditable") as? Bool { return editable }
        return isSettable(el, kAXSelectedTextAttribute)
    }

    /// URL of the document / page the element belongs to (browsers expose AXURL on the web area).
    static func documentURL(_ el: AXUIElement) -> String? {
        var current: AXUIElement? = el
        for _ in 0..<12 {
            guard let c = current else { break }
            if let url = attribute(c, kAXURLAttribute) as? URL { return url.absoluteString }
            if let doc = string(c, kAXDocumentAttribute) { return doc }
            current = element(c, kAXParentAttribute)
        }
        return nil
    }

    // MARK: Menus

    struct MenuCommands {
        var cut: Bool?
        var copy: Bool?
        var paste: Bool?
        var bold: Bool?
    }

    /// Reads the enabled state of the app's ⌘X / ⌘C / ⌘V / ⌘B menu items.
    /// ⌘B often lives in a Format › Font (or Style) submenu, so those submenus are searched one level deeper.
    static func menuCommands(pid: pid_t) -> MenuCommands {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.25)
        var result = MenuCommands()
        guard let bar = element(appEl, kAXMenuBarAttribute) else { return result }
        let submenuTitles: Set<String> = ["font", "style", "text", "format", "formatting", "schrift", "police", "fuente", "stil"]

        // ⌘B is "Build" in IDEs, so it only counts as Bold when it is titled so or lives in a formatting menu.
        let boldTitles: Set<String> = ["bold", "fett", "gras", "negrita", "grassetto", "negrito", "vet", "fed", "fet",
                                       "lihavoitu", "pogrubienie", "tučné", "полужирный", "жирный", "太字", "粗体", "粗體",
                                       "굵게", "kalın", "κομψή", "έντονα"]

        func scan(_ menu: AXUIElement, depth: Int, inFormatMenu: Bool) {
            for item in children(menu) {
                if let char = string(item, kAXMenuItemCmdCharAttribute)?.uppercased(), char.count == 1,
                   ((attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int) ?? 0) == 0 {
                    let enabled = (attribute(item, kAXEnabledAttribute) as? Bool) ?? false
                    switch char {
                    case "X": result.cut = enabled
                    case "C": result.copy = enabled
                    case "V": result.paste = enabled
                    case "B":
                        let title = string(item, kAXTitleAttribute)?.lowercased() ?? ""
                        if inFormatMenu || boldTitles.contains(title) { result.bold = enabled }
                    default: break
                    }
                } else if depth < 2, result.bold == nil,
                          let title = string(item, kAXTitleAttribute)?.lowercased(), submenuTitles.contains(title) {
                    for sub in children(item) { scan(sub, depth: depth + 1, inFormatMenu: true) }
                }
            }
        }

        for top in children(bar).dropFirst() { // skip the Apple menu
            let topTitle = string(top, kAXTitleAttribute)?.lowercased() ?? ""
            for menu in children(top) { scan(menu, depth: 0, inFormatMenu: submenuTitles.contains(topTitle)) }
            if result.cut != nil, result.copy != nil, result.paste != nil, result.bold != nil { break }
        }
        return result
    }
}
