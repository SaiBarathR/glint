import AppKit

// PLACEHOLDER: replaced by the full SwiftUI settings window.
enum SettingsPane: String, CaseIterable { case general, actions, apps, advanced, about }

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    func show(pane: SettingsPane? = nil) {}
    func show(extensionKey: String) {}
}

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    func show() {}
}
