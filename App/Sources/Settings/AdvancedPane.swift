import AppKit
import SwiftUI

struct AdvancedPane: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var confirmingReset = false
    @State private var resetDone = false

    private var maxLengthBinding: Binding<Int> {
        Binding(get: { prefs.maxTextLength },
                set: { prefs.maxTextLength = min(max($0, 100), 10_000_000) })
    }

    var body: some View {
        Form {
            Section("Reading the Selection") {
                Toggle(isOn: $prefs.useCopyFallback) {
                    Text("Copy the selection when an app doesn't share it")
                    Text("Glint briefly simulates ⌘C in apps that don't share the selected text through Accessibility.")
                }
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField("Maximum length", value: maxLengthBinding, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 96)
                        Text("characters")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Maximum text length")
                    Text("The most selected text Glint reads at once.")
                }
            }

            Section("Clipboard") {
                Toggle(isOn: $prefs.restoreClipboardAfterPaste) {
                    Text("Restore the clipboard after pasting")
                    Text("Puts your previous clipboard back after an action pastes its result.")
                }
            }

            Section("Permissions") {
                LabeledContent {
                    Button("Open Accessibility Settings") { Permissions.openAccessibilitySettings() }
                } label: {
                    Text("Accessibility")
                    Text("Required to read selections and show the bar.")
                }
                LabeledContent {
                    Button("Open Automation Settings") { Permissions.openAutomationSettings() }
                } label: {
                    Text("Automation")
                    Text("Lets AppleScript actions and extensions control other apps.")
                }
            }

            Section {
                LabeledContent {
                    Button("Reset…") { confirmingReset = true }
                } label: {
                    Text("Reset all settings")
                    Text("Restores every setting to its default. Installed extensions are kept.")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive, action: resetAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every Glint setting goes back to its default, including action order, shortcuts and excluded apps.")
        }
        .alert("Settings were reset", isPresented: $resetDone) {
            Button("Relaunch Now", action: Self.relaunch)
            Button("Later", role: .cancel) {}
        } message: {
            Text("Relaunch Glint to finish resetting.")
        }
    }

    private func resetAll() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: id)
        UserDefaults.standard.synchronize()
        resetDone = true
    }

    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open -n \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
