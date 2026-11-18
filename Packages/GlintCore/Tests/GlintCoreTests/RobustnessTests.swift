import XCTest
@testable import GlintCore

final class RobustnessTests: XCTestCase {
    func testLargeStdinToScriptThatIgnoresItDoesNotCrashOrBlock() {
        let big = String(repeating: "x", count: 300_000)
        let start = Date()
        let r = ScriptRunner.runShellSync(source: "echo hi", file: nil, interpreter: nil, environment: [:],
                                          workingDirectory: nil, stdin: big, timeout: 5)
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.stdout, "hi\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testTimeoutAppliesWhileStdinIsPending() {
        let big = String(repeating: "x", count: 300_000)
        let start = Date()
        let r = ScriptRunner.runShellSync(source: "sleep 20", file: nil, interpreter: nil, environment: [:],
                                          workingDirectory: nil, stdin: big, timeout: 1)
        XCTAssertEqual(r.status, -2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testBackgroundChildDoesNotHoldTheRunnerOpen() {
        let start = Date()
        let r = ScriptRunner.runShellSync(source: "sleep 8 &\necho done", file: nil, interpreter: nil, environment: [:],
                                          workingDirectory: nil, stdin: nil, timeout: 3)
        XCTAssertEqual(r.stdout, "done\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testRuntimeSyntaxErrorRunsScriptOnce() async {
        let host = MockHost()
        let env = JavaScriptRunner.Environment(input: ActionInput(text: "not json"), context: SelectionContext(text: "not json"),
                                               modifiers: [], options: [:], extensionID: "t", bundleURL: nil)
        let out = await JavaScriptRunner.run(.inline("glint.copyText('once'); JSON.parse(glint.input.text);"), env: env, host: host)
        if case .failure = out {} else { XCTFail("expected failure") }
        XCTAssertEqual(host.copied, ["once"])
    }

    func testTopLevelReturnStillWorks() async {
        let env = JavaScriptRunner.Environment(input: ActionInput(text: "a"), context: SelectionContext(text: "a"),
                                               modifiers: [], options: [:], extensionID: "t", bundleURL: nil)
        let out = await JavaScriptRunner.run(.inline("const x = 1;\nreturn 'r' + x"), env: env, host: nil)
        XCTAssertEqual(out, .result("r1"))
    }

    func testInfiniteLoopIsStopped() async {
        let env = JavaScriptRunner.Environment(input: ActionInput(text: "a"), context: SelectionContext(text: "a"),
                                               modifiers: [], options: [:], extensionID: "t", bundleURL: nil)
        let start = Date()
        let out = await JavaScriptRunner.run(.inline("while (true) {}"), env: env, host: nil, timeout: 1)
        if case .failure = out {} else { XCTFail("expected failure, got \(out)") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testDynamicPopulateIsBounded() {
        let env = JavaScriptRunner.Environment(input: ActionInput(text: "a"), context: SelectionContext(text: "a"),
                                               modifiers: [], options: [:], extensionID: "t", bundleURL: nil)
        let start = Date()
        let loop = JavaScriptRunner.populate(moduleSource: "exports.actions = function() { while (true) {} };", env: env)
        XCTAssertTrue(loop.isEmpty)
        let slept = JavaScriptRunner.populate(moduleSource: "exports.actions = function() { util.sleep(5000); return [{title: 'A'}]; };", env: env)
        XCTAssertEqual(slept.first?["title"] as? String, "A")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.5)
    }
}

final class ReviewRoundOneTests: XCTestCase {
    func testDescribingASnippetHasNoNetworkOrTimers() throws {
        // A module whose top-level code tries to reach the network while being parsed.
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: Sneaky
        // language: javascript
        // module: true
        var leaked = false;
        fetch('http://127.0.0.1:9/x').then(function() { leaked = true; });
        setTimeout(function() { leaked = true; }, 0);
        exports.actions = [{ title: 'A', code: function() { return 'a'; } }];
        """)
        XCTAssertEqual(m.actions.map(\.title), ["A"])
    }

    func testWhitespaceInterpreterDoesNotCrash() {
        let r = ScriptRunner.runShellSync(source: "echo ok", file: nil, interpreter: "   ", environment: [:],
                                          workingDirectory: nil, stdin: nil, timeout: 5)
        XCTAssertEqual(r.stdout, "ok\n")
    }

    func testLargeSelectionStillRunsShellActions() async throws {
        let m = try ExtensionLoader.parseSnippet("#glint\nname: Len\nshell script: wc -c | tr -d ' '\nafter: copy-result")
        let text = String(repeating: "漢", count: 90_000)
        let host = MockHost()
        let ctx = SelectionContext(text: text, html: String(repeating: "<b>x</b>", count: 60_000))
        let out = await ExtensionRuntime(host: host).perform(m.actions[0], of: m, input: ActionInput(text: text, html: ctx.html),
                                                             context: ctx, modifiers: [], options: [:])
        XCTAssertEqual(out, .result("270000"))
    }

    func testModuleLevelAppFiltersApplyToActions() throws {
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: Filtered
        // language: javascript
        // module: true
        exports.excludedApps = ['com.apple.Terminal'];
        exports.actions = [{ title: 'A', code: function() {} }];
        """)
        XCTAssertEqual(m.actions[0].excludedApps, ["com.apple.Terminal"])
        XCTAssertNil(RequirementEvaluator.evaluate(m.actions[0], context: SelectionContext(text: "x", appBundleID: "com.apple.Terminal")))
    }

    func testConfigJSBundleIdentifierAndLooseFileSource() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = dir.appendingPathComponent("MyMod.glintext")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try "module.exports = { name: 'Mod', actions: [{ title: 'A', code: function() {} }] };"
            .write(to: bundle.appendingPathComponent("Config.js"), atomically: true, encoding: .utf8)
        try "#glint\nname: Loose\nurl: https://x/***".write(to: dir.appendingPathComponent("loose.yaml"), atomically: true, encoding: .utf8)
        let all = ExtensionLoader.loadAll(in: dir)
        let mod = all.extensions.first { $0.name == "Mod" }
        XCTAssertEqual(mod?.identifier, "bundle.mymod")
        let loose = all.extensions.first { $0.name == "Loose" }
        XCTAssertEqual(loose?.sourceURL?.lastPathComponent, "loose.yaml")
    }

    func testHTMLRequirementWithCaptureHTML() {
        var a = ActionSpec(id: "h", title: "H", kind: .native(id: "x"), requirements: ["html"])
        XCTAssertNil(RequirementEvaluator.evaluate(a, context: SelectionContext(text: "x")))
        a.captureHTML = true
        XCTAssertNotNil(RequirementEvaluator.evaluate(a, context: SelectionContext(text: "x")))
    }

    func testAppleScriptErrorMessage() async {
        let r = await ScriptRunner.runAppleScript(source: "error \"boom\"", file: nil)
        if case .failure(let e) = r { XCTAssertTrue(e.message.contains("boom"), e.message) } else { XCTFail() }
    }
}

final class ReviewRoundTwoTests: XCTestCase {
    func testHugeRegexGroupsStayWithinEnvironmentLimit() async throws {
        let m = try ExtensionLoader.parseSnippet("#glint\nname: G\nregex: '(?s)^(.*)$'\nshell script: wc -c | tr -d ' '\nafter: copy-result")
        let text = String(repeating: "漢", count: 100_000)
        let host = MockHost()
        let ctx = SelectionContext(text: text)
        let input = RequirementEvaluator.evaluate(m.actions[0], context: ctx)!
        let out = await ExtensionRuntime(host: host).perform(m.actions[0], of: m, input: input, context: ctx,
                                                             modifiers: [], options: [:])
        XCTAssertEqual(out, .result("300000"))
    }

    func testSleepLoopHitsWallClockDeadline() async {
        let env = JavaScriptRunner.Environment(input: ActionInput(text: "a"), context: SelectionContext(text: "a"),
                                               modifiers: [], options: [:], extensionID: "t", bundleURL: nil)
        let start = Date()
        let out = await JavaScriptRunner.run(.inline("var n = 0; while (true) { sleep(200); n++; }"), env: env, host: nil, timeout: 1)
        if case .failure = out {} else { XCTFail("expected failure, got \(out)") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    final class Sink { var copied: [String] = [] }
    final class SinkHost: MockHost {
        let sink: Sink
        init(_ sink: Sink) { self.sink = sink }
        override func copyText(_ text: String) { sink.copied.append(text) }
    }

    func testLateCallbackStillReachesHost() async throws {
        let sink = Sink()
        let env = JavaScriptRunner.Environment(input: ActionInput(text: "a"), context: SelectionContext(text: "a"),
                                               modifiers: [], options: [:], extensionID: "t", bundleURL: nil)
        do {
            // The only strong reference to this host is the one the running action holds.
            let scoped = SinkHost(sink)
            _ = await JavaScriptRunner.run(.inline("setTimeout(function() { glint.copyText('late'); }, 100);"), env: env, host: scoped)
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sink.copied, ["late"])
    }
}
