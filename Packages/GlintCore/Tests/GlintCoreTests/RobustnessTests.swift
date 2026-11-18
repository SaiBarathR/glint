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
