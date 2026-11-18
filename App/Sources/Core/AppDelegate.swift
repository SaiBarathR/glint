import AppKit
import GlintCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ActionRegistry.shared
    }
}
