import Foundation

/// Normalises config keys so "Shell Script File", "shell_script_file" and "shellScriptFile" all match.
public func normalizeKey(_ key: String) -> String {
    key.lowercased().filter { $0.isLetter || $0.isNumber }
}

/// A config dictionary with normalised keys and typed accessors.
public struct ConfigDict {
    public let raw: [String: Any]
    public init(_ dict: [String: Any]) {
        var out: [String: Any] = [:]
        for (k, v) in dict { out[normalizeKey(k)] = v }
        raw = out
    }
    public subscript(_ keys: String...) -> Any? {
        for k in keys { if let v = raw[normalizeKey(k)] { return v } }
        return nil
    }
    public func string(_ keys: String...) -> String? {
        for k in keys {
            if let v = raw[normalizeKey(k)] {
                if let s = v as? String { return s }
                if let n = v as? NSNumber { return n.stringValue }
            }
        }
        return nil
    }
    public func bool(_ keys: String...) -> Bool? {
        for k in keys {
            if let v = raw[normalizeKey(k)] {
                if let b = v as? Bool { return b }
                if let n = v as? NSNumber { return n.boolValue }
                if let s = v as? String { return ["true", "yes", "1"].contains(s.lowercased()) }
            }
        }
        return nil
    }
    public func strings(_ keys: String...) -> [String]? {
        for k in keys {
            if let v = raw[normalizeKey(k)] {
                if let a = v as? [Any] { return a.compactMap { ($0 as? String) ?? ($0 as? NSNumber)?.stringValue } }
                if let s = v as? String { return [s] }
            }
        }
        return nil
    }
    public func dicts(_ keys: String...) -> [[String: Any]]? {
        for k in keys { if let v = raw[normalizeKey(k)] as? [[String: Any]] { return v } }
        return nil
    }
}

public enum AfterAction: String, Codable, CaseIterable {
    case none
    case copyResult = "copy-result"
    case pasteResult = "paste-result"
    case showResult = "show-result"
    case previewResult = "preview-result"
    case showStatus = "show-status"

    public init(config: String?) {
        guard let config else { self = .none; return }
        let n = normalizeKey(config)
        self = AfterAction.allCases.first { normalizeKey($0.rawValue) == n } ?? .none
    }
}

public enum ScriptKind: String, Codable {
    case shell, appleScript, javaScript
}

public enum ActionKind: Equatable {
    /// Open a URL template; `***` / `{text}` are replaced by the URL-encoded selection.
    case url(template: String, alternateTemplate: String?)
    /// Send a key press (e.g. "command B") to the frontmost app.
    case keyCombo(KeyCombo)
    /// Several key presses in a row.
    case keyCombos([KeyCombo])
    /// Run a macOS Service by name.
    case service(name: String)
    /// Run a Shortcuts.app shortcut by name.
    case shortcut(name: String)
    /// Inline script source.
    case script(kind: ScriptKind, source: String, interpreter: String?)
    /// Script loaded from a file inside the extension bundle.
    case scriptFile(kind: ScriptKind, path: String, interpreter: String?)
    /// A function defined in a JavaScript module (`exports.actions`).
    case jsModuleAction(index: Int)
    /// Implemented natively by the app (built-in actions).
    case native(id: String)
}

public struct OptionSpec: Equatable, Identifiable {
    public enum Kind: String, Equatable { case string, boolean, multiple, password, secret, heading }
    public var id: String
    public var kind: Kind
    public var label: String
    public var description: String?
    public var defaultValue: String?
    public var values: [String]
    public var valueLabels: [String]
    public var inset: Bool
    public var hidden: Bool

    public init(id: String, kind: Kind, label: String, description: String? = nil, defaultValue: String? = nil,
                values: [String] = [], valueLabels: [String] = [], inset: Bool = false, hidden: Bool = false) {
        self.id = id; self.kind = kind; self.label = label; self.description = description
        self.defaultValue = defaultValue; self.values = values; self.valueLabels = valueLabels
        self.inset = inset; self.hidden = hidden
    }

    init?(config c: ConfigDict) {
        guard let id = c.string("identifier", "id", "option identifier") else { return nil }
        let typeName = normalizeKey(c.string("type", "option type") ?? "string")
        let kind: Kind
        switch typeName {
        case "boolean", "bool", "checkbox": kind = .boolean
        case "multiple", "choice", "enum", "select": kind = .multiple
        case "password": kind = .password
        case "secret": kind = .secret
        case "heading": kind = .heading
        default: kind = .string
        }
        var def: String?
        if let v = c["default value", "default"] {
            if let b = v as? Bool { def = b ? "1" : "0" } else if let s = v as? String { def = s }
            else if let n = v as? NSNumber { def = n.stringValue }
        }
        self.init(id: id, kind: kind, label: c.string("label", "option label") ?? id,
                  description: c.string("description", "option description"), defaultValue: def,
                  values: c.strings("values", "option values") ?? [],
                  valueLabels: c.strings("value labels", "option value labels") ?? [],
                  inset: c.bool("inset") ?? false, hidden: c.bool("hidden") ?? false)
    }
}

/// One action (button) on the bar.
public struct ActionSpec: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var icon: String?
    public var kind: ActionKind
    public var requirements: [String]
    public var regex: String?
    public var after: AfterAction
    public var requiredApps: [String]
    public var excludedApps: [String]
    public var stayVisible: Bool
    public var restoreClipboard: Bool
    /// Text sent to the action is trimmed of surrounding whitespace (default true for url/search).
    public var trimInput: Bool
    public var captureHTML: Bool
    public var description: String?

    public init(id: String, title: String, icon: String? = nil, kind: ActionKind, requirements: [String] = ["text"],
                regex: String? = nil, after: AfterAction = .none, requiredApps: [String] = [], excludedApps: [String] = [],
                stayVisible: Bool = false, restoreClipboard: Bool = false, trimInput: Bool = true,
                captureHTML: Bool = false, description: String? = nil) {
        self.id = id; self.title = title; self.icon = icon; self.kind = kind; self.requirements = requirements
        self.regex = regex; self.after = after; self.requiredApps = requiredApps; self.excludedApps = excludedApps
        self.stayVisible = stayVisible; self.restoreClipboard = restoreClipboard; self.trimInput = trimInput
        self.captureHTML = captureHTML; self.description = description
    }
}

/// A parsed extension (one or more actions plus options).
public struct ExtensionManifest: Equatable, Identifiable {
    public var identifier: String
    public var name: String
    public var icon: String?
    public var description: String?
    public var author: String?
    public var homepage: String?
    public var options: [OptionSpec]
    public var actions: [ActionSpec]
    /// JavaScript module source (for `exports.actions` style extensions).
    public var moduleSource: String?
    /// Folder the extension was loaded from (nil for built-ins / snippets not yet installed).
    public var bundleURL: URL?
    /// Original snippet text, kept so snippet extensions can be re-saved and shown.
    public var snippetSource: String?
    public var isBuiltIn: Bool

    public var id: String { identifier }

    public init(identifier: String, name: String, icon: String? = nil, description: String? = nil, author: String? = nil,
                homepage: String? = nil, options: [OptionSpec] = [], actions: [ActionSpec], moduleSource: String? = nil,
                bundleURL: URL? = nil, snippetSource: String? = nil, isBuiltIn: Bool = false) {
        self.identifier = identifier; self.name = name; self.icon = icon; self.description = description
        self.author = author; self.homepage = homepage; self.options = options; self.actions = actions
        self.moduleSource = moduleSource; self.bundleURL = bundleURL; self.snippetSource = snippetSource
        self.isBuiltIn = isBuiltIn
    }
}

public enum ManifestError: LocalizedError, Equatable {
    case notADictionary
    case missingName
    case noActions
    case unreadable(String)
    case invalidYAML(String)

    public var errorDescription: String? {
        switch self {
        case .notADictionary: return "The extension config must be a dictionary of keys and values."
        case .missingName: return "The extension needs a `name`."
        case .noActions: return "The extension doesn't define any action (url, shell script, AppleScript, JavaScript, key combo, service or shortcut)."
        case .unreadable(let s): return "Couldn't read the extension: \(s)"
        case .invalidYAML(let s): return "Invalid YAML: \(s)"
        }
    }
}

public enum ManifestParser {
    /// Builds a manifest from a config dictionary (from YAML, JSON or plist).
    /// - Parameters:
    ///   - bundleURL: folder containing script files referenced by the config.
    ///   - language/code: for "inverted" snippets where the body is the script.
    public static func parse(_ dict: [String: Any], bundleURL: URL? = nil, inlineCode: String? = nil,
                             snippetSource: String? = nil, isBuiltIn: Bool = false) throws -> ExtensionManifest {
        let c = ConfigDict(dict)
        guard let name = c.string("name", "extension name", "title") else { throw ManifestError.missingName }
        let identifier = c.string("identifier", "extension identifier") ?? derivedIdentifier(name: name)
        let icon = c.string("icon", "image file", "extension image file")
        let options = (c.dicts("options") ?? []).compactMap { OptionSpec(config: ConfigDict($0)) }

        var moduleSource: String?
        if let module = c.string("module") {
            if let bundleURL, let src = try? String(contentsOf: bundleURL.appendingPathComponent(module), encoding: .utf8) {
                moduleSource = src
            } else if inlineCode != nil, normalizeKey(module) == "true" || module.isEmpty {
                moduleSource = inlineCode
            }
        }
        if moduleSource == nil, let lang = c.string("language"), normalizeKey(lang) == "javascript",
           c.bool("module") == true, let inlineCode {
            moduleSource = inlineCode
        }

        // Defaults inherited by every action.
        let defaults = ActionDefaults(config: c)
        var actions: [ActionSpec] = []
        if let list = c.dicts("actions") {
            for (index, item) in list.enumerated() {
                if let a = try parseAction(ConfigDict(item), defaults: defaults, extensionName: name,
                                           extensionIcon: icon, index: index, bundleURL: bundleURL, inlineCode: nil) {
                    actions.append(a)
                }
            }
        }
        if actions.isEmpty, moduleSource == nil,
           let single = try parseAction(c, defaults: defaults, extensionName: name, extensionIcon: icon, index: 0,
                                        bundleURL: bundleURL, inlineCode: inlineCode) {
            actions.append(single)
        }
        if actions.isEmpty && moduleSource == nil { throw ManifestError.noActions }

        return ExtensionManifest(identifier: identifier, name: name, icon: icon,
                                 description: c.string("description", "extension description"),
                                 author: c.string("author", "credits"), homepage: c.string("homepage", "app link", "link"),
                                 options: options, actions: actions, moduleSource: moduleSource, bundleURL: bundleURL,
                                 snippetSource: snippetSource, isBuiltIn: isBuiltIn)
    }

    static func derivedIdentifier(name: String) -> String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "snippet." + String(slug).split(separator: "-").joined(separator: "-")
    }

    struct ActionDefaults {
        var requirements: [String]?
        var regex: String?
        var after: String?
        var apps: [String]
        var excludedApps: [String]
        var stayVisible: Bool?
        var restoreClipboard: Bool?
        var captureHTML: Bool?
        var interpreter: String?

        init(config c: ConfigDict) {
            requirements = c.strings("requirements", "required")
            regex = c.string("regex")
            after = c.string("after")
            apps = ActionDefaults.bundleIDs(c["required apps", "apps", "app", "required app bundle identifiers"])
            excludedApps = ActionDefaults.bundleIDs(c["excluded apps", "blocked apps", "excluded app bundle identifiers"])
            stayVisible = c.bool("stay visible")
            restoreClipboard = c.bool("restore pasteboard", "restore clipboard")
            captureHTML = c.bool("capture html")
            interpreter = c.string("interpreter")
        }

        static func bundleIDs(_ v: Any?) -> [String] {
            if let s = v as? String { return [s] }
            if let a = v as? [Any] {
                return a.compactMap { item in
                    if let s = item as? String { return s }
                    if let d = item as? [String: Any] { return ConfigDict(d).string("bundle identifier", "bundle identifiers", "identifier") }
                    return nil
                }
            }
            if let d = v as? [String: Any] {
                let c = ConfigDict(d)
                return c.strings("bundle identifiers", "bundle identifier") ?? []
            }
            return []
        }
    }

    static func parseAction(_ c: ConfigDict, defaults: ActionDefaults, extensionName: String, extensionIcon: String?,
                            index: Int, bundleURL: URL?, inlineCode: String?) throws -> ActionSpec? {
        let interpreter = c.string("interpreter") ?? defaults.interpreter
        var kind: ActionKind?
        if let url = c.string("url") {
            kind = .url(template: url, alternateTemplate: c.string("alternate url", "alt url"))
        } else if let source = c.string("shell script") {
            kind = .script(kind: .shell, source: source, interpreter: interpreter)
        } else if let file = c.string("shell script file", "script file") {
            kind = .scriptFile(kind: .shell, path: file, interpreter: interpreter)
        } else if let source = c.string("applescript", "apple script") {
            kind = .script(kind: .appleScript, source: source, interpreter: nil)
        } else if let file = c.string("applescript file", "apple script file") {
            kind = .scriptFile(kind: .appleScript, path: file, interpreter: nil)
        } else if let source = c.string("javascript", "java script") {
            kind = .script(kind: .javaScript, source: source, interpreter: nil)
        } else if let file = c.string("javascript file", "java script file") {
            kind = .scriptFile(kind: .javaScript, path: file, interpreter: nil)
        } else if let combos = c["key combos"] as? [Any] {
            kind = .keyCombos(combos.compactMap { KeyCombo(config: $0) })
        } else if let combo = c["key combo", "keyboard shortcut"], let parsed = KeyCombo(config: combo) {
            kind = .keyCombo(parsed)
        } else if let service = c.string("service name", "service") {
            kind = .service(name: service)
        } else if let shortcut = c.string("shortcut name", "shortcut") {
            kind = .shortcut(name: shortcut)
        } else if let native = c.string("native action", "builtin") {
            kind = .native(id: native)
        } else if let inlineCode, let lang = c.string("language") {
            switch normalizeKey(lang) {
            case "javascript", "js": kind = .script(kind: .javaScript, source: inlineCode, interpreter: nil)
            case "applescript": kind = .script(kind: .appleScript, source: inlineCode, interpreter: nil)
            default:
                // Any other language is a shell interpreter: bash, zsh, python3, ruby, perl, node...
                kind = .script(kind: .shell, source: inlineCode, interpreter: interpreterPath(for: lang))
            }
        }
        guard let kind else { return nil }

        let title = c.string("title", "name") ?? extensionName
        var requirements = c.strings("requirements", "required") ?? defaults.requirements ?? ["text"]
        if requirements.isEmpty { requirements = [] }
        let afterString = c.string("after") ?? defaults.after
        var after = AfterAction(config: afterString)
        // Legacy boolean flags.
        if afterString == nil {
            if c.bool("paste result") == true { after = .pasteResult }
            else if c.bool("copy result") == true { after = .copyResult }
            else if c.bool("show result") == true { after = .showResult }
        }
        let apps = ActionDefaults.bundleIDs(c["required apps", "apps", "app"])
        let excluded = ActionDefaults.bundleIDs(c["excluded apps", "blocked apps"])
        let id = c.string("identifier") ?? "\(index)"
        return ActionSpec(id: id, title: title, icon: c.string("icon", "image file") ?? extensionIcon, kind: kind,
                          requirements: requirements, regex: c.string("regex") ?? defaults.regex, after: after,
                          requiredApps: apps.isEmpty ? defaults.apps : apps,
                          excludedApps: excluded.isEmpty ? defaults.excludedApps : excluded,
                          stayVisible: c.bool("stay visible") ?? defaults.stayVisible ?? false,
                          restoreClipboard: c.bool("restore pasteboard", "restore clipboard") ?? defaults.restoreClipboard ?? false,
                          trimInput: c.bool("trim") ?? true,
                          captureHTML: c.bool("capture html") ?? defaults.captureHTML ?? false,
                          description: c.string("description"))
    }

    public static func interpreterPath(for language: String) -> String {
        switch normalizeKey(language) {
        case "shell", "sh": return "/bin/sh"
        case "bash": return "/bin/bash"
        case "zsh": return "/bin/zsh"
        case "python", "python3": return "python3"
        case "ruby": return "ruby"
        case "perl": return "perl"
        case "node", "nodejs": return "node"
        case "swift": return "swift"
        case "php": return "php"
        default: return language
        }
    }
}
