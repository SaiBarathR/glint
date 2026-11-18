import Foundation

public struct DetectedContent: Equatable {
    public var urls: [String] = []
    public var emails: [String] = []
    public var paths: [String] = []
    public var phoneNumbers: [String] = []
    /// Non-nil when the whole selection is a math expression.
    public var mathResult: String?

    public var isSingleURL: Bool { urls.count == 1 }
}

public enum ContentDetector {
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue
                                                          | NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    private static let bareDomain = try! NSRegularExpression(
        pattern: #"(?<![@\w.-])((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:com|org|net|io|dev|app|co|ai|edu|gov|me|info|xyz|uk|de|in|jp|fr|tv|ly|gg|sh|so|to|us|ca|au|nz|eu|ch|nl|se|no|es|it|be|at|dk|fi|pl|ru|br|cn|kr|news|blog|page|site|tech|cloud)(?:/[^\s]*)?)(?![\w.-])"#,
        options: [.caseInsensitive])

    public static func detect(in text: String) -> DetectedContent {
        var result = DetectedContent()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }
        let ns = trimmed as NSString
        let full = NSRange(location: 0, length: ns.length)

        var seen = Set<String>()
        linkDetector?.enumerateMatches(in: trimmed, options: [], range: full) { match, _, _ in
            guard let match else { return }
            if match.resultType == .phoneNumber, let number = match.phoneNumber {
                result.phoneNumbers.append(number)
                return
            }
            guard let url = match.url else { return }
            if url.scheme == "mailto" {
                let email = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                if !result.emails.contains(email) { result.emails.append(email) }
            } else if url.scheme == "file" {
                // File URLs are reported as paths below.
            } else {
                let s = url.absoluteString
                if seen.insert(s).inserted { result.urls.append(s) }
            }
        }
        // Bare domains like "example.com/path" that NSDataDetector can miss.
        if result.urls.isEmpty {
            for match in bareDomain.matches(in: trimmed, range: full) {
                let s = "https://" + ns.substring(with: match.range(at: 1))
                if seen.insert(s).inserted { result.urls.append(s) }
            }
        }

        // File paths: whole selection (or each line) beginning with / or ~ that exists on disk.
        for line in trimmed.split(whereSeparator: \.isNewline) {
            let candidate = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard candidate.hasPrefix("/") || candidate.hasPrefix("~") || candidate.hasPrefix("file://") else { continue }
            var path = candidate
            if path.hasPrefix("file://"), let url = URL(string: path) { path = url.path }
            path = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) { result.paths.append(path) }
        }

        // Phone numbers like 555-1234 aren't subtraction.
        if trimmed.count <= 200, result.phoneNumbers.isEmpty, Calculator.looksLikeExpression(trimmed), let value = try? Calculator.evaluate(trimmed) {
            result.mathResult = Calculator.format(value)
        }
        return result
    }
}
