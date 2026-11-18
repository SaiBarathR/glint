import AppKit
import XCTest
@testable import GlintCore

/// Records what bundled extensions ask the app to do. Thread-safe: JavaScript and shell actions
/// call back from background queues.
final class BundledRecordingHost: ActionHost {
    private let lock = NSLock()
    private var _pasted: [String] = [], _copied: [String] = [], _opened: [(URL, Bool)] = []
    private var _shown: [(String, Bool)] = [], _statuses: [Bool] = [], _logs: [String] = [], _settings: [String] = []

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var pasted: [String] { locked { _pasted } }
    var copied: [String] { locked { _copied } }
    var opened: [(URL, Bool)] { locked { _opened } }
    var shown: [(String, Bool)] { locked { _shown } }
    var statuses: [Bool] { locked { _statuses } }
    var logs: [String] { locked { _logs } }
    var settingsShown: [String] { locked { _settings } }

    func pasteText(_ text: String, restoreClipboard: Bool) { locked { _pasted.append(text) } }
    func copyText(_ text: String) { locked { _copied.append(text) } }
    func openURL(_ url: URL, background: Bool, appBundleID: String?) { locked { _opened.append((url, background)) } }
    func pressKey(_ combo: KeyCombo) {}
    func performCommand(_ command: StandardCommand) {}
    func performService(_ name: String, text: String) -> Bool { false }
    func showText(_ text: String, preview: Bool) { locked { _shown.append((text, preview)) } }
    func showStatus(success: Bool) { locked { _statuses.append(success) } }
    func showSettings(extensionID: String) { locked { _settings.append(extensionID) } }
    func log(_ message: String, extensionID: String) { locked { _logs.append(message) } }
}

final class BundledExtensionsTests: XCTestCase {
    /// `<repo>/App/Resources/Extensions`, found relative to this file.
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() } // file, GlintCoreTests, Tests, GlintCore, Packages
        return url.appendingPathComponent("App/Resources/Extensions", isDirectory: true)
    }()

    static let loaded = ExtensionLoader.loadAll(in: directory, isBuiltIn: true)

    func manifest(_ slug: String) throws -> ExtensionManifest {
        let id = "dev.saibarath.glint." + slug
        return try XCTUnwrap(Self.loaded.extensions.first { $0.identifier == id }, "missing bundled extension \(id)")
    }

    func action(_ m: ExtensionManifest, _ title: String) throws -> ActionSpec {
        try XCTUnwrap(m.actions.first { $0.title == title }, "\(m.name) has no action \(title)")
    }

    /// The option values the app would pass: defaults, overridden by `overrides`.
    func optionValues(_ m: ExtensionManifest, _ overrides: [String: String]) -> [String: String] {
        var values: [String: String] = [:]
        for o in m.options { if let d = o.defaultValue { values[o.id] = d } }
        for (k, v) in overrides { values[k] = v }
        return values
    }

    /// Evaluates requirements like the app does (the action must be offered), then runs it.
    @discardableResult
    func run(_ slug: String, _ title: String? = nil, text: String, modifiers: ModifierState = [],
             options: [String: String] = [:], canPaste: Bool = true,
             file: StaticString = #filePath, line: UInt = #line) async throws -> (ActionOutcome, BundledRecordingHost) {
        let m = try manifest(slug)
        let a = try title.map { try action(m, $0) } ?? XCTUnwrap(m.actions.first)
        let ctx = SelectionContext(text: text, appBundleID: "com.apple.TextEdit", appName: "TextEdit",
                                   canCut: canPaste, canCopy: true, canPaste: canPaste, clipboardText: "clip")
        let input = try XCTUnwrap(RequirementEvaluator.evaluate(a, context: ctx),
                                  "\(m.name) › \(a.title) should be offered for \(text.debugDescription)", file: file, line: line)
        let host = BundledRecordingHost()
        let outcome = await ExtensionRuntime(host: host).perform(a, of: m, input: input, context: ctx, modifiers: modifiers,
                                                                 options: optionValues(m, options))
        return (outcome, host)
    }

    /// Runs an action that pastes its result and returns the pasted text.
    func pasted(_ slug: String, _ title: String? = nil, _ text: String, modifiers: ModifierState = [],
                options: [String: String] = [:], file: StaticString = #filePath, line: UInt = #line) async throws -> String? {
        let (outcome, host) = try await run(slug, title, text: text, modifiers: modifiers, options: options, file: file, line: line)
        guard case .result(let result) = outcome else {
            XCTFail("\(slug) › \(title ?? "") returned \(outcome)", file: file, line: line)
            return nil
        }
        XCTAssertEqual(host.pasted, [result], file: file, line: line)
        return result
    }

    func isOffered(_ slug: String, _ title: String? = nil, for text: String) throws -> Bool {
        let m = try manifest(slug)
        let a = try title.map { try action(m, $0) } ?? XCTUnwrap(m.actions.first)
        return RequirementEvaluator.evaluate(a, context: SelectionContext(text: text, canCut: true, canPaste: true)) != nil
    }

    // MARK: - Loading

    func testAllBundledExtensionsLoad() throws {
        let (extensions, errors) = Self.loaded
        XCTAssertTrue(errors.isEmpty, errors.map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(extensions.count, 20)

        let ids = extensions.map(\.identifier)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate identifiers: \(ids)")
        for m in extensions {
            XCTAssertTrue(m.identifier.hasPrefix("dev.saibarath.glint."), m.identifier)
            XCTAssertTrue(m.isBuiltIn, m.identifier)
            XCTAssertFalse(m.description?.isEmpty ?? true, "\(m.identifier) needs a description")
            XCTAssertFalse(m.actions.isEmpty, "\(m.identifier) has no actions")
            XCTAssertNotNil(m.icon, "\(m.identifier) needs an icon")
            for a in m.actions {
                XCTAssertFalse(a.icon?.isEmpty ?? true, "\(m.identifier) › \(a.title) has no icon")
            }
        }
        // The two extensions the app enables by default must exist.
        XCTAssertNoThrow(try manifest("translate"))
        XCTAssertNoThrow(try manifest("change-case"))
    }

    func testSymbolIconsExist() {
        for m in Self.loaded.extensions {
            for spec in [m.icon] + m.actions.map(\.icon) {
                guard let spec, spec.lowercased().hasPrefix("symbol:") else { continue }
                let name = String(spec.dropFirst("symbol:".count))
                XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                                "\(m.identifier): \(name) is not an SF Symbol on this macOS")
            }
        }
    }

    func testFormatsAreParsedAsExpected() throws {
        // Script files in a bundle.
        guard case .scriptFile(.shell, "encode.sh", _) = try manifest("base64").actions[0].kind else {
            return XCTFail("Base64 Encode should be a shell script file")
        }
        // Inverted perl snippet.
        guard case .script(.shell, let src, let interpreter) = try manifest("codepoints").actions[0].kind else {
            return XCTFail("Character Codes should be a shell script")
        }
        XCTAssertEqual(interpreter, "perl")
        XCTAssertTrue(src.contains("U+%04X"))
        // JavaScript modules.
        XCTAssertEqual(try manifest("change-case").actions.map(\.title),
                       ["UPPERCASE", "lowercase", "Title Case", "Sentence case", "camelCase", "snake_case", "kebab-case"])
        XCTAssertTrue(try manifest("change-case").actions.allSatisfy { $0.after == .pasteResult })
        // AppleScript actions are only parsed here: running them would create real reminders and notes.
        for slug in ["reminders", "notes"] {
            let a = try manifest(slug).actions[0]
            guard case .script(.appleScript, let source, _) = a.kind else { return XCTFail("\(slug) should be AppleScript") }
            XCTAssertTrue(source.contains("\"{glint text}\""), slug)
            XCTAssertEqual(a.after, .showStatus)
        }
        let translate = try manifest("translate")
        XCTAssertEqual(translate.options.first?.id, "lang")
        XCTAssertEqual(translate.options.first?.kind, .multiple)
        XCTAssertEqual(translate.options.first?.defaultValue, "en")
        XCTAssertEqual(translate.options.first?.values.count, translate.options.first?.valueLabels.count)
    }

    // MARK: - Web actions

    func testSearchURLs() async throws {
        let expected: [String: String] = [
            "wikipedia": "https://en.wikipedia.org/w/index.php?search=swift%20ui",
            "youtube": "https://www.youtube.com/results?search_query=swift%20ui",
            "maps": "maps://?q=swift%20ui",
            "github-search": "https://github.com/search?q=swift%20ui&type=repositories",
            "stack-overflow": "https://stackoverflow.com/search?q=swift%20ui",
            "amazon": "https://www.amazon.com/s?k=swift%20ui",
            "dictionary": "https://www.dictionary.com/browse/swift%20ui",
            "ask-claude": "https://claude.ai/new?q=swift%20ui",
            "perplexity": "https://www.perplexity.ai/search?q=swift%20ui",
            "x-search": "https://x.com/search?q=swift%20ui",
            "reddit": "https://www.reddit.com/search/?q=swift%20ui",
            "translate": "https://translate.google.com/?sl=auto&tl=en&text=swift%20ui&op=translate",
        ]
        for (slug, url) in expected {
            let (outcome, host) = try await run(slug, text: " swift ui ")
            XCTAssertEqual(outcome, .done, slug)
            XCTAssertEqual(host.opened.map(\.0.absoluteString), [url], slug)
            XCTAssertEqual(host.opened.first?.1, false, slug)
        }
        let (_, synonyms) = try await run("dictionary", "Synonyms", text: "happy")
        XCTAssertEqual(synonyms.opened.first?.0.absoluteString, "https://www.thesaurus.com/browse/happy")
        XCTAssertFalse(try isOffered("dictionary", for: "https://apple.com"))
    }

    func testURLModifiersAndOptions() async throws {
        // ⌥ uses the alternate URL.
        let (_, alt) = try await run("maps", text: "1 Infinite Loop", modifiers: .option)
        XCTAssertEqual(alt.opened.first?.0.absoluteString, "https://www.google.com/maps/search/?api=1&query=1%20Infinite%20Loop")
        // ⌘ opens in the background.
        let (_, bg) = try await run("github-search", text: "glint", modifiers: .command)
        XCTAssertEqual(bg.opened.first?.1, true)
        // ⇧ copies the URL instead of opening it.
        let (_, copy) = try await run("wikipedia", text: "Ada", modifiers: .shift)
        XCTAssertTrue(copy.opened.isEmpty)
        XCTAssertEqual(copy.copied, ["https://en.wikipedia.org/w/index.php?search=Ada"])
        // Option values are filled into the URL.
        let (_, fr) = try await run("translate", text: "good morning", options: ["lang": "fr"])
        XCTAssertEqual(fr.opened.first?.0.absoluteString,
                       "https://translate.google.com/?sl=auto&tl=fr&text=good%20morning&op=translate")
    }

    // MARK: - Change Case

    func testChangeCase() async throws {
        let cases: [(String, String, String)] = [
            ("UPPERCASE", "Hello, wörld", "HELLO, WÖRLD"),
            ("lowercase", "Hello, WÖRLD", "hello, wörld"),
            ("Title Case", "the lord OF the rings", "The Lord of the Rings"),
            ("Title Case", "a tale of two cities\n\"war and peace\"", "A Tale of Two Cities\n\"War and Peace\""),
            ("Sentence case", "HELLO THERE. how are you? i think i'm fine", "Hello there. How are you? I think I'm fine"),
            ("camelCase", "parse HTTP response", "parseHttpResponse"),
            ("camelCase", "user_id-value", "userIdValue"),
            ("snake_case", "XMLHttpRequest", "xml_http_request"),
            ("snake_case", "Hello World\nsecond line", "hello_world\nsecond_line"),
            ("kebab-case", "Hello World Again", "hello-world-again"),
            ("kebab-case", "someVariableName", "some-variable-name"),
        ]
        for (title, input, expected) in cases {
            let result = try await pasted("change-case", title, input)
            XCTAssertEqual(result, expected, "\(title): \(input)")
        }
    }

    func testChangeCaseCopiesWhenNotEditable() async throws {
        let (outcome, host) = try await run("change-case", "UPPERCASE", text: "read only", canPaste: false)
        XCTAssertEqual(outcome, .result("READ ONLY"))
        XCTAssertTrue(host.pasted.isEmpty)
        XCTAssertEqual(host.copied, ["READ ONLY"])
        // ⇧ copies too.
        let (_, shifted) = try await run("change-case", "lowercase", text: "ABC", modifiers: .shift)
        XCTAssertEqual(shifted.copied, ["abc"])
    }

    // MARK: - Text tools

    func testSortLines() async throws {
        let text = "banana\nApple\ncherry\napple\nitem 10\nitem 2"
        let asc = try await pasted("sort-lines", nil, text)
        XCTAssertEqual(asc, "Apple\napple\nbanana\ncherry\nitem 2\nitem 10")
        let desc = try await pasted("sort-lines", nil, text, modifiers: .option)
        XCTAssertEqual(desc, "item 10\nitem 2\ncherry\nbanana\napple\nApple")
        let unique = try await pasted("sort-lines", nil, "b\na\nB\na", options: ["unique": "1"])
        XCTAssertEqual(unique, "a\nB") // ties keep the first in sorted order; uppercase sorts first
        let caseSensitiveUnique = try await pasted("sort-lines", nil, "b\na\nB\na", options: ["unique": "1", "ignoreCase": "0"])
        XCTAssertEqual(caseSensitiveUnique, "a\nb\nB")
    }

    func testURLEncodeDecode() async throws {
        let encoded = try await pasted("url-encode", "URL Encode", "a b&c/é?")
        XCTAssertEqual(encoded, "a%20b%26c%2F%C3%A9%3F")
        let decoded = try await pasted("url-encode", "URL Decode", "a%20b+c%2F%C3%A9")
        XCTAssertEqual(decoded, "a b c/é")
        XCTAssertFalse(try isOffered("url-encode", "URL Decode", for: "plain words"))
        // Malformed escapes fail rather than pasting garbage.
        let (bad, host) = try await run("url-encode", "URL Decode", text: "100%25 and %E0%A4%A")
        if case .failure = bad {} else { XCTFail("expected failure, got \(bad)") }
        XCTAssertEqual(host.statuses, [false])
    }

    func testBase64() async throws {
        let encoded = try await pasted("base64", "Base64 Encode", "hello wörld")
        XCTAssertEqual(encoded, "aGVsbG8gd8O2cmxk")
        let decoded = try await pasted("base64", "Base64 Decode", "aGVsbG8gd8O2cmxk")
        XCTAssertEqual(decoded, "hello wörld")
        let urlSafe = try await pasted("base64", "Base64 Decode", "Pz8_")
        XCTAssertEqual(urlSafe, "???")
        XCTAssertFalse(try isOffered("base64", "Base64 Decode", for: "not base64!"))
        // "//79" decodes to the bytes FF FE FD: not UTF-8 text, so it fails.
        let (bad, host) = try await run("base64", "Base64 Decode", text: "//79")
        if case .failure = bad {} else { XCTFail("expected failure, got \(bad)") }
        XCTAssertEqual(host.statuses, [false])
    }

    func testFormatJSON() async throws {
        let json = #"{"b":1,"a":[1,true,null],"s":"x"}"#
        let pretty = try await pasted("format-json", "Format JSON", json)
        XCTAssertEqual(pretty, "{\n  \"b\": 1,\n  \"a\": [\n    1,\n    true,\n    null\n  ],\n  \"s\": \"x\"\n}")
        let sorted = try await pasted("format-json", "Format JSON", json, options: ["sortKeys": "1", "indent": "4"])
        XCTAssertEqual(sorted, "{\n    \"a\": [\n        1,\n        true,\n        null\n    ],\n    \"b\": 1,\n    \"s\": \"x\"\n}")
        let tabbed = try await pasted("format-json", "Format JSON", "[1]", options: ["indent": "tab"])
        XCTAssertEqual(tabbed, "[\n\t1\n]")
        let minified = try await pasted("format-json", "Minify JSON", "{\n  \"a\" : [ 1, 2 ]\n}")
        XCTAssertEqual(minified, #"{"a":[1,2]}"#)

        let (outcome, host) = try await run("format-json", "Format JSON", text: "{not json}")
        guard case .failure(let message) = outcome else { return XCTFail("expected failure, got \(outcome)") }
        XCTAssertTrue(message.contains("Not valid JSON"), message)
        XCTAssertEqual(host.statuses, [false])
        XCTAssertTrue(host.pasted.isEmpty)
    }

    func testHashes() async throws {
        let (sha, host) = try await run("hash", "SHA-256", text: "hello")
        XCTAssertEqual(sha, .result("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"))
        XCTAssertEqual(host.shown.first?.0, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertEqual(host.shown.first?.1, true, "hashes use preview-result")
        let (sha1, _) = try await run("hash", "SHA-1", text: "hello")
        XCTAssertEqual(sha1, .result("aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"))
        let (md5, _) = try await run("hash", "MD5", text: "hello")
        XCTAssertEqual(md5, .result("5d41402abc4b2a76b9719d911017c592"))
        // The exact selection is hashed, surrounding whitespace included.
        let (spaced, _) = try await run("hash", "MD5", text: "hello ")
        XCTAssertNotEqual(spaced, md5)
    }

    func testWhitespace() async throws {
        let joined = try await pasted("whitespace", "Join Lines", "one\ntwo  \n  three\n\nfour\r\nfive")
        XCTAssertEqual(joined, "one two three\n\nfour five")
        let trimmed = try await pasted("whitespace", "Trim Whitespace", "  a   b\t\tc  \n\n\n\n   d  ")
        XCTAssertEqual(trimmed, "a b c\n\nd")
    }

    func testStraightQuotes() async throws {
        let result = try await pasted("straight-quotes", nil, "“Hi,” she said — it’s ‘fine’.")
        XCTAssertEqual(result, "\"Hi,\" she said — it's 'fine'.")
        XCTAssertFalse(try isOffered("straight-quotes", for: "no curly quotes here"))
    }

    func testWrap() async throws {
        let quoted = try await pasted("wrap", "Quotes", " hello ")
        XCTAssertEqual(quoted, " “hello” ")
        let parens = try await pasted("wrap", "Parentheses", "aside")
        XCTAssertEqual(parens, "(aside)")
        let brackets = try await pasted("wrap", "Brackets", "x")
        XCTAssertEqual(brackets, "[x]")
        let tick = try await pasted("wrap", "Backticks", "code")
        XCTAssertEqual(tick, "`code`")
        let fence = try await pasted("wrap", "Backticks", "a\nb")
        XCTAssertEqual(fence, "```\na\nb\n```")
    }

    func testMarkdownLink() async throws {
        let labelled = try await pasted("markdown-link", nil, "Glint docs https://example.com/docs")
        XCTAssertEqual(labelled, "[Glint docs](https://example.com/docs)")
        let bare = try await pasted("markdown-link", nil, "https://www.example.com/")
        XCTAssertEqual(bare, "[example.com](https://www.example.com/)")
        let parens = try await pasted("markdown-link", nil, "Swift: https://en.wikipedia.org/wiki/Swift_(language)")
        XCTAssertEqual(parens, "[Swift](https://en.wikipedia.org/wiki/Swift_%28language%29)")
        XCTAssertFalse(try isOffered("markdown-link", for: "no link here"))
    }

    func testPlainText() async throws {
        let (outcome, host) = try await run("plain-text", "Copy as Plain Text", text: "Bold words")
        XCTAssertEqual(outcome, .result("Bold words"))
        XCTAssertEqual(host.copied, ["Bold words"])
        XCTAssertEqual(host.statuses, [true])

        let html = "<div><p>Fish &amp; chips</p><script>x()</script><p>caf&#233; &lt;3<br>bye&nbsp;now</p></div>"
        let stripped = try await pasted("plain-text", "Strip HTML Tags", html)
        XCTAssertEqual(stripped, "Fish & chips\ncafé <3\nbye now")
        XCTAssertFalse(try isOffered("plain-text", "Strip HTML Tags", for: "1 < 2 and 3 > 2"))
    }

    func testCodepoints() async throws {
        let (outcome, host) = try await run("codepoints", text: "Aé😀")
        XCTAssertEqual(outcome, .result("U+0041 U+00E9 U+1F600"))
        XCTAssertEqual(host.shown.first?.1, true)
    }

    func testRunShortcutAsksForSettingsWithoutAName() async throws {
        let (outcome, host) = try await run("run-shortcut", text: "anything")
        XCTAssertEqual(outcome, .settingsError)
        XCTAssertEqual(host.settingsShown, ["dev.saibarath.glint.run-shortcut"])
    }

    func testOpenInTerminalOnlyForExistingPaths() throws {
        // Not run: it would open a Terminal window.
        XCTAssertTrue(try isOffered("open-in-terminal", for: "/usr/bin"))
        XCTAssertTrue(try isOffered("open-in-terminal", for: "~"))
        XCTAssertFalse(try isOffered("open-in-terminal", for: "/definitely/not/here"))
        XCTAssertFalse(try isOffered("open-in-terminal", for: "hello"))
    }

    func testOpenInTerminalScriptResolvesFolder() throws {
        // Exercise the path handling with `open` swapped for `echo`.
        let m = try manifest("open-in-terminal")
        guard case .script(.shell, let source, _) = m.actions[0].kind else { return XCTFail() }
        let dry = source.replacingOccurrences(of: "/usr/bin/open -a Terminal", with: "echo")
        for (text, folder) in [("/usr/bin/true", "/usr/bin"), ("\"/usr/lib\"", "/usr/lib"),
                               ("~", NSHomeDirectory())] {
            let r = ScriptRunner.runShellSync(source: dry, file: nil, interpreter: nil, environment: ["GLINT_TEXT": text],
                                              workingDirectory: nil, stdin: text)
            XCTAssertEqual(r.status, 0, r.stderr)
            XCTAssertEqual(r.stdout.trimmingCharacters(in: .newlines), folder, text)
        }
    }
}
