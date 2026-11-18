import AppKit
import GlintCore

/// Decides which actions appear on the bar for a selection.
enum ActionBuilder {
    static func actions(for selection: CapturedSelection) -> [BarAction] {
        let registry = ActionRegistry.shared
        let prefs = Preferences.shared
        let ctx = selection.context
        let detected = ContentDetector.detect(in: ctx.text)
        var out: [BarAction] = []

        for entry in registry.entries where registry.isEnabled(entry.key) || entry.builtin == .installExtension {
            if let builtin = entry.builtin {
                out += builtinActions(builtin, entry: entry, selection: selection, detected: detected)
                continue
            }
            guard !selection.isPasteOnly, let manifest = entry.manifest else { continue }
            let options = prefs.optionValues(for: manifest)
            for (index, action) in manifest.actions.enumerated() {
                if case .jsModuleAction(let i) = action.kind, i < 0 {
                    // Dynamic actions computed by the extension's JavaScript.
                    guard let input = RequirementEvaluator.evaluate(action, context: ctx, detected: detected) else { continue }
                    let runtime = ExtensionRuntime(host: nil)
                    for (di, dyn) in runtime.populateDynamic(manifest, input: input, context: ctx, modifiers: [],
                                                             options: options).enumerated() {
                        out.append(BarAction(id: "\(entry.key)#dyn\(di)", entryKey: entry.key, title: dyn.title,
                                             icon: dyn.icon, iconBaseURL: manifest.bundleURL,
                                             kind: .extensionAction(manifest, dyn, input, dynamicIndex: di)))
                    }
                    continue
                }
                guard let input = RequirementEvaluator.evaluate(action, context: ctx, detected: detected) else { continue }
                out.append(BarAction(id: "\(entry.key)#\(index)", entryKey: entry.key, title: action.title,
                                     icon: action.icon ?? manifest.icon, iconBaseURL: manifest.bundleURL,
                                     kind: .extensionAction(manifest, action, input, dynamicIndex: nil)))
            }
        }
        return out
    }

    private static func make(_ b: BuiltinID, _ entry: RegistryEntry, title: String? = nil, icon: String? = nil,
                             variant: String? = nil, textOnly: Bool = false) -> BarAction {
        BarAction(id: entry.key + (variant.map { "#" + $0 } ?? ""), entryKey: entry.key, title: title ?? b.name,
                  icon: icon ?? b.icon, iconBaseURL: nil, kind: .builtin(b, variant: variant), textOnly: textOnly)
    }

    static func builtinActions(_ b: BuiltinID, entry: RegistryEntry, selection: CapturedSelection,
                               detected: DetectedContent) -> [BarAction] {
        let ctx = selection.context
        let text = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if selection.isPasteOnly {
            switch b {
            case .paste: return ctx.canPaste && ctx.clipboardText?.isEmpty == false ? [make(b, entry)] : []
            case .pasteMatchStyle: return ctx.canPaste && ctx.clipboardText?.isEmpty == false ? [make(b, entry)] : []
            default: return []
            }
        }
        guard !text.isEmpty else { return [] }
        switch b {
        case .installExtension:
            return ExtensionLoader.isSnippet(ctx.text) ? [make(b, entry)] : []
        case .search:
            return detected.urls.count == 1 && text.count < 300 && !text.contains(" ") ? [] : [make(b, entry)]
        case .cut:
            return ctx.canCut ? [make(b, entry)] : []
        case .copy:
            return ctx.canCopy ? [make(b, entry)] : []
        case .paste:
            return ctx.canPaste && ctx.clipboardText?.isEmpty == false ? [make(b, entry)] : []
        case .pasteMatchStyle:
            return ctx.canPaste && ctx.clipboardText?.isEmpty == false ? [make(b, entry)] : []
        case .openLink:
            guard !detected.urls.isEmpty else { return [] }
            if detected.urls.count == 1 {
                let host = URL(string: detected.urls[0])?.host ?? "Link"
                return [make(b, entry, title: "Open \(host)")]
            }
            return [make(b, entry, title: "Open \(detected.urls.count) Links", icon: "symbol:square.stack.3d.up")]
        case .newMail:
            return detected.emails.isEmpty ? [] : [make(b, entry, title: "Email \(detected.emails[0])")]
        case .call:
            return detected.phoneNumbers.count == 1 && text.count < 40 ? [make(b, entry, title: "Call \(detected.phoneNumbers[0])")] : []
        case .revealInFinder:
            return detected.paths.isEmpty ? [] : [make(b, entry)]
        case .lookUp:
            return text.count <= 60 && !text.contains("\n") && text.split(separator: " ").count <= 4 ? [make(b, entry)] : []
        case .spelling:
            guard ctx.canPaste || ctx.canCut, !text.contains(" "), text.count < 40, Spelling.isMisspelled(text) else { return [] }
            return [make(b, entry)]
        case .formatting:
            guard ctx.canFormat else { return [] }
            return [make(b, entry, title: "Bold", icon: "symbol:bold", variant: "bold"),
                    make(b, entry, title: "Italic", icon: "symbol:italic", variant: "italic"),
                    make(b, entry, title: "Underline", icon: "symbol:underline", variant: "underline")]
        case .speak:
            return [make(b, entry, title: Speech.shared.isSpeaking ? "Stop Speaking" : "Speak",
                         icon: Speech.shared.isSpeaking ? "symbol:stop.circle" : nil)]
        case .stats:
            return text.count >= 1 ? [make(b, entry)] : []
        case .calculate:
            guard let result = detected.mathResult else { return [] }
            return [make(b, entry, title: "= \(result)", variant: result, textOnly: true)]
        }
    }
}

enum Spelling {
    static func isMisspelled(_ word: String) -> Bool {
        guard word.rangeOfCharacter(from: .letters) != nil, word.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        return range.location != NSNotFound
    }

    static func guesses(for word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return Array((NSSpellChecker.shared.guesses(forWordRange: range, in: word, language: nil,
                                                    inSpellDocumentWithTag: 0) ?? []).prefix(6))
    }
}
