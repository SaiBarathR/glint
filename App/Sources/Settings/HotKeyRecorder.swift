import AppKit
import GlintCore
import SwiftUI

/// Click to record a global shortcut. Captures the next key press that has ⌘, ⌃ or ⌥ (or is a function key).
/// Esc cancels, ⌫ while recording clears, and the × button removes the shortcut.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo?
    var width: CGFloat = 156

    @StateObject private var recorder = HotKeyRecorderModel()

    private var label: String {
        if recorder.isRecording { return "Press shortcut…" }
        return combo?.description ?? "Record Shortcut"
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: combo != nil && !recorder.isRecording ? .medium : .regular))
                .foregroundStyle(combo == nil || recorder.isRecording ? Color.secondary : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            if recorder.isRecording {
                Button {
                    recorder.stop()
                } label: {
                    Image(systemName: "escape")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Cancel (Esc)")
            } else if combo != nil {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove shortcut")
            }
        }
        .padding(.leading, combo != nil || recorder.isRecording ? 20 : 8)
        .padding(.trailing, combo != nil || recorder.isRecording ? 2 : 8)
        .frame(width: width, height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(recorder.isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                              lineWidth: recorder.isRecording ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start { combo = $0 }
            }
        }
        .onDisappear { recorder.stop() }
        .help(recorder.isRecording ? "Press a shortcut that includes ⌘, ⌃ or ⌥. Esc cancels." : "Click to record a shortcut")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

final class HotKeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var onCapture: ((KeyCombo?) -> Void)?

    /// F1–F20.
    static let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113,
                                                106, 64, 79, 80, 90]

    func start(_ handler: @escaping (KeyCombo?) -> Void) {
        stop()
        onCapture = handler
        isRecording = true
        // Release existing global shortcuts so pressing one records it instead of running it.
        HotKeyCenter.shared.suspend()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil,
                                                                queue: .main) { [weak self] _ in self?.stop() }
    }

    func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        resignObserver = nil
        onCapture = nil
        if isRecording {
            isRecording = false
            HotKeyCenter.shared.resume()
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let hasPrimary = !mods.intersection([.control, .option, .command]).isEmpty
        let isFunctionKey = Self.functionKeyCodes.contains(event.keyCode)

        if event.keyCode == 53, mods.isEmpty {  // Esc
            stop()
            return nil
        }
        if (event.keyCode == 51 || event.keyCode == 117), mods.isEmpty {  // ⌫ / ⌦ clears
            onCapture?(nil)
            stop()
            return nil
        }
        guard hasPrimary || isFunctionKey else {
            NSSound.beep()
            return nil
        }
        let combo = KeyCombo(keyCode: event.keyCode, modifiers: KeyCombo.ModifierFlags(rawValue: Int(mods.rawValue)))
        onCapture?(combo)
        stop()
        return nil
    }

    deinit { stop() }
}
