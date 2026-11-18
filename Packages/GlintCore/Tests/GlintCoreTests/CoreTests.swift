import XCTest
@testable import GlintCore

class MockHost: ActionHost {
    var pasted: [String] = []
    var copied: [String] = []
    var opened: [(URL, Bool)] = []
    var keys: [KeyCombo] = []
    var shown: [String] = []
    var statuses: [Bool] = []
    var logs: [String] = []
    var commands: [StandardCommand] = []
    func pasteText(_ text: String, restoreClipboard: Bool) { pasted.append(text) }
    func copyText(_ text: String) { copied.append(text) }
    func openURL(_ url: URL, background: Bool, appBundleID: String?) { opened.append((url, background)) }
    func pressKey(_ combo: KeyCombo) { keys.append(combo) }
    func performCommand(_ command: StandardCommand) { commands.append(command) }
    func performService(_ name: String, text: String) -> Bool { true }
    func showText(_ text: String, preview: Bool) { shown.append(text) }
    func showStatus(success: Bool) { statuses.append(success) }
    func showSettings(extensionID: String) {}
    func log(_ message: String, extensionID: String) { logs.append(message) }
}

final class CalculatorTests: XCTestCase {
    func testArithmetic() throws {
        XCTAssertEqual(try Calculator.evaluate("2 + 3 * 4"), 14)
        XCTAssertEqual(try Calculator.evaluate("(2 + 3) * 4"), 20)
        XCTAssertEqual(try Calculator.evaluate("2^10"), 1024)
        XCTAssertEqual(try Calculator.evaluate("-3 + 5"), 2)
        XCTAssertEqual(try Calculator.evaluate("1,234 + 1"), 1235)
        XCTAssertEqual(try Calculator.evaluate("10 ÷ 4"), 2.5)
        XCTAssertEqual(try Calculator.evaluate("sqrt(16) + 1 ="), 5)
        XCTAssertThrowsError(try Calculator.evaluate("1 / 0"))
        XCTAssertThrowsError(try Calculator.evaluate("2 +"))
    }

    func testLooksLikeExpression() {
        XCTAssertTrue(Calculator.looksLikeExpression("12 * 4"))
        XCTAssertFalse(Calculator.looksLikeExpression("hello world"))
        XCTAssertFalse(Calculator.looksLikeExpression("2024"))
        XCTAssertFalse(Calculator.looksLikeExpression("call me at 5-6"))
        XCTAssertEqual(Calculator.format(2.5), "2.5")
        XCTAssertEqual(Calculator.format(14), "14")
    }
}

final class DetectorTests: XCTestCase {
    func testURLsAndEmails() {
        let d = ContentDetector.detect(in: "see https://apple.com and mail bob@example.com")
        XCTAssertEqual(d.urls, ["https://apple.com"])
        XCTAssertEqual(d.emails, ["bob@example.com"])
        XCTAssertEqual(ContentDetector.detect(in: "github.com/foo").urls, ["https://github.com/foo"])
        XCTAssertEqual(ContentDetector.detect(in: "/usr/bin").paths, ["/usr/bin"])
        XCTAssertEqual(ContentDetector.detect(in: "3 * 7").mathResult, "21")
        XCTAssertNil(ContentDetector.detect(in: "plain words").mathResult)
    }

    func testStats() {
        let s = TextStats("Hello world. How are you?\nFine.")
        XCTAssertEqual(s.words, 6)
        XCTAssertEqual(s.lines, 2)
        XCTAssertEqual(s.sentences, 3)
    }
}

final class KeyComboTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(KeyCombo(string: "command B"), KeyCombo(keyCode: 11, modifiers: .command))
        XCTAssertEqual(KeyCombo(string: "cmd+shift+k"), KeyCombo(keyCode: 40, modifiers: [.command, .shift]))
        XCTAssertEqual(KeyCombo(string: "⌘⌥V"), KeyCombo(keyCode: 9, modifiers: [.command, .option]))
        XCTAssertEqual(KeyCombo(string: "option return")?.keyCode, 36)
        XCTAssertEqual(KeyCombo(config: ["keyChar": "I", "modifiers": 1 << 20])?.modifiers, .command)
        XCTAssertEqual(KeyCombo(keyCode: 11, modifiers: [.command, .shift]).description, "⇧⌘B")
    }
}

final class ManifestTests: XCTestCase {
    func testYAMLSnippet() throws {
        let m = try ExtensionLoader.parseSnippet("""
        #glint
        name: Search Wiki
        icon: W
        url: https://en.wikipedia.org/w/index.php?search=***
        """)
        XCTAssertEqual(m.name, "Search Wiki")
        XCTAssertEqual(m.actions.count, 1)
        XCTAssertEqual(m.actions[0].kind, .url(template: "https://en.wikipedia.org/w/index.php?search=***", alternateTemplate: nil))
    }

    func testPopClipStyleKeys() throws {
        let m = try ExtensionLoader.parseSnippet("""
        # popclip
        name: Upper
        Shell Script: tr a-z A-Z
        After: paste-result
        Requirements: [text, paste]
        """)
        XCTAssertEqual(m.actions[0].after, .pasteResult)
        XCTAssertEqual(m.actions[0].requirements, ["text", "paste"])
        if case .script(.shell, let src, _) = m.actions[0].kind { XCTAssertEqual(src, "tr a-z A-Z") } else { XCTFail() }
    }

    func testInvertedJavaScriptSnippet() throws {
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: Reverse
        // after: copy-result
        return glint.input.text.split('').reverse().join('')
        """)
        XCTAssertEqual(m.name, "Reverse")
        guard case .script(.javaScript, let src, _) = m.actions[0].kind else { return XCTFail() }
        XCTAssertTrue(src.contains("reverse()"))
    }

    func testInvertedShellSnippetWithLanguage() throws {
        let m = try ExtensionLoader.parseSnippet("""
        # #popclip
        # name: Py
        # language: python3
        import sys; print(sys.stdin.read().upper())
        """)
        guard case .script(.shell, _, let interp) = m.actions[0].kind else { return XCTFail() }
        XCTAssertEqual(interp, "python3")
    }

    func testMultipleActionsAndOptions() throws {
        let m = try ExtensionLoader.parseSnippet("""
        #glint
        name: Multi
        options:
          - identifier: engine
            type: multiple
            values: [a, b]
            default value: b
          - identifier: loud
            type: boolean
        actions:
          - title: One
            key combo: command 1
          - title: Two
            url: https://x.com/?q=***
            requirements: [url]
        """)
        XCTAssertEqual(m.actions.map(\.title), ["One", "Two"])
        XCTAssertEqual(m.options.map(\.id), ["engine", "loud"])
        XCTAssertEqual(m.options[0].defaultValue, "b")
        XCTAssertEqual(m.options[1].kind, .boolean)
    }

    func testSnippetDetection() {
        XCTAssertTrue(ExtensionLoader.isSnippet("#glint\nname: x"))
        XCTAssertTrue(ExtensionLoader.isSnippet("\n  # popclip\nname: x"))
        XCTAssertTrue(ExtensionLoader.isSnippet("-- #popclip\n-- name: x"))
        XCTAssertFalse(ExtensionLoader.isSnippet("# Heading\nname: x"))
    }

    func testJavaScriptModuleSnippet() throws {
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: Cases
        // language: javascript
        // module: true
        exports.actions = [
          { title: "Upper", icon: "AB", code: (input) => input.text.toUpperCase(), after: "paste-result" },
          { title: "Lower", code: (input) => input.text.toLowerCase() },
        ];
        """)
        XCTAssertEqual(m.actions.map(\.title), ["Upper", "Lower"])
        XCTAssertEqual(m.actions[0].after, .pasteResult)
    }
}

final class RequirementTests: XCTestCase {
    let urlAction = ActionSpec(id: "u", title: "Open", kind: .url(template: "***", alternateTemplate: nil), requirements: ["url"])

    func testURLRequirement() {
        XCTAssertNil(RequirementEvaluator.evaluate(urlAction, context: SelectionContext(text: "just words")))
        let input = RequirementEvaluator.evaluate(urlAction, context: SelectionContext(text: "go to https://a.com now"))
        XCTAssertEqual(input?.matchedText, "https://a.com")
    }

    func testNegationAndEditability() {
        let notURL = ActionSpec(id: "n", title: "N", kind: .native(id: "x"), requirements: ["text", "!url"])
        XCTAssertNil(RequirementEvaluator.evaluate(notURL, context: SelectionContext(text: "https://a.com")))
        XCTAssertNotNil(RequirementEvaluator.evaluate(notURL, context: SelectionContext(text: "hello")))
        let cut = ActionSpec(id: "c", title: "Cut", kind: .native(id: "cut"), requirements: ["cut"])
        XCTAssertNil(RequirementEvaluator.evaluate(cut, context: SelectionContext(text: "x", canCut: false)))
        XCTAssertNotNil(RequirementEvaluator.evaluate(cut, context: SelectionContext(text: "x", canCut: true)))
    }

    func testRegexAndApps() {
        var a = ActionSpec(id: "r", title: "R", kind: .native(id: "x"), regex: #"#(\d+)"#)
        let input = RequirementEvaluator.evaluate(a, context: SelectionContext(text: "issue #42 here"))
        XCTAssertEqual(input?.matchedText, "#42")
        XCTAssertEqual(input?.regexGroups, ["#42", "42"])
        a.requiredApps = ["com.apple.Safari"]
        XCTAssertNil(RequirementEvaluator.evaluate(a, context: SelectionContext(text: "#1", appBundleID: "com.apple.TextEdit")))
        XCTAssertNotNil(RequirementEvaluator.evaluate(a, context: SelectionContext(text: "#1", appBundleID: "com.apple.Safari")))
    }
}

final class TemplateTests: XCTestCase {
    func testURLFill() {
        XCTAssertEqual(Templates.fillURL("https://g.co/?q=***", text: "a b&c", options: [:]), "https://g.co/?q=a%20b%26c")
        XCTAssertEqual(Templates.fillURL("https://x/{popclip option lang}/{glint text}", text: "hi", options: ["lang": "fr"]),
                       "https://x/fr/hi")
    }

    func testExtraPlaceholders() {
        let ctx = SelectionContext(text: "see https://a.com", appBundleID: "com.x", appName: "My App")
        let input = ActionInput(text: "see https://a.com", urls: ["https://a.com"])
        let extras = Templates.extras(input: input, context: ctx)
        XCTAssertEqual(Templates.fillURL("x://{glint url}/{popclip app name}", text: "t", options: [:], extras: extras),
                       "x://https%3A%2F%2Fa.com/My%20App")
    }

    func testYAMLConfigWithModuleFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".glintext")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "name: Mod\nidentifier: t.mod\nmodule: main.js\n".write(to: dir.appendingPathComponent("Config.yaml"), atomically: true, encoding: .utf8)
        try "exports.actions = [{ title: 'Up', code: (i) => i.text.toUpperCase() }];".write(
            to: dir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        let m = try ExtensionLoader.loadBundle(at: dir)
        XCTAssertEqual(m.identifier, "t.mod")
        XCTAssertEqual(m.actions.map(\.title), ["Up"])
    }

    func testAppleScriptEscape() {
        XCTAssertEqual(Templates.fillAppleScript("say \"{glint text}\"", text: "a \"q\"", options: [:]), "say \"a \\\"q\\\"\"")
    }
}

final class RuntimeTests: XCTestCase {
    func run(_ snippet: String, text: String, modifiers: ModifierState = [], canPaste: Bool = true,
             options: [String: String] = [:]) async throws -> (ActionOutcome, MockHost) {
        let m = try ExtensionLoader.parseSnippet(snippet)
        let host = MockHost()
        let runtime = ExtensionRuntime(host: host)
        let ctx = SelectionContext(text: text, canCut: canPaste, canPaste: canPaste, clipboardText: "clip")
        let input = RequirementEvaluator.evaluate(m.actions[0], context: ctx) ?? ActionInput(text: text)
        let outcome = await runtime.perform(m.actions[0], of: m, input: input, context: ctx, modifiers: modifiers, options: options)
        return (outcome, host)
    }

    func testShellPasteResult() async throws {
        let (out, host) = try await run("#glint\nname: U\nshell script: tr a-z A-Z\nafter: paste-result", text: "abc")
        XCTAssertEqual(out, .result("ABC"))
        XCTAssertEqual(host.pasted, ["ABC"])
    }

    func testShellEnvAndShiftCopies() async throws {
        let (_, host) = try await run("#glint\nname: E\nshell script: 'printf \"%s-%s\" \"$POPCLIP_TEXT\" \"$GLINT_OPTION_SEP\"'\nafter: paste-result",
                                      text: "hey", modifiers: .shift, options: ["sep": "x"])
        XCTAssertEqual(host.copied, ["hey-x"])
        XCTAssertTrue(host.pasted.isEmpty)
    }

    func testShellFailureShowsX() async throws {
        let (out, host) = try await run("#glint\nname: F\nshell script: exit 1", text: "a")
        if case .failure = out {} else { XCTFail("expected failure") }
        XCTAssertEqual(host.statuses, [false])
    }

    func testJavaScriptInlineAndAPI() async throws {
        let (out, host) = try await run("""
        // #glint
        // name: J
        // after: copy-result
        popclip.showText("hi " + popclip.options.who);
        return popclip.input.text + "!"
        """, text: "yo", options: ["who": "bob"])
        XCTAssertEqual(out, .result("yo!"))
        XCTAssertEqual(host.shown, ["hi bob"])
        XCTAssertEqual(host.copied, ["yo!"])
    }

    func testJavaScriptPromise() async throws {
        let (out, _) = try await run("""
        // #glint
        // name: P
        return new Promise(function(r) { setTimeout(function() { r("later"); }, 10); })
        """, text: "x")
        XCTAssertEqual(out, .result("later"))
    }

    func testJavaScriptModuleAction() async throws {
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: Cases
        // module: true
        // language: javascript
        exports.actions = [
          { title: "Upper", code: (input) => input.text.toUpperCase() },
          { title: "Lower", code: (input, options, context) => input.text.toLowerCase() + context.appName },
        ];
        """)
        let host = MockHost()
        let ctx = SelectionContext(text: "MiX", appName: "Notes")
        let out = await ExtensionRuntime(host: host).perform(m.actions[1], of: m, input: ActionInput(text: "MiX"), context: ctx,
                                                             modifiers: [], options: [:])
        XCTAssertEqual(out, .result("mixNotes"))
    }

    func testURLActionModifiers() async throws {
        let (_, host) = try await run("#glint\nname: S\nurl: https://s.com/?q=***", text: "a b")
        XCTAssertEqual(host.opened.first?.0.absoluteString, "https://s.com/?q=a%20b")
        let (_, host2) = try await run("#glint\nname: S\nurl: https://s.com/?q=***", text: "a", modifiers: .command)
        XCTAssertEqual(host2.opened.first?.1, true)
    }

    func testAppleScript() async throws {
        let (out, _) = try await run("-- #glint\n-- name: AS\nreturn \"{glint text}\" & \"!\"", text: "q\"x")
        XCTAssertEqual(out, .result("q\"x!"))
    }

    func testKeyCombo() async throws {
        let (_, host) = try await run("#glint\nname: B\nkey combo: command b\nrequirements: [formatting]", text: "x")
        XCTAssertEqual(host.keys, [KeyCombo(keyCode: 11, modifiers: .command)])
    }

    func testInstallSnippetRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ExtensionLoader.installSnippet("#glint\nname: Saved\nidentifier: com.me.saved\nurl: https://x/***", into: dir)
        let all = ExtensionLoader.loadAll(in: dir)
        XCTAssertEqual(all.extensions.map(\.identifier), ["com.me.saved"])
        XCTAssertTrue(all.errors.isEmpty)
    }
}
