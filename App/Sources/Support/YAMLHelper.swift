import Foundation
import GlintCore

/// Parses untrusted extension YAML in a child process (this same executable with `--parse-yaml`), so a document
/// that makes the YAML library hang or crash can't take Glint down. The child gets a 3-second deadline.
enum YAMLHelper {
    static let flag = "--parse-yaml"

    /// Child side: read YAML from stdin, print `{"ok": <dict>}` or `{"error": "..."}` as JSON, exit.
    static func runChild() -> Never {
        // Own deadline: if the parent is gone (force-quit mid-parse), never spin forever.
        alarm(5)
        let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        var reply: [String: Any]
        do {
            reply = ["ok": jsonSafe(try ExtensionLoader.parseYAMLInProcess(input))]
        } catch ManifestError.invalidYAML(let message) {
            reply = ["error": message] // the parent wraps it again
        } catch ManifestError.notADictionary {
            reply = ["ok": NSNull()] // the parent reports "must be a dictionary"
        } catch {
            reply = ["error": error.localizedDescription]
        }
        // JSONSerialization raises (uncatchable) on invalid objects such as NaN; check first.
        if !JSONSerialization.isValidJSONObject(reply) { reply = ["error": "The extension config contains unsupported values."] }
        let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data(#"{"error":"Unreadable config"}"#.utf8)
        FileHandle.standardOutput.write(data)
        exit(0)
    }

    /// Parent side.
    static func parse(_ text: String) throws -> [String: Any] {
        guard let exe = Bundle.main.executableURL else { return try ExtensionLoader.parseYAMLInProcess(text) }
        let p = Process()
        p.executableURL = exe
        p.arguments = [flag]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        var out = Data()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global().async { out = outPipe.fileHandleForReading.readDataToEndOfFile(); reader.leave() }
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do {
            try p.run()
        } catch {
            // Let the reader finish (it waits for EOF on a pipe we still hold) and report something useful.
            try? outPipe.fileHandleForWriting.close()
            try? inPipe.fileHandleForReading.close()
            _ = reader.wait(timeout: .now() + 1)
            throw ManifestError.unreadable("Glint couldn't start its config reader. If Glint was moved while running, quit and reopen it.")
        }
        let input = Data(text.utf8)
        DispatchQueue.global().async {
            try? inPipe.fileHandleForWriting.write(contentsOf: input)
            try? inPipe.fileHandleForWriting.close()
        }
        if done.wait(timeout: .now() + 3) == .timedOut {
            kill(p.processIdentifier, SIGKILL)
            _ = done.wait(timeout: .now() + 1)
            _ = reader.wait(timeout: .now() + 1)
            throw ManifestError.invalidYAML("The extension config took too long to read.")
        }
        _ = reader.wait(timeout: .now() + 1)
        guard p.terminationStatus == 0,
              let reply = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else {
            throw ManifestError.invalidYAML("The extension config couldn't be read.")
        }
        if let message = reply["error"] as? String { throw ManifestError.invalidYAML(message) }
        guard let dict = reply["ok"] as? [String: Any] else { throw ManifestError.notADictionary }
        return dict
    }

    /// Makes parsed YAML values JSON-serialisable (dates and binary become strings).
    static func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let d as [String: Any]: return d.mapValues(jsonSafe)
        case let d as [AnyHashable: Any]:
            var out: [String: Any] = [:]
            for (k, v) in d { out["\(k)"] = jsonSafe(v) }
            return out
        case let a as [Any]: return a.map(jsonSafe)
        case let d as Double where !d.isFinite: return "\(d)"
        case let date as Date: return ISO8601DateFormatter().string(from: date)
        case let data as Data: return data.base64EncodedString()
        case is NSNull, is String, is NSNumber: return value
        default: return "\(value)"
        }
    }
}
