import AppKit
import GlintCore

/// A selection ready to show the bar for.
struct CapturedSelection {
    var context: SelectionContext
    /// Where to anchor the bar (Cocoa screen coordinates).
    var anchor: CGRect
    /// The bar was summoned without a selection (long-press paste).
    var isPasteOnly: Bool
}

enum SelectionReader {
    private static let ownBundleID = Bundle.main.bundleIdentifier

    /// Reads the current selection of the frontmost app.
    /// - Parameters:
    ///   - mouse: mouse location for anchoring when the selection rect is unknown.
    ///   - allowCopyFallback: may send ⌘C when Accessibility returns nothing.
    ///   - pasteOnly: build a context for a long-press "Paste" bar instead.
    static func capture(mouse: CGPoint?, allowCopyFallback: Bool, pasteOnly: Bool = false,
                        requireNearMouse: Bool = false) async -> CapturedSelection? {
        let prefs = Preferences.shared
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != ownBundleID else { return nil }
        if prefs.isExcluded(bundleID: app.bundleIdentifier) { return nil }

        let pid = app.processIdentifier
        let (axText, element, editable, secure, bounds, docURL) = await Task.detached(priority: .userInitiated) {
            () -> (String?, AXUIElement?, Bool, Bool, CGRect?, String?) in
            guard let el = AX.focusedElement() else { return (nil, nil, false, false, nil, nil) }
            AXUIElementSetMessagingTimeout(el, 0.3)
            if AX.isSecure(el) { return (nil, el, false, true, nil, nil) }
            let text = pasteOnly ? nil : AX.selectedText(el)
            let editable = AX.isEditable(el)
            let bounds = pasteOnly ? nil : AX.selectionBounds(el)
            return (text, el, editable, false, bounds, AX.documentURL(el))
        }.value
        if secure { return nil }

        var text = axText ?? ""
        var html: String?
        if !pasteOnly, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Chromium/Electron need a nudge to expose their tree; next selection will work via AX.
            if element == nil || axText == nil { AX.enableEnhancedAccessibility(pid: pid) }
            guard allowCopyFallback, prefs.useCopyFallback, let copied = await Clipboard.copySelection() else { return nil }
            text = copied.0
            html = copied.1
        }
        if !pasteOnly, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if text.count > prefs.maxTextLength { return nil }
        // When the pointer wasn't over text (e.g. a window drag), only trust a selection that sits under the mouse,
        // otherwise an old selection in another field would make the bar appear.
        if requireNearMouse, !pasteOnly {
            guard let mouse, let bounds, bounds.insetBy(dx: -40, dy: -40).contains(mouse) else { return nil }
        }

        let menu = await Task.detached(priority: .userInitiated) { AX.menuCommands(pid: pid) }.value
        let clipboard = await MainActor.run { Clipboard.string }
        // Cut being enabled in the menu means the selection is editable even if AX didn't say so.
        let isEditable = editable || (menu.cut == true)
        let context = SelectionContext(
            text: text, html: html, appBundleID: app.bundleIdentifier, appName: app.localizedName,
            canCut: !pasteOnly && isEditable && (menu.cut ?? true),
            canCopy: !pasteOnly && (menu.copy ?? true),
            canPaste: isEditable && (menu.paste ?? true),
            canFormat: isEditable && (menu.bold == true),
            clipboardText: clipboard, sourceURL: docURL)

        if pasteOnly, !context.canPaste { return nil }

        var anchor: CGRect
        if let bounds, bounds.width < 4000 {
            anchor = bounds
            // Multi-line selections: anchor at the first line near the mouse.
            if let mouse, bounds.height > 60, bounds.contains(mouse) {
                anchor = CGRect(x: mouse.x - 1, y: mouse.y - 8, width: 2, height: 16)
            }
        } else if let mouse {
            anchor = CGRect(x: mouse.x - 1, y: mouse.y - 8, width: 2, height: 16)
        } else if let el = element, let frame = AX.frame(el) {
            anchor = CGRect(x: frame.midX - 1, y: frame.maxY - 20, width: 2, height: 16)
        } else {
            let m = NSEvent.mouseLocation
            anchor = CGRect(x: m.x - 1, y: m.y - 8, width: 2, height: 16)
        }
        return CapturedSelection(context: context, anchor: anchor, isPasteOnly: pasteOnly)
    }
}
