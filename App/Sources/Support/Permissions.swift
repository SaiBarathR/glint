import AppKit
import ApplicationServices

enum Permissions {
    /// Accessibility access is needed to read selections, find their position and send key presses.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Glint to Accessibility settings.
    static func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Polls until access is granted, then calls `handler` on the main thread.
    static func waitForAccessibility(_ handler: @escaping () -> Void) {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                handler()
            }
        }
    }
}
