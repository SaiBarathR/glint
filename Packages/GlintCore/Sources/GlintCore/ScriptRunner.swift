import Foundation

public enum ScriptRunner {
    public struct ShellResult {
        public var status: Int32
        public var stdout: String
        public var stderr: String
    }

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
        if let interpreter, !interpreter.isEmpty {
            let parts = interpreter.split(separator: " ").map(String.init)
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

        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); group.enter()
        DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        do { try process.run() } catch {
            return ShellResult(status: -1, stdout: "", stderr: "Couldn't start \(process.executableURL?.path ?? "script"): \(error.localizedDescription)")
        }
        if let stdin, let data = stdin.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        try? inPipe.fileHandleForWriting.close()

        let deadline = DispatchTime.now() + timeout
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        if process.isRunning, finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 1)
            return ShellResult(status: -2, stdout: String(decoding: outData, as: UTF8.self), stderr: "Timed out after \(Int(timeout))s")
        }
        group.wait()
        return ShellResult(status: process.terminationStatus, stdout: String(decoding: outData, as: UTF8.self),
                           stderr: String(decoding: errData, as: UTF8.self))
    }

    /// Runs AppleScript source or a script file. Returns the string result or an error message.
    public static func runAppleScript(source: String?, file: URL?) -> Result<String?, ScriptError> {
        let work = { () -> Result<String?, ScriptError> in
            var errorInfo: NSDictionary?
            let script: NSAppleScript?
            if let file { script = NSAppleScript(contentsOf: file, error: &errorInfo) }
            else { script = NSAppleScript(source: source ?? "") }
            guard let script else {
                return .failure(ScriptError(message: (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "Couldn't load script"))
            }
            let output = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                return .failure(ScriptError(message: (errorInfo[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"))
            }
            return .success(output.stringValue)
        }
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
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
