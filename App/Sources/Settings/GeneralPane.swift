import AppKit
import SwiftUI

struct GeneralPane: View {
    @ObservedObject private var prefs = Preferences.shared
    @EnvironmentObject private var nav: SettingsNavigator

    static let suppressChoices: [(label: String, value: Int)] = [
        ("None", 0),
        ("⌥ Option", Int(NSEvent.ModifierFlags.option.rawValue)),
        ("⌃ Control", Int(NSEvent.ModifierFlags.control.rawValue)),
        ("⌘ Command", Int(NSEvent.ModifierFlags.command.rawValue)),
        ("⇧ Shift", Int(NSEvent.ModifierFlags.shift.rawValue)),
    ]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.enabled) {
                    Text("Enable Glint")
                    Text("Show the action bar when you select text.")
                }
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                Toggle(isOn: $prefs.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("When the icon is hidden, open Glint again to bring up Settings.")
                }
            }

            Section("Permissions") {
                AccessibilityStatusRow(forcedStatus: nav.previewAccessibilityTrusted)
            }

            Section {
                Toggle("Selecting with the mouse", isOn: $prefs.activateOnDrag)
                Toggle(isOn: $prefs.activateOnDoubleClick) {
                    Text("Double-click")
                    Text("Selects a word.")
                }
                Toggle(isOn: $prefs.activateOnTripleClick) {
                    Text("Triple-click")
                    Text("Selects a line or paragraph.")
                }
                Toggle(isOn: $prefs.activateOnShiftClick) {
                    Text("Shift-click")
                    Text("Extends the current selection.")
                }
                Toggle(isOn: $prefs.activateOnKeyboardSelection) {
                    Text("Selecting with the keyboard")
                    Text("⇧ with the arrow keys, or ⌘A.")
                }
                Toggle(isOn: $prefs.activateOnLongPress) {
                    Text("Long press in a text field")
                    Text("Shows Paste when nothing is selected.")
                }
            } header: {
                Text("Show the Bar After")
            }

            Section("Behavior") {
                Picker(selection: $prefs.suppressModifier) {
                    ForEach(Self.suppressChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                } label: {
                    Text("Hold to suppress")
                    Text("Hold this key while selecting to keep the bar hidden.")
                }

                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { prefs.popupDelay },
                            set: { prefs.popupDelay = ($0 * 20).rounded() / 20 }
                        ), in: 0...1)
                            .frame(width: 170)
                        Text(delayLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                } label: {
                    Text("Delay before showing")
                }

                LabeledContent {
                    HotKeyRecorder(combo: $prefs.showBarHotKey)
                } label: {
                    Text("Show bar shortcut")
                    Text("Shows the bar for the current selection, from any app.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var delayLabel: String {
        prefs.popupDelay < 0.01 ? "None" : String(format: "%.2f s", prefs.popupDelay)
    }
}
