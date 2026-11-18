import AppKit
import GlintCore

/// Runs bar actions: built-ins natively, extensions through the GlintCore runtime.
final class ActionPerformer: ActionHost {
    static let shared = ActionPerformer()
    private lazy var runtime = ExtensionRuntime(host: self)
    private let popup = PopupController.shared
    private let prefs = Preferences.shared
    /// The selection the bar was shown for.
    var selection: CapturedSelection?
    private(set) var log: [String] = []

    func perform(_ action: BarAction, flags: NSEvent.ModifierFlags) {
        let mods = ModifierState(rawValue: Int(flags.rawValue) & (ModifierState.shift.rawValue | ModifierState.control.rawValue
                                                                  | ModifierState.option.rawValue | ModifierState.command.rawValue))
        guard let selection else { return }
        switch action.kind {
        case .builtin(let b, let variant):
            performBuiltin(b, variant: variant, selection: selection, mods: mods)
        case .extensionAction(let manifest, let spec, let input, let dynamicIndex):
            if !spec.stayVisible { popup.dismiss() }
            let options = prefs.optionValues(for: manifest)
            Task { [runtime] in
                // Let the target app regain its key state before keystrokes arrive.
                try? await Task.sleep(nanoseconds: 40_000_000)
                await runtime.perform(spec, of: manifest, input: input, context: selection.context, modifiers: mods,
                                      options: options, dynamicIndex: dynamicIndex)
            }
        }
    }

    /// Runs an entry's first applicable action directly (per-action hotkeys).
    func performFirstAction(of entryKey: String, selection: CapturedSelection) {
        self.selection = selection
        let actions = ActionBuilder.actions(for: selection).filter { $0.entryKey == entryKey }
        guard let first = actions.first else { NSSound.beep(); return }
        perform(first, flags: [])
    }

    // MARK: Built-ins

    private func performBuiltin(_ b: BuiltinID, variant: String?, selection: CapturedSelection, mods: ModifierState) {
        let ctx = selection.context
        let text = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = ContentDetector.detect(in: ctx.text)
        switch b {
        case .installExtension:
            do {
                let m = try ActionRegistry.shared.install(snippet: ctx.text)
                popup.showResult("Installed “\(m.name)”", preview: false)
            } catch {
                popup.showResult("Can't install: \(error.localizedDescription)", preview: false)
            }
        case .search:
            let template = prefs.searchTemplate
            let url = Templates.fillURL(template, text: text, options: [:])
            if mods.contains(.shift) { Clipboard.setString(url); popup.showStatus(success: true); return }
            popup.dismiss()
            if let u = URL(string: url) { openURL(u, background: mods.contains(.command), appBundleID: nil) }
        case .cut:
            popup.dismiss()
            KeySender.command(.cut)
        case .copy:
            KeySender.command(.copy)
            popup.showStatus(success: true)
        case .paste:
            popup.dismiss()
            if mods.contains(.option) { pastePlain() } else { KeySender.command(.paste) }
        case .pasteMatchStyle:
            popup.dismiss()
            pastePlain()
        case .openLink:
            if mods.contains(.shift) {
                Clipboard.setString(detected.urls.joined(separator: "\n"))
                popup.showStatus(success: true)
                return
            }
            popup.dismiss()
            for s in detected.urls { if let u = URL(string: s) { openURL(u, background: mods.contains(.command), appBundleID: nil) } }
        case .newMail:
            popup.dismiss()
            if let email = detected.emails.first, let u = URL(string: "mailto:\(email)") { NSWorkspace.shared.open(u) }
        case .revealInFinder:
            popup.dismiss()
            NSWorkspace.shared.activateFileViewerSelecting(detected.paths.map { URL(fileURLWithPath: $0) })
        case .lookUp:
            popup.dismiss()
            if mods.contains(.option) {
                // In-place definition popover (⌃⌘D) in apps that support it.
                KeySender.press(KeyCombo(keyCode: 2, modifiers: [.control, .command]))
            } else if let u = URL(string: "dict://" + Templates.urlEncode(text)) {
                NSWorkspace.shared.open(u)
            }
        case .spelling:
            let guesses = Spelling.guesses(for: text)
            guard !guesses.isEmpty else { popup.showResult("No suggestions", preview: false); return }
            popup.showChoices(guesses) { [weak self] choice, flags in
                self?.popup.dismiss()
                if flags.contains(.shift) { Clipboard.setString(choice) } else { self?.pasteText(choice, restoreClipboard: true) }
            }
        case .formatting:
            popup.dismiss()
            let key: UInt16 = variant == "italic" ? 34 : variant == "underline" ? 32 : 11
            KeySender.press(KeyCombo(keyCode: key, modifiers: .command))
        case .speak:
            popup.dismiss()
            Speech.shared.toggle(text)
        case .stats:
            popup.showResult(TextStats(ctx.text).summary, preview: true)
        case .calculate:
            let result = variant ?? ""
            if mods.contains(.shift), ctx.canPaste {
                popup.dismiss()
                pasteText(text.hasSuffix("=") ? "\(text) \(result)" : result, restoreClipboard: true)
            } else {
                Clipboard.setString(result)
                popup.showStatus(success: true)
            }
        }
    }

    private func pastePlain() {
        guard let s = Clipboard.string else { return }
        let snap = Clipboard.snapshot()
        Clipboard.setString(s)
        KeySender.command(.paste)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Clipboard.restore(snap) }
    }

    // MARK: ActionHost

    func pasteText(_ text: String, restoreClipboard: Bool) {
        onMain {
            let snap = Clipboard.snapshot()
            Clipboard.setString(text)
            KeySender.command(.paste)
            if restoreClipboard || self.prefs.restoreClipboardAfterPaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Clipboard.restore(snap) }
            }
        }
    }

    func copyText(_ text: String) { onMain { Clipboard.setString(text) } }

    func openURL(_ url: URL, background: Bool, appBundleID: String?) {
        onMain {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = !background
            if let appBundleID, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
            } else {
                NSWorkspace.shared.open(url, configuration: config)
            }
        }
    }

    func pressKey(_ combo: KeyCombo) { onMain { KeySender.press(combo) } }

    func performCommand(_ command: StandardCommand) {
        onMain {
            if command == .pasteMatchStyle { self.pastePlain() } else { KeySender.command(command) }
        }
    }

    func performService(_ name: String, text: String) -> Bool {
        var ok = false
        let work = {
            let pb = NSPasteboard(name: NSPasteboard.Name("dev.saibarath.glint.service"))
            pb.clearContents()
            pb.setString(text, forType: .string)
            ok = NSPerformService(name, pb)
            // Services that return text replace the selection when it is editable.
            if ok, let out = pb.string(forType: .string), out != text, self.selection?.context.canPaste == true {
                self.pasteText(out, restoreClipboard: true)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return ok
    }

    func showText(_ text: String, preview: Bool) { onMain { self.popup.showResult(text, preview: preview) } }

    func showStatus(success: Bool) { onMain { self.popup.showStatus(success: success) } }

    func showSettings(extensionID: String) { onMain { SettingsWindowController.shared.show(extensionKey: extensionID) } }

    func log(_ message: String, extensionID: String) {
        let line = "[\(extensionID)] \(message)"
        NSLog("Glint: %@", line)
        onMain {
            self.log.append(line)
            if self.log.count > 500 { self.log.removeFirst(self.log.count - 500) }
        }
    }

    func clearLog() { log.removeAll() }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
}
