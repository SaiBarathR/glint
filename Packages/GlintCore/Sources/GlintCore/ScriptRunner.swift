import Foundation

public enum ScriptRunner {
    public struct ShellResult {
        public var status: Int32
        public var stdout: String
        public var stderr: String
    }

    /// Writing to a pipe whose reader exited must fail with EPIPE instead of killing the app.
    static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    static let extraPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Runs a shell script (inline source or file) with the given environment, feeding `stdin`.
    public static func runShell(source: String?, file: URL?, interpreter: String?, environment: [String: String],
                                workingDirectory: URL?, stdin: String?, timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runShellSync(source: source, file: file, interpreter: interpreter,
                                                    environment: environment, workingDirectory: workingDirectory,
                                                    stdin: stdin, timeout: timeout))
            }
        }
    }

    public static func runShellSync(source: String?, file: URL?, interpreter: String?, environment: [String: String],
                                    workingDirectory: URL?, stdin: String?, timeout: TimeInterval = 30) -> ShellResult {
        _ = ignoreSIGPIPE
        let fm = FileManager.default
        var tempFile: URL?
        defer { if let tempFile { try? fm.removeItem(at: tempFile) } }

        var scriptPath: String
        if let file {
            scriptPath = file.path
        } else {
            let tmp = fm.temporaryDirectory.appendingPathComponent("glint-\(UUID().uuidString)")
            do { try (source ?? "").write(to: tmp, atomically: true, encoding: .utf8) } catch {
                return ShellResult(status: -1, stdout: "", stderr: "\(error)")
            }
            tempFile = tmp
            scriptPath = tmp.path
        }

        let process = Process()
        var args: [String] = []
        if let interpreter, case let parts = interpreter.split(whereSeparator: \.isWhitespace).map(String.init), !parts.isEmpty {
            if parts[0].hasPrefix("/") {
                process.executableURL = URL(fileURLWithPath: parts[0])
                args = Array(parts.dropFirst())
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                args = parts
            }
            args.append(scriptPath)
        } else if file != nil, fm.isExecutableFile(atPath: scriptPath) {
            process.executableURL = URL(fileURLWithPath: scriptPath)
        } else {
            // Respect a shebang line; otherwise run with zsh.
            let firstLine = (source ?? (try? String(contentsOfFile: scriptPath, encoding: .utf8)) ?? "")
                .split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            if firstLine.hasPrefix("#!") {
                let parts = firstLine.dropFirst(2).trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
                process.executableURL = URL(fileURLWithPath: parts.first ?? "/bin/zsh")
                args = Array(parts.dropFirst())
            } else {
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            }
            args.append(scriptPath)
        }
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = extraPath + ":" + (env["PATH"] ?? "")
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        for (k, v) in environment { env[k] = v }
        process.environment = env
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        // Read both pipes incrementally. A script may leave a background child holding the pipes open,
        // so EOF can't be relied on: after the script exits we wait only briefly for remaining output.
        let lock = NSLock()
        var outData = Data(), errData = Data()
        let eof = DispatchGroup()
        for (pipe, isOut) in [(outPipe, true), (errPipe, false)] {
            eof.enter()
            var finished = false
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                lock.lock(); defer { lock.unlock() }
                if chunk.isEmpty {
                    if !finished { finished = true; handle.readabilityHandler = nil; eof.leave() }
                } else if isOut { outData.append(chunk) } else { errData.append(chunk) }
            }
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ShellResult(status: -1, stdout: "", stderr: "Couldn't start \(process.executableURL?.path ?? "script"): \(error.localizedDescription)")
        }
        let deadline = DispatchTime.now() + timeout

        // Feed stdin off this thread: scripts that never read it must not block us (or kill us with SIGPIPE).
        let input = stdin.flatMap { $0.data(using: .utf8) } ?? Data()
        DispatchQueue.global(qos: .utility).async {
            let writer = inPipe.fileHandleForWriting
            if !input.isEmpty { try? writer.write(contentsOf: input) }
            try? writer.close()
        }

        var timedOut = false
        if exited.wait(timeout: deadline) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }
        _ = eof.wait(timeout: .now() + (timedOut ? 0.2 : 1.0))
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        let out = String(decoding: outData, as: UTF8.self), err = String(decoding: errData, as: UTF8.self)
        lock.unlock()
        if timedOut { return ShellResult(status: -2, stdout: out, stderr: "Timed out after \(Int(timeout))s") }
        return ShellResult(status: process.isRunning ? -2 : process.terminationStatus, stdout: out, stderr: err)
    }

    /// Runs AppleScript source or a script file in a separate `osascript` process, so a slow script,
    /// a dialog or a permission prompt can't block the app. Returns the result as text.
    public static func runAppleScript(source: String?, file: URL?, timeout: TimeInterval = 120) async -> Result<String?, ScriptError> {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                var scriptFile = file
                var temp: URL?
                if scriptFile == nil {
                    let t = fm.temporaryDirectory.appendingPathComponent("glint-\(UUID().uuidString).applescript")
                    do { try (source ?? "").write(to: t, atomically: true, encoding: .utf8) } catch {
                        cont.resume(returning: .failure(ScriptError(message: error.localizedDescription))); return
                    }
                    temp = t
                    scriptFile = t
                }
                defer { if let temp { try? fm.removeItem(at: temp) } }
                let r = runShellSync(source: nil, file: scriptFile, interpreter: "/usr/bin/osascript", environment: [:],
                                     workingDirectory: nil, stdin: nil, timeout: timeout)
                if r.status == 0 {
                    let out = r.stdout.hasSuffix("\n") ? String(r.stdout.dropLast()) : r.stdout
                    cont.resume(returning: .success(out.isEmpty ? nil : out))
                } else {
                    var msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    // "…/glint-UUID.applescript:12:20: execution error: Message (-1728)" → "Message (-1728)"
                    if let range = msg.range(of: "error: ") { msg = String(msg[range.upperBound...]) }
                    cont.resume(returning: .failure(ScriptError(message: msg.isEmpty ? "AppleScript failed" : msg)))
                }
            }
        }
    }

    /// Runs a Shortcuts.app shortcut with `input` and returns its text output.
    public static func runShortcut(name: String, input: String) async -> Result<String?, ScriptError> {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("glint-shortcut-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let inFile = dir.appendingPathComponent("input.txt")
        let outFile = dir.appendingPathComponent("output.txt")
        try? input.write(to: inFile, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name, "--input-path", inFile.path, "--output-path", outFile.path,
                             "--output-type", "public.plain-text"]
        let err = Pipe()
        process.standardError = err
        return await withCheckedContinuation { cont in
            process.terminationHandler = { p in
                if p.terminationStatus != 0 {
                    let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    cont.resume(returning: .failure(ScriptError(message: msg.isEmpty ? "Shortcut failed" : msg)))
                } else {
                    cont.resume(returning: .success(try? String(contentsOf: outFile, encoding: .utf8)))
                }
            }
            do { try process.run() } catch {
                cont.resume(returning: .failure(ScriptError(message: error.localizedDescription)))
            }
        }
    }
}

public struct ScriptError: Error, Equatable, LocalizedError {
    public var message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}
