import Foundation

/// Executes extension actions and applies their `after` behaviour through an `ActionHost`.
public final class ExtensionRuntime {
    public weak var host: ActionHost?
    public init(host: ActionHost?) { self.host = host }

    /// Runs one action. `options` are the user's current option values for the extension.
    @discardableResult
    public func perform(_ action: ActionSpec, of manifest: ExtensionManifest, input: ActionInput, context: SelectionContext,
                        modifiers: ModifierState, options: [String: String], dynamicIndex: Int? = nil) async -> ActionOutcome {
        let outcome = await execute(action, of: manifest, input: input, context: context, modifiers: modifiers,
                                    options: options, dynamicIndex: dynamicIndex)
        apply(outcome, after: action.after, action: action, manifest: manifest, context: context, modifiers: modifiers)
        return outcome
    }

    func execute(_ action: ActionSpec, of manifest: ExtensionManifest, input: ActionInput, context: SelectionContext,
                 modifiers: ModifierState, options: [String: String], dynamicIndex: Int?) async -> ActionOutcome {
        let text = input.matchedText
        switch action.kind {
        case .url(let template, let alternate):
            let chosen = (modifiers.contains(.option) ? alternate : nil) ?? template
            let filled = Templates.fillURL(chosen, text: text, options: options,
                                           extras: Templates.extras(input: input, context: context))
            guard let url = URL(string: filled) else { return .failure("Invalid URL: \(filled)") }
            if modifiers.contains(.shift) {
                host?.copyText(url.absoluteString)
                host?.showStatus(success: true)
                return .done
            }
            host?.openURL(url, background: modifiers.contains(.command), appBundleID: nil)
            return .done

        case .keyCombo(let combo):
            host?.pressKey(combo)
            return .done

        case .keyCombos(let combos):
            for combo in combos {
                host?.pressKey(combo)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return .done

        case .service(let name):
            return host?.performService(name, text: text) == true ? .done : .failure("Service “\(name)” failed")

        case .shortcut(let name):
            switch await ScriptRunner.runShortcut(name: name, input: text) {
            case .success(let out): return out.map { .result($0) } ?? .done
            case .failure(let e): return .failure(e.message)
            }

        case .script(let kind, let source, let interpreter):
            return await runScript(kind: kind, source: source, file: nil, interpreter: interpreter, manifest: manifest,
                                   input: input, context: context, modifiers: modifiers, options: options)

        case .scriptFile(let kind, let path, let interpreter):
            guard let base = manifest.bundleURL else { return .failure("Script file \(path) not found") }
            let file = base.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: file.path) else { return .failure("Script file \(path) not found") }
            return await runScript(kind: kind, source: nil, file: file, interpreter: interpreter, manifest: manifest,
                                   input: input, context: context, modifiers: modifiers, options: options)

        case .jsModuleAction(let index):
            guard let source = manifest.moduleSource else { return .failure("Missing JavaScript module") }
            let env = JavaScriptRunner.Environment(input: input, context: context, modifiers: modifiers, options: options,
                                                   optionSpecs: manifest.options, extensionID: manifest.identifier,
                                                   bundleURL: manifest.bundleURL)
            return await JavaScriptRunner.run(.module(source: source, actionIndex: index), env: env, host: host,
                                              dynamicIndex: dynamicIndex)

        case .native:
            return .failure("Native actions are handled by the app")
        }
    }

    func runScript(kind: ScriptKind, source: String?, file: URL?, interpreter: String?, manifest: ExtensionManifest,
                   input: ActionInput, context: SelectionContext, modifiers: ModifierState,
                   options: [String: String]) async -> ActionOutcome {
        switch kind {
        case .shell:
            let env = Self.environment(manifest: manifest, input: input, context: context, modifiers: modifiers, options: options)
            let r = await ScriptRunner.runShell(source: source, file: file, interpreter: interpreter, environment: env,
                                                workingDirectory: manifest.bundleURL, stdin: input.matchedText)
            if !r.stderr.isEmpty { host?.log(r.stderr, extensionID: manifest.identifier) }
            switch r.status {
            case 0:
                let out = r.stdout.hasSuffix("\n") ? String(r.stdout.dropLast()) : r.stdout
                return out.isEmpty ? .done : .result(out)
            case 2: return .settingsError
            default:
                let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(msg.isEmpty ? "Script exited with status \(r.status)" : msg)
            }
        case .appleScript:
            let extras = Templates.extras(input: input, context: context)
            let filled = source.map { Templates.fillAppleScript($0, text: input.matchedText, options: options, extras: extras) }
            switch await ScriptRunner.runAppleScript(source: filled, file: file) {
            case .success(let s): return (s?.isEmpty == false) ? .result(s!) : .done
            case .failure(let e): return .failure(e.message)
            }
        case .javaScript:
            var src = source
            if let file { src = try? String(contentsOf: file, encoding: .utf8) }
            guard let src else { return .failure("Couldn't read script") }
            let env = JavaScriptRunner.Environment(input: input, context: context, modifiers: modifiers, options: options,
                                                   optionSpecs: manifest.options, extensionID: manifest.identifier,
                                                   bundleURL: manifest.bundleURL)
            // A file that defines exports is a module with a single action.
            if file != nil, src.contains("exports.") || src.contains("module.exports") {
                return await JavaScriptRunner.run(.module(source: src, actionIndex: 0), env: env, host: host)
            }
            return await JavaScriptRunner.run(.inline(src), env: env, host: host)
        }
    }

    /// Environment for shell scripts. Variables are provided with both GLINT_ and POPCLIP_ prefixes.
    public static func environment(manifest: ExtensionManifest, input: ActionInput, context: SelectionContext,
                                   modifiers: ModifierState, options: [String: String]) -> [String: String] {
        // The environment (with both prefixes) must stay well under the 1 MB exec limit, so large values are
        // left out; scripts can always read the full text from stdin.
        let limit = 64 * 1024
        func capped(_ s: String) -> String { s.utf8.count <= limit ? s : "" }
        var base: [String: String] = [
            "TEXT": capped(input.matchedText),
            "FULL_TEXT": input.text == input.matchedText ? capped(input.text) : capped(input.text),
            "TEXT_TRUNCATED": input.matchedText.utf8.count > limit ? "1" : "0",
            "URLS": input.urls.joined(separator: "\n"),
            "BUNDLE_IDENTIFIER": context.appBundleID ?? "",
            "APP_NAME": context.appName ?? "",
            "MODIFIER_FLAGS": String(modifiers.rawValue),
            "EXTENSION_IDENTIFIER": manifest.identifier,
            "EXTENSION_PATH": manifest.bundleURL?.path ?? "",
            "BROWSER_URL": context.sourceURL ?? "",
            "HTML": capped(input.html ?? ""),
            "MARKDOWN": capped(input.text),
        ]
        base["URLS"] = capped(base["URLS"] ?? "")
        for (i, g) in input.regexGroups.enumerated() { base["REGEX_GROUP_\(i)"] = capped(g) }
        for (k, v) in options {
            base["OPTION_" + k.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.map(String.init).joined()] = capped(v)
        }
        // Overall budget (each value is exported twice). Duplicates and extras are dropped first, in a fixed
        // order, so GLINT_TEXT survives whenever it fits on its own.
        let budget = 384 * 1024
        func total() -> Int { base.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count + 16 } * 2 }
        let regexKeys = base.keys.filter { $0.hasPrefix("REGEX_GROUP_") }.sorted { $0.count != $1.count ? $0.count > $1.count : $0 > $1 }
        let optionKeys = base.keys.filter { $0.hasPrefix("OPTION_") }.sorted()
        let order = ["HTML", "MARKDOWN", "FULL_TEXT"] + regexKeys + ["URLS"] + optionKeys + ["TEXT"]
        for key in order where total() > budget {
            guard let v = base[key], !v.isEmpty else { continue }
            base[key] = ""
            if key == "TEXT" { base["TEXT_TRUNCATED"] = "1" }
        }
        var env: [String: String] = [:]
        for (k, v) in base {
            env["GLINT_" + k] = v
            env["POPCLIP_" + k] = v
        }
        return env
    }

    func apply(_ outcome: ActionOutcome, after: AfterAction, action: ActionSpec, manifest: ExtensionManifest,
               context: SelectionContext, modifiers: ModifierState) {
        switch outcome {
        case .failure(let message):
            host?.log(message, extensionID: manifest.identifier)
            host?.showStatus(success: false)
        case .settingsError:
            host?.showSettings(extensionID: manifest.identifier)
        case .done:
            if after == .showStatus { host?.showStatus(success: true) }
        case .result(let text):
            var effective = after
            if effective == .none { effective = .none }
            // Shift turns paste into copy (useful in read-only places too).
            if effective == .pasteResult, modifiers.contains(.shift) || !context.canPaste { effective = .copyResult }
            switch effective {
            case .pasteResult: host?.pasteText(text, restoreClipboard: action.restoreClipboard)
            case .copyResult: host?.copyText(text); host?.showStatus(success: true)
            case .showResult: host?.showText(text, preview: false)
            case .previewResult: host?.showText(text, preview: true)
            case .showStatus: host?.showStatus(success: true)
            case .none: break
            }
        }
    }

    /// Expands dynamic JavaScript actions (`exports.actions = function(...)`) for the current selection.
    public func populateDynamic(_ manifest: ExtensionManifest, input: ActionInput, context: SelectionContext,
                                modifiers: ModifierState, options: [String: String]) -> [ActionSpec] {
        guard let source = manifest.moduleSource else { return [] }
        let env = JavaScriptRunner.Environment(input: input, context: context, modifiers: modifiers, options: options,
                                               optionSpecs: manifest.options, extensionID: manifest.identifier,
                                               bundleURL: manifest.bundleURL)
        // The placeholder carries the module-level settings that every dynamic action inherits.
        let parent = manifest.actions.first { $0.kind == .jsModuleAction(index: -1) }
        return JavaScriptRunner.populate(moduleSource: source, env: env).enumerated().map { i, d in
            let c = ConfigDict(d)
            return ActionSpec(id: "dyn\(i)", title: c.string("title") ?? manifest.name, icon: c.string("icon") ?? manifest.icon,
                              kind: .jsModuleAction(index: i), requirements: [],
                              after: c.string("after").map { AfterAction(config: $0) } ?? parent?.after ?? .none,
                              stayVisible: c.bool("stay visible") ?? parent?.stayVisible ?? false,
                              captureHTML: c.bool("capture html") ?? parent?.captureHTML ?? false)
        }
    }
}
