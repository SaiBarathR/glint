import AppKit
import XCTest
@testable import GlintCore

/// Records everything gallery extensions ask the app to do. Thread-safe: JavaScript and shell actions call back
/// from background queues.
final class GalleryMockHost: ActionHost {
    private let lock = NSLock()
    private var _pasted: [String] = [], _copied: [String] = [], _opened: [URL] = [], _shown: [String] = []
    private var _keys: [KeyCombo] = [], _services: [(String, String)] = [], _statuses: [Bool] = [], _logs: [String] = []

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var pasted: [String] { locked { _pasted } }
    var copied: [String] { locked { _copied } }
    var opened: [URL] { locked { _opened } }
    var shown: [String] { locked { _shown } }
    var keys: [KeyCombo] { locked { _keys } }
    var services: [(String, String)] { locked { _services } }
    var statuses: [Bool] { locked { _statuses } }
    var logs: [String] { locked { _logs } }

    func pasteText(_ text: String, restoreClipboard: Bool) { locked { _pasted.append(text) } }
    func copyText(_ text: String) { locked { _copied.append(text) } }
    func openURL(_ url: URL, background: Bool, appBundleID: String?) { locked { _opened.append(url) } }
    func pressKey(_ combo: KeyCombo) { locked { _keys.append(combo) } }
    func performCommand(_ command: StandardCommand) {}
    func performService(_ name: String, text: String) -> Bool { locked { _services.append((name, text)) }; return true }
    func showText(_ text: String, preview: Bool) { locked { _shown.append(text) } }
    func showStatus(success: Bool) { locked { _statuses.append(success) } }
    func showSettings(extensionID: String) {}
    func log(_ message: String, extensionID: String) { locked { _logs.append(message) } }
    func currentClipboardText() -> String? { "clip" }
}

/// Loads every extension in `gallery/` (the website's extension gallery) and runs the examples listed in
/// `gallery/catalog.json`, which are the same examples the website shows on each card.
final class GalleryExtensionsTests: XCTestCase {
    static let repo: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() } // file, GlintCoreTests, Tests, GlintCore, Packages
        return url
    }()
    static let galleryDir = repo.appendingPathComponent("gallery", isDirectory: true)

    struct Example {
        var action: String
        var input: String
        var raw: [String: Any]
    }

    struct Entry {
        var path: String
        var category: String
        var examples: [Example]
    }

    static let catalog: (categories: [String], entries: [Entry]) = {
        let url = galleryDir.appendingPathComponent("catalog.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], []) }
        let entries = (json["extensions"] as? [[String: Any]] ?? []).map { e in
            Entry(path: e["path"] as? String ?? "", category: e["category"] as? String ?? "",
                  examples: (e["examples"] as? [[String: Any]] ?? []).map {
                      Example(action: $0["action"] as? String ?? "", input: $0["input"] as? String ?? "", raw: $0)
                  })
        }
        return (json["categories"] as? [String] ?? [], entries)
    }()

    /// Loads one gallery item the way the app would after installing it: folders with `load(folder:)`,
    /// snippet files with `parseSnippet` (they are installed as snippets).
    static func load(_ path: String) throws -> ExtensionManifest {
        let url = galleryDir.appendingPathComponent(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ManifestError.unreadable("missing \(path)")
        }
        if isDir.boolValue { return try ExtensionLoader.load(folder: url) }
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(ExtensionLoader.isSnippet(text), "\(path) should start with a #glint header")
        return try ExtensionLoader.parseSnippet(text)
    }

    static let loaded: [String: Result<ExtensionManifest, Error>] = {
        var out: [String: Result<ExtensionManifest, Error>] = [:]
        for e in catalog.entries { out[e.path] = Result { try load(e.path) } }
        return out
    }()

    func manifest(_ path: String) throws -> ExtensionManifest {
        try XCTUnwrap(Self.loaded[path]).get()
    }

    // MARK: - Loading

    func testCatalogListsEveryGalleryItem() throws {
        let items = try FileManager.default.contentsOfDirectory(atPath: Self.galleryDir.path)
            .filter { $0.hasSuffix(".txt") || $0.hasSuffix(".glintext") }
        XCTAssertEqual(Set(items), Set(Self.catalog.entries.map(\.path)), "catalog.json and gallery/ disagree")
        XCTAssertGreaterThanOrEqual(items.count, 12)
        XCTAssertLessThanOrEqual(items.count, 20)
        for e in Self.catalog.entries {
            XCTAssertTrue(Self.catalog.categories.contains(e.category), "\(e.path): unknown category \(e.category)")
        }
    }

    func testAllGalleryExtensionsLoad() throws {
        var ids: [String] = []
        for e in Self.catalog.entries {
            switch Self.loaded[e.path] {
            case .success(let m):
                ids.append(m.identifier)
                XCTAssertTrue(m.identifier.hasPrefix("io.github.saibarathr.glint.gallery."), "\(e.path): \(m.identifier)")
                XCTAssertFalse(m.description?.isEmpty ?? true, "\(e.path) needs a description")
                XCTAssertNotNil(m.icon, "\(e.path) needs an extension icon")
                XCTAssertFalse(m.actions.isEmpty, "\(e.path) has no actions")
                for a in m.actions {
                    XCTAssertFalse(a.icon?.isEmpty ?? true, "\(e.path) › \(a.title) has no icon")
                }
            case .failure(let error):
                XCTFail("\(e.path) failed to load: \(error.localizedDescription)")
            case nil:
                XCTFail("\(e.path) was not loaded")
            }
        }
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate identifiers: \(ids)")

        // No clash with the extensions that ship in the app (a user extension with a bundled id replaces it).
        let bundled = ExtensionLoader.loadAll(in: Self.repo.appendingPathComponent("App/Resources/Extensions"), isBuiltIn: true)
        XCTAssertFalse(bundled.extensions.isEmpty)
        let clash = Set(ids).intersection(bundled.extensions.map(\.identifier))
        XCTAssertTrue(clash.isEmpty, "gallery identifiers clash with bundled ones: \(clash)")
        // Action titles inside one extension must be unique, since the website and the tests address them by title.
        for e in Self.catalog.entries {
            guard let m = try? manifest(e.path) else { continue }
            XCTAssertEqual(Set(m.actions.map(\.title)).count, m.actions.count, "\(e.path) repeats an action title")
        }
    }

    func testSymbolIconsExist() throws {
        for e in Self.catalog.entries {
            guard let m = try? manifest(e.path) else { continue }
            for spec in [m.icon] + m.actions.map(\.icon) {
                guard let spec, spec.lowercased().hasPrefix("symbol:") else { continue }
                let name = String(spec.dropFirst("symbol:".count))
                XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                                "\(e.path): \(name) is not an SF Symbol on this macOS")
            }
        }
    }

    func testStaticPreviewNeedsNoCode() throws {
        // What the install prompt shows: parsed without evaluating any JavaScript.
        for e in Self.catalog.entries {
            let url = Self.galleryDir.appendingPathComponent(e.path)
            let m: ExtensionManifest
            if e.path.hasSuffix(".glintext") {
                m = try ExtensionLoader.load(folder: url, evaluateModules: false)
            } else {
                m = try ExtensionLoader.parseSnippet(String(contentsOf: url, encoding: .utf8), evaluateModules: false)
            }
            XCTAssertFalse(m.name.isEmpty, e.path)
        }
    }

    func testFormats() throws {
        guard case .scriptFile(.shell, "unique.sh", _) = try manifest("LineTools.glintext").actions[0].kind else {
            return XCTFail("Line Tools should run shell script files")
        }
        guard case .scriptFile(.javaScript, "to-yaml.js", _) = try manifest("JSONToYAML.glintext").actions[0].kind else {
            return XCTFail("JSON to YAML should run a JavaScript file")
        }
        guard case .jsModuleAction = try manifest("EpochConverter.glintext").actions[0].kind else {
            return XCTFail("Epoch Converter's actions should come from its module")
        }
        XCTAssertEqual(try manifest("EpochConverter.glintext").actions.map(\.title), ["To Date", "To Timestamp"])
        XCTAssertEqual(try manifest("color-converter.txt").actions.map(\.title), ["To RGB", "To HSL", "To Hex"])
        guard case .script(.shell, _, _) = try manifest("rot13.txt").actions[0].kind else { return XCTFail("ROT13 is shell") }
        guard case .script(.appleScript, let source, _) = try manifest("mail-selection.txt").actions[0].kind else {
            return XCTFail("Mail Selection is AppleScript")
        }
        XCTAssertTrue(source.contains("\"{glint text}\""), "the placeholder must sit inside quotes")
        guard case .keyCombo = try manifest("toggle-comment.txt").actions[0].kind else { return XCTFail("Toggle Comment is a key combo") }
        XCTAssertTrue(try manifest("toggle-comment.txt").actions[0].requiredApps.contains("com.apple.dt.Xcode"))
        guard case .service("Make New Sticky Note") = try manifest("new-sticky.txt").actions[0].kind else {
            return XCTFail("New Sticky runs a service")
        }
        XCTAssertEqual(try manifest("developer-docs.txt").actions.count, 5)
        XCTAssertEqual(try manifest("hard-wrap.txt").options.first?.defaultValue, "80")
        XCTAssertEqual(try manifest("HeadlineCase.glintext").options.first?.values, ["chicago", "ap"])
    }

    // MARK: - Running the catalog examples

    static func modifiers(_ names: [String]) -> ModifierState {
        var m: ModifierState = []
        for n in names {
            switch n {
            case "shift": m.insert(.shift)
            case "option": m.insert(.option)
            case "command": m.insert(.command)
            case "control": m.insert(.control)
            default: break
            }
        }
        return m
    }

    func testCatalogExamples() async throws {
        var ran = 0
        for e in Self.catalog.entries {
            guard let m = try? manifest(e.path) else { continue }
            for ex in e.examples {
                let label = "\(e.path) › \(ex.action) ‹\(ex.input.prefix(40))›"
                let action = try XCTUnwrap(m.actions.first { $0.title == ex.action }, "\(label): no such action")
                let ctx = SelectionContext(text: ex.input, appBundleID: ex.raw["app"] as? String ?? "com.apple.TextEdit",
                                           appName: "TextEdit", canCut: true, canCopy: true, canPaste: true,
                                           clipboardText: "clip")
                // The action must be offered for this selection (requirements, regex, required apps).
                guard let input = RequirementEvaluator.evaluate(action, context: ctx) else {
                    XCTFail("\(label): not offered for this selection")
                    continue
                }
                var options: [String: String] = [:]
                for o in m.options { if let d = o.defaultValue { options[o.id] = d } }
                for (k, v) in ex.raw["options"] as? [String: String] ?? [:] { options[k] = v }
                let host = GalleryMockHost()
                let outcome = await ExtensionRuntime(host: host).perform(action, of: m, input: input, context: ctx,
                                                                         modifiers: Self.modifiers(ex.raw["modifiers"] as? [String] ?? []),
                                                                         options: options)
                ran += 1
                if case .failure(let message) = outcome { XCTFail("\(label) failed: \(message) \(host.logs)"); continue }

                if let expected = ex.raw["output"] as? String {
                    XCTAssertEqual(outcome, .result(expected), label)
                }
                if let fragment = ex.raw["contains"] as? String {
                    guard case .result(let r) = outcome else { XCTFail("\(label): no result"); continue }
                    XCTAssertTrue(r.contains(fragment), "\(label): \(r)")
                    if let count = ex.raw["paragraphs"] as? Int {
                        XCTAssertEqual(r.components(separatedBy: "\n\n").count, count, label)
                    }
                }
                if ex.raw["permutation"] as? Bool == true {
                    guard case .result(let r) = outcome else { XCTFail("\(label): no result"); continue }
                    XCTAssertEqual(r.components(separatedBy: "\n").sorted(), ex.input.components(separatedBy: "\n").sorted(), label)
                }
                if let url = ex.raw["opens"] as? String {
                    XCTAssertEqual(host.opened.map(\.absoluteString), [url], label)
                }
                if let keys = ex.raw["keys"] as? [String] {
                    XCTAssertEqual(host.keys, keys.compactMap { KeyCombo(string: $0) }, label)
                    XCTAssertEqual(keys.count, keys.compactMap { KeyCombo(string: $0) }.count, "\(label): unparsable key combo")
                }
                if let copied = ex.raw["copied"] as? [String] {
                    XCTAssertEqual(host.copied, copied, label)
                }
                if let service = ex.raw["service"] as? String {
                    XCTAssertEqual(host.services.map(\.0), [service], label)
                    XCTAssertEqual(host.services.first?.1, ex.input, label)
                }
                // paste-result actions paste in editable text; preview/show-result actions show the result.
                if case .result(let r) = outcome {
                    switch action.after {
                    case .pasteResult: XCTAssertEqual(host.pasted, [r], label)
                    case .showResult, .previewResult: XCTAssertEqual(host.shown, [r], label)
                    default: break
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(ran, 30)
    }

    // MARK: - Edge cases beyond the catalog

    func run(_ path: String, _ title: String, _ text: String, options: [String: String] = [:],
             canPaste: Bool = true) async throws -> (ActionOutcome?, GalleryMockHost) {
        let m = try manifest(path)
        let action = try XCTUnwrap(m.actions.first { $0.title == title })
        let ctx = SelectionContext(text: text, appBundleID: "com.apple.TextEdit", canCut: canPaste, canCopy: true, canPaste: canPaste)
        let host = GalleryMockHost()
        guard let input = RequirementEvaluator.evaluate(action, context: ctx) else { return (nil, host) }
        var values: [String: String] = [:]
        for o in m.options { if let d = o.defaultValue { values[o.id] = d } }
        for (k, v) in options { values[k] = v }
        let outcome = await ExtensionRuntime(host: host).perform(action, of: m, input: input, context: ctx, modifiers: [],
                                                                 options: values)
        return (outcome, host)
    }

    func testOfferedOnlyWhereTheyApply() async throws {
        // Regex-gated actions stay hidden for selections they can't handle.
        let notOffered: [(String, String, String)] = [
            ("LineTools.glintext", "Remove Duplicates", "a single line"),
            ("JSONToYAML.glintext", "JSON to YAML", "not json"),
            ("EpochConverter.glintext", "To Date", "12345"),
            ("EpochConverter.glintext", "To Timestamp", "yesterday"),
            ("color-converter.txt", "To Hex", "#ffbe36"),
            ("color-converter.txt", "To RGB", "rgb(1, 2, 3)"),
            ("color-converter.txt", "To RGB", "beef"),
            ("unit-converter.txt", "Unit Converter", "12 parsecs"),
            ("lorem-ipsum.txt", "Lorem Ipsum", "21"),
            ("jwt-decode.txt", "JWT Decode", "not.a.token"),
            ("clean-url.txt", "Clean URL", "no link here"),
            ("developer-docs.txt", "MDN", "https://example.com"),
            ("toggle-comment.txt", "Toggle Comment", "x = 1"), // TextEdit is not a code editor
        ]
        for (path, title, text) in notOffered {
            let (outcome, _) = try await run(path, title, text)
            XCTAssertNil(outcome, "\(path) › \(title) should not be offered for \(text.debugDescription)")
        }
    }

    func testFailuresAreReported() async throws {
        let (badJSON, host) = try await run("JSONToYAML.glintext", "JSON to YAML", "{\"a\": }")
        guard case .failure(let message) = badJSON else { return XCTFail("expected failure, got \(String(describing: badJSON))") }
        XCTAssertTrue(message.contains("Not valid JSON"), message)
        XCTAssertEqual(host.statuses, [false])

        let (empty, _) = try await run("slugify.txt", "Slugify", "!!!")
        guard case .failure = empty else { return XCTFail("slugify of punctuation should fail, got \(String(describing: empty))") }
    }

    func testCopiesInsteadOfPastingInReadOnlyText() async throws {
        let (outcome, host) = try await run("rot13.txt", "ROT13", "abc", canPaste: false)
        XCTAssertEqual(outcome, .result("nop"))
        XCTAssertTrue(host.pasted.isEmpty)
        XCTAssertEqual(host.copied, ["nop"])
    }

    func testHardWrapKeepsParagraphsAndBullets() async throws {
        let text = "- one two three four five six seven eight nine ten\n\nshort\n"
        let (outcome, _) = try await run("hard-wrap.txt", "Hard Wrap", text, options: ["width": "20"])
        XCTAssertEqual(outcome, .result("- one two three four\n  five six seven\n  eight nine ten\n\nshort\n"))
    }

    // MARK: - The website's tutorial

    /// Code blocks in a Markdown file that are installable snippets (first line is a #glint header).
    static func snippets(inMarkdown url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var blocks: [String] = [], current: [String]? = nil
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let c = current { blocks.append(c.joined(separator: "\n")); current = nil } else { current = [] }
            } else if current != nil {
                current!.append(line)
            }
        }
        return blocks.filter { ExtensionLoader.isSnippet($0) }
    }

    func testTutorialSnippetsWork() async throws {
        let guide = Self.repo.appendingPathComponent("site/src/guides/writing-extensions.md")
        let blocks = try Self.snippets(inMarkdown: guide)
        XCTAssertGreaterThanOrEqual(blocks.count, 5, "the tutorial's snippets weren't found")
        var byName: [String: ExtensionManifest] = [:]
        for block in blocks {
            let m = try ExtensionLoader.parseSnippet(block)
            XCTAssertFalse(m.actions.isEmpty, m.name)
            for a in m.actions {
                if let spec = a.icon, spec.hasPrefix("symbol:") {
                    XCTAssertNotNil(NSImage(systemSymbolName: String(spec.dropFirst(7)), accessibilityDescription: nil), spec)
                }
            }
            byName[m.name] = m // later (fuller) versions replace earlier ones
        }

        func run(_ name: String, _ text: String, modifiers: ModifierState = [], options: [String: String] = [:]) async throws -> ActionOutcome {
            let m = try XCTUnwrap(byName[name], "tutorial has no \(name)")
            let a = try XCTUnwrap(m.actions.first)
            let ctx = SelectionContext(text: text, canCut: true, canCopy: true, canPaste: true)
            let input = try XCTUnwrap(RequirementEvaluator.evaluate(a, context: ctx), "\(name) not offered")
            var values: [String: String] = [:]
            for o in m.options { if let d = o.defaultValue { values[o.id] = d } }
            for (k, v) in options { values[k] = v }
            return await ExtensionRuntime(host: GalleryMockHost()).perform(a, of: m, input: input, context: ctx,
                                                                         modifiers: modifiers, options: values)
        }

        // 1. MDN
        let mdn = try XCTUnwrap(byName["MDN"])
        guard case .url(let template, let alt) = mdn.actions[0].kind else { return XCTFail("MDN is a URL action") }
        XCTAssertTrue(template.contains("***"))
        XCTAssertNotNil(alt)
        // 2. Indent, and ⌥ outdents
        let indented = try await run("Indent", "a\n  b")
        XCTAssertEqual(indented, .result("  a\n    b"))
        let outdented = try await run("Indent", "  a\n    b", modifiers: .option)
        XCTAssertEqual(outdented, .result("a\n  b"))
        // 3. Truncate
        let long = String(repeating: "word ", count: 60)
        let truncated = try await run("Truncate", long, options: ["length": "80"])
        guard case .result(let t) = truncated else { return XCTFail("Truncate returned \(truncated)") }
        XCTAssertLessThanOrEqual(t.count, 80)
        XCTAssertTrue(t.hasSuffix("word…"), t)
        let short = try await run("Truncate", "short text")
        XCTAssertEqual(short, .result("short text"))
        let noWords = try await run("Truncate", String(repeating: "x", count: 100), options: ["length": "80", "words": "0", "ellipsis": "..."])
        XCTAssertEqual(noWords, .result(String(repeating: "x", count: 77) + "..."))
    }

    func testSnippetsFitInAnInstallLink() throws {
        // The website offers glint://install?snippet=… for every snippet file.
        for e in Self.catalog.entries where e.path.hasSuffix(".txt") {
            let text = try String(contentsOf: Self.galleryDir.appendingPathComponent(e.path), encoding: .utf8)
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let encoded = try XCTUnwrap(text.addingPercentEncoding(withAllowedCharacters: allowed))
            let url = try XCTUnwrap(URL(string: "glint://install?snippet=" + encoded))
            let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "snippet" }?.value
            XCTAssertEqual(decoded, text, "\(e.path) doesn't survive the install link")
            XCTAssertLessThan(url.absoluteString.utf8.count, 16_000, "\(e.path) is too long for a link")
        }
    }
}
