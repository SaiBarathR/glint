import AppKit
import GlintCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = argumentValue("--render-settings") {
            SettingsWindowController.renderSnapshots(to: URL(fileURLWithPath: dir))
            exit(0)
        }
        _ = ActionRegistry.shared
    }

    private func argumentValue(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
