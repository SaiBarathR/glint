import Foundation

public enum StandardCommand: String {
    case cut, copy, paste, pasteMatchStyle = "paste-plain", selectAll = "select-all", undo, redo
}

/// What the app provides to running actions. Implementations must be callable from any thread.
public protocol ActionHost: AnyObject {
    /// Replace the selection with `text` (via the clipboard). Restores the previous clipboard when asked.
    func pasteText(_ text: String, restoreClipboard: Bool)
    func copyText(_ text: String)
    func openURL(_ url: URL, background: Bool, appBundleID: String?)
    func pressKey(_ combo: KeyCombo)
    func performCommand(_ command: StandardCommand)
    /// Runs a macOS Service on `text`. Returns the text the service returned, if any.
    func performService(_ name: String, text: String) -> Bool
    /// Show `text` in the bar. With `preview`, clicking it copies the text.
    func showText(_ text: String, preview: Bool)
    func showStatus(success: Bool)
    /// Open this extension's settings.
    func showSettings(extensionID: String)
    /// Log a line to the extension console.
    func log(_ message: String, extensionID: String)
    /// The clipboard's current text (for `pasteboard.text` in JavaScript).
    func currentClipboardText() -> String?
}

public extension ActionHost {
    func currentClipboardText() -> String? { nil }
}

public enum ActionOutcome: Equatable {
    case done
    case result(String)
    case failure(String)
    /// Script asked for its settings to be shown (shell exit code 2 / JS `showSettings`).
    case settingsError
}
