import Foundation

public enum Templates {
    /// Characters allowed unescaped in a URL query component.
    static let queryAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#/:;,@$!'()*")
        return set
    }()

    public static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? s
    }

    /// Fills a URL template: `***`, `{glint text}` / `{popclip text}` → encoded text,
    /// `{glint option NAME}` / `{popclip option NAME}` → encoded option values.
    public static func fillURL(_ template: String, text: String, options: [String: String],
                               extras: [String: String] = [:]) -> String {
        var out = template.replacingOccurrences(of: "***", with: urlEncode(text))
        out = replaceTokens(in: out, text: text, options: options, extras: extras, encode: urlEncode)
        return out
    }

    /// Fills an AppleScript source: placeholders become AppleScript-string-escaped values,
    /// so `"{glint text}"` is a safe string literal.
    public static func fillAppleScript(_ source: String, text: String, options: [String: String],
                                       extras: [String: String] = [:]) -> String {
        replaceTokens(in: source, text: text, options: options, extras: extras, encode: appleScriptEscape)
    }

    /// Extra placeholder values (`{glint url}`, `{glint urls}`, `{glint html}`, `{glint app name}`,
    /// `{glint bundle identifier}`) built from the input and context.
    public static func extras(input: ActionInput, context: SelectionContext) -> [String: String] {
        ["url": input.urls.first ?? "", "urls": input.urls.joined(separator: "\n"), "html": input.html ?? "",
         "appname": context.appName ?? "", "bundleidentifier": context.appBundleID ?? ""]
    }

    public static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func replaceTokens(in source: String, text: String, options: [String: String], extras: [String: String] = [:],
                              encode: (String) -> String) -> String {
        let pattern = #"\{(?:glint|popclip)\s+(text|option\s+([A-Za-z0-9_\-]+)|urls?|html|app\s+name|bundle\s+identifier)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return source }
        let ns = source as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let token = ns.substring(with: match.range(at: 1)).lowercased()
            if token == "text" {
                result += encode(text)
            } else if token.hasPrefix("option"), match.range(at: 2).location != NSNotFound {
                let name = ns.substring(with: match.range(at: 2))
                let value = options[name] ?? options.first { normalizeKey($0.key) == normalizeKey(name) }?.value ?? ""
                result += encode(value)
            } else {
                result += encode(extras[normalizeKey(token)] ?? (token.hasPrefix("url") ? "" : text))
            }
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
