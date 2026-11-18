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

final class ReviewRoundThreeTests: XCTestCase {
    func testBudgetKeepsTextAndDropsDuplicatesFirst() {
        let text = String(repeating: "a", count: 60_000)
        let m = ExtensionManifest(identifier: "t", name: "T", actions: [])
        for _ in 0..<10 {
            let env = ExtensionRuntime.environment(manifest: m,
                                                   input: ActionInput(text: text, regexGroups: [text, text],
                                                                      html: String(repeating: "h", count: 50_000)),
                                                   context: SelectionContext(text: text), modifiers: [], options: [:])
            XCTAssertEqual(env["GLINT_TEXT"]?.count, 60_000)
            XCTAssertEqual(env["GLINT_TEXT_TRUNCATED"], "0")
            XCTAssertEqual(env["GLINT_HTML"], "")
        }
    }

    func testDynamicActionsInheritModuleAfter() throws {
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: Dyn
        // language: javascript
        // module: true
        exports.after = 'paste-result';
        exports.stayVisible = true;
        exports.actions = function(input) { return [{ title: 'A', code: function(i) { return 'R:' + i.text; } }]; };
        """)
        let ctx = SelectionContext(text: "hello", canPaste: true)
        let dyn = ExtensionRuntime(host: nil).populateDynamic(m, input: ActionInput(text: "hello"), context: ctx, modifiers: [], options: [:])
        XCTAssertEqual(dyn.first?.after, .pasteResult)
        XCTAssertEqual(dyn.first?.stayVisible, true)
    }

    func testHiddenStagingFoldersAreIgnored() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staging = dir.appendingPathComponent(".staging-123")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try "name: Foo\nurl: https://x/***".write(to: staging.appendingPathComponent("Config.yaml"), atomically: true, encoding: .utf8)
        XCTAssertTrue(ExtensionLoader.loadAll(in: dir).extensions.isEmpty)
    }

    func testTimersStopAtTheDeadline() async throws {
        final class Counter: MockHost { var n = 0; override func copyText(_ text: String) { n += 1 } }
        let host = Counter()
        let env = JavaScriptRunner.Environment(input: ActionInput(text: "a"), context: SelectionContext(text: "a"),
                                               modifiers: [], options: [:], extensionID: "t", bundleURL: nil)
        _ = await JavaScriptRunner.run(.inline("function tick() { glint.copyText('x'); setTimeout(tick, 100); } tick();"),
                                       env: env, host: host, timeout: 1)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let afterDeadline = host.n
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(host.n, afterDeadline, "timer kept firing after the deadline")
        XCTAssertLessThan(afterDeadline, 15)
    }
}

final class ReviewRoundFourTests: XCTestCase {
    func testDynamicActionResolvedByTitle() async throws {
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: Dyn
        // language: javascript
        // module: true
        exports.actions = function(input, options, context) {
          var a = { title: 'A', code: function() { return 'ran A'; } };
          var b = { title: 'B', code: function() { return 'ran B'; } };
          return glint.modifiers.shift ? [b, a] : [a, b];
        };
        """)
        let ctx = SelectionContext(text: "x")
        let runtime = ExtensionRuntime(host: nil)
        let built = runtime.populateDynamic(m, input: ActionInput(text: "x"), context: ctx, modifiers: [], options: [:])
        XCTAssertEqual(built.map(\.title), ["A", "B"])
        // Clicked "A" (index 0) while holding shift, which reorders the list at run time.
        let out = await runtime.perform(built[0], of: m, input: ActionInput(text: "x"), context: ctx, modifiers: .shift,
                                        options: [:], dynamicIndex: 0)
        XCTAssertEqual(out, .result("ran A"))
    }

    func testFetchContinuationAfterTimeoutDoesNotReachHost() async throws {
        // A local server that answers after 2 s.
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", """
        import http.server, time
        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                time.sleep(2); self.send_response(200); self.end_headers(); self.wfile.write(b'late')
            def log_message(self, *a): pass
        http.server.HTTPServer(('127.0.0.1', 47815), H).serve_forever()
        """]
        try server.run()
        defer { server.terminate() }
        try await Task.sleep(nanoseconds: 700_000_000)
        let host = MockHost()
        let env = JavaScriptRunner.Environment(input: ActionInput(text: "a"), context: SelectionContext(text: "a"),
                                               modifiers: [], options: [:], extensionID: "t", bundleURL: nil)
        let out = await JavaScriptRunner.run(.inline(
            "return fetch('http://127.0.0.1:47815/').then(function(r) { return r.text(); }).then(function(t) { glint.pasteText(t); return t; });"),
                                             env: env, host: host, timeout: 1)
        if case .failure = out {} else { XCTFail("expected timeout, got \(out)") }
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertTrue(host.pasted.isEmpty, "late fetch continuation pasted \(host.pasted)")
    }

    func testBrowserURLIsCapped() {
        let m = ExtensionManifest(identifier: "t", name: "T", actions: [])
        let env = ExtensionRuntime.environment(manifest: m, input: ActionInput(text: "a"),
                                               context: SelectionContext(text: "a", sourceURL: "data:" + String(repeating: "x", count: 600_000)),
                                               modifiers: [], options: [:])
        XCTAssertEqual(env["GLINT_BROWSER_URL"], "")
    }

    func testDotIdentifierInstallsVisibly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ExtensionLoader.installSnippet("#glint\nname: Dot\nidentifier: .foo\nurl: https://x/***", into: dir)
        XCTAssertEqual(ExtensionLoader.loadAll(in: dir).extensions.map(\.name), ["Dot"])
    }
}

final class ReviewRoundFiveTests: XCTestCase {
    func testSameTitledDynamicActionsKeepTheirIndex() async throws {
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: Two
        // language: javascript
        // module: true
        exports.actions = function() {
          return [{ title: 'Open', code: function() { return 'FIRST'; } }, { title: 'Open', code: function() { return 'SECOND'; } }];
        };
        """)
        let ctx = SelectionContext(text: "x")
        let runtime = ExtensionRuntime(host: nil)
        let built = runtime.populateDynamic(m, input: ActionInput(text: "x"), context: ctx, modifiers: [], options: [:])
        let out = await runtime.perform(built[1], of: m, input: ActionInput(text: "x"), context: ctx, modifiers: [],
                                        options: [:], dynamicIndex: 1)
        XCTAssertEqual(out, .result("SECOND"))
    }

    func testJSModuleRestorePasteboard() throws {
        let m = try ExtensionLoader.parseSnippet("""
        // #glint
        // name: R
        // language: javascript
        // module: true
        exports.restorePasteboard = true;
        exports.actions = [{ title: 'A', code: function() { return 'a'; } }, { title: 'B', restorePasteboard: false, code: function() {} }];
        """)
        XCTAssertEqual(m.actions.map(\.restoreClipboard), [true, false])
    }
}

final class ReviewRoundTwelveTests: XCTestCase {
    func testUnaryMinusBindsLooserThanPower() throws {
        XCTAssertEqual(try Calculator.evaluate("-2^2"), -4)
        XCTAssertEqual(try Calculator.evaluate("2^-1"), 0.5)
        XCTAssertEqual(try Calculator.evaluate("(-2)^2"), 4)
        XCTAssertEqual(try Calculator.evaluate("3 - -2"), 5)
    }

    func testDatesAndPhonesAreNotMath() {
        XCTAssertNil(ContentDetector.detect(in: "2026-11-18").mathResult)
        XCTAssertNil(ContentDetector.detect(in: "10/12/2026").mathResult)
        XCTAssertNil(ContentDetector.detect(in: "18.11.2026").mathResult)
        XCTAssertNil(ContentDetector.detect(in: "555-1234").mathResult)
        XCTAssertEqual(ContentDetector.detect(in: "100 - 25").mathResult, "75")
        XCTAssertEqual(ContentDetector.detect(in: "10/4").mathResult, "2.5")
    }
}

final class ReviewRoundThirteenTests: XCTestCase {
    func testSubtractionAndDecimalsStillCalculate() {
        for (expr, result) in [("5000-2500", "2500"), ("3600-1800", "1800"), ("45000 - 12500", "32500"),
                               ("100-20-30", "50"), ("(20000-15000)*2", "10000"), ("12.5/100", "0.125"),
                               ("19.99-10", "9.99"), ("99.5 - 10", "89.5"), ("2024-1999", "25")] {
            XCTAssertEqual(ContentDetector.detect(in: expr).mathResult, result, expr)
        }
        for notMath in ["555-1234", "+91 98765 43210", "(555) 123-4567", "555-123-4567", "2026-11-18", "10/12/2026"] {
            XCTAssertNil(ContentDetector.detect(in: notMath).mathResult, notMath)
        }
    }
}

final class ReviewRoundFourteenTests: XCTestCase {
    func testCalculatorEdgeCases() {
        XCTAssertNil(ContentDetector.detect(in: "0x20 - 0x10").mathResult)
        XCTAssertNil(ContentDetector.detect(in: "0x1000 * 4").mathResult)
        XCTAssertNil(ContentDetector.detect(in: "(2019)").mathResult)
        XCTAssertNil(ContentDetector.detect(in: "(3)").mathResult)
        XCTAssertEqual(ContentDetector.detect(in: "-5 * 0").mathResult, "0")
        XCTAssertEqual(ContentDetector.detect(in: "sqrt(16)").mathResult, "4")
        XCTAssertEqual(ContentDetector.detect(in: "(2+3)*4").mathResult, "20")
    }
}

final class ReviewRoundFifteenTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(ContentDetector.detect(in: "0.3-0.2-0.1").mathResult, "0")
        XCTAssertEqual(ContentDetector.detect(in: "1-0.9-0.1").mathResult, "0")
        XCTAssertEqual(ContentDetector.detect(in: "2^64").mathResult, "1.84467440737096e+19")
        XCTAssertEqual(ContentDetector.detect(in: "0.1+0.2").mathResult, "0.3")
        XCTAssertEqual(ContentDetector.detect(in: "10/3").mathResult, "3.3333333333")
        XCTAssertEqual(ContentDetector.detect(in: "999999*1000").mathResult, "999999000")
    }
}
