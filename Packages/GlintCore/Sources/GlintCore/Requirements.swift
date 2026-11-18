import Foundation

/// The input an action receives after its requirements and regex were applied.
public struct ActionInput: Equatable {
    public var text: String
    /// The part of `text` matched by the action's regex (or the whole text).
    public var matchedText: String
    /// Capture groups of the regex match.
    public var regexGroups: [String]
    public var urls: [String]
    public var emails: [String]
    public var paths: [String]
    public var html: String?

    public init(text: String, matchedText: String? = nil, regexGroups: [String] = [], urls: [String] = [],
                emails: [String] = [], paths: [String] = [], html: String? = nil) {
        self.text = text
        self.matchedText = matchedText ?? text
        self.regexGroups = regexGroups
        self.urls = urls; self.emails = emails; self.paths = paths; self.html = html
    }
}

public enum RequirementEvaluator {
    /// Returns the input for the action, or nil when the action should not appear.
    public static func evaluate(_ action: ActionSpec, context: SelectionContext,
                                detected: DetectedContent? = nil) -> ActionInput? {
        if let bundle = context.appBundleID {
            if !action.requiredApps.isEmpty, !action.requiredApps.contains(bundle) { return nil }
            if action.excludedApps.contains(bundle) { return nil }
        } else if !action.requiredApps.isEmpty {
            return nil
        }
        let content = detected ?? ContentDetector.detect(in: context.text)
        let hasText = context.hasText
        for raw in action.requirements {
            var req = normalizeKey(raw)
            let negated = raw.trimmingCharacters(in: .whitespaces).hasPrefix("!")
            if negated { req = normalizeKey(String(raw.drop { $0 == "!" || $0 == " " })) }
            let satisfied: Bool
            switch req {
            case "text": satisfied = hasText
            case "copy": satisfied = hasText && context.canCopy
            case "cut": satisfied = hasText && context.canCut
            case "paste": satisfied = context.canPaste && (context.clipboardText?.isEmpty == false)
            case "formatting": satisfied = context.canFormat
            case "url": satisfied = content.urls.count == 1
            case "urls": satisfied = !content.urls.isEmpty
            case "email": satisfied = content.emails.count == 1
            case "emails": satisfied = !content.emails.isEmpty
            case "path": satisfied = content.paths.count >= 1
            case "html": satisfied = context.html != nil
            case "number", "math": satisfied = content.mathResult != nil
            case "editable": satisfied = context.canPaste || context.canCut
            case "none", "": satisfied = true
            default: satisfied = true // Unknown requirements are ignored rather than hiding the action.
            }
            if satisfied == negated { return nil }
        }

        var input = ActionInput(text: action.trimInput ? context.text.trimmingCharacters(in: .whitespacesAndNewlines) : context.text,
                                urls: content.urls, emails: content.emails, paths: content.paths, html: context.html)
        if input.text.isEmpty { input.text = context.text }
        input.matchedText = input.text
        if let pattern = action.regex {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            let ns = context.text as NSString
            guard let match = regex.firstMatch(in: context.text, range: NSRange(location: 0, length: ns.length)) else { return nil }
            input.matchedText = ns.substring(with: match.range)
            input.regexGroups = (0..<match.numberOfRanges).map { i in
                let r = match.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
        // For url requirements, the action works on the detected URL.
        if action.requirements.contains(where: { normalizeKey($0) == "url" }), let url = content.urls.first, action.regex == nil {
            input.matchedText = url
        }
        if action.requirements.contains(where: { normalizeKey($0) == "email" }), let email = content.emails.first, action.regex == nil {
            input.matchedText = email
        }
        return input
    }
}
