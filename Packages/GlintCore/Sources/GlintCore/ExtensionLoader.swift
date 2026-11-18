import Foundation
import Yams

public enum ExtensionLoader {
    /// File names searched (in order) inside an extension bundle folder.
    public static let configNames = ["Config.yaml", "Config.yml", "Config.json", "Config.plist", "config.yaml",
                                     "config.yml", "config.json", "config.plist", "Config.js", "Config.ts", "config.js"]
    public static let bundleExtensions = ["glintext", "popclipext"]

    // MARK: Bundles

    public static func loadBundle(at url: URL, isBuiltIn: Bool = false) throws -> ExtensionManifest {
        let fm = FileManager.default
        for name in configNames {
            let file = url.appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else { continue }
            let ext = file.pathExtension.lowercased()
            if ext == "js" || ext == "ts" {
                let src = try String(contentsOf: file, encoding: .utf8)
                return try loadJavaScriptModule(source: src, bundleURL: url, isBuiltIn: isBuiltIn)
            }
            let dict = try readDictionary(file)
            var manifest = try ManifestParser.parse(dict, bundleURL: url, isBuiltIn: isBuiltIn)
            // `module: file.js` in a static config: the module supplies the actions.
            if manifest.actions.isEmpty, let source = manifest.moduleSource {
                var module = try loadJavaScriptModule(source: source, bundleURL: url, isBuiltIn: isBuiltIn, headerConfig: dict)
                if module.options.isEmpty { module.options = manifest.options }
                manifest = module
            }
            if manifest.identifier.hasPrefix("snippet.") {
                manifest.identifier = "bundle." + url.deletingPathExtension().lastPathComponent.lowercased()
            }
            return manifest
        }
        throw ManifestError.unreadable("No Config.yaml, Config.json or Config.plist in \(url.lastPathComponent)")
    }

    public static func readDictionary(_ file: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: file)
        switch file.pathExtension.lowercased() {
        case "json":
            guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ManifestError.notADictionary }
            return d
        case "plist":
            guard let d = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw ManifestError.notADictionary
            }
            return d
        default:
            guard let text = String(data: data, encoding: .utf8) else { throw ManifestError.unreadable("not UTF-8") }
            return try parseYAMLDictionary(text)
        }
    }

    public static func parseYAMLDictionary(_ text: String) throws -> [String: Any] {
        let object: Any?
        do { object = try Yams.load(yaml: text) } catch { throw ManifestError.invalidYAML("\(error)") }
        guard let dict = object as? [String: Any] else { throw ManifestError.notADictionary }
        return dict
    }

    /// A Config.js module: the whole extension is defined in JavaScript (`module.exports = { name, actions }`).
    /// The static parts (name, icon, options) are read by evaluating the module once.
    public static func loadJavaScriptModule(source: String, bundleURL: URL?, isBuiltIn: Bool,
                                            snippetSource: String? = nil, headerConfig: [String: Any] = [:]) throws -> ExtensionManifest {
        let info = JavaScriptRunner.describeModule(source: source)
        var dict = headerConfig
        for (k, v) in info.config where dict[k] == nil { dict[k] = v }
        if dict["name"] == nil { dict["name"] = bundleURL?.deletingPathExtension().lastPathComponent ?? "JavaScript Extension" }
        // Actions are provided by the module; build specs that call back into it.
        let c = ConfigDict(dict)
        let name = c.string("name") ?? "Extension"
        let icon = c.string("icon")
        let defaults = ManifestParser.ActionDefaults(config: c)
        var actions: [ActionSpec] = []
        for (i, a) in info.actions.enumerated() {
            let ac = ConfigDict(a)
            if ac.bool("dynamic") == true {
                actions.append(ActionSpec(id: "dynamic", title: name, icon: icon, kind: .jsModuleAction(index: -1),
                                          requirements: defaults.requirements ?? ["text"]))
                continue
            }
            let req = ac.strings("requirements") ?? defaults.requirements ?? ["text"]
            actions.append(ActionSpec(id: ac.string("identifier") ?? "\(i)", title: ac.string("title") ?? name,
                                      icon: ac.string("icon") ?? icon, kind: .jsModuleAction(index: i),
                                      requirements: req, regex: ac.string("regex") ?? defaults.regex,
                                      after: AfterAction(config: ac.string("after") ?? defaults.after),
                                      requiredApps: ManifestParser.ActionDefaults.bundleIDs(ac["apps", "required apps"]),
                                      excludedApps: ManifestParser.ActionDefaults.bundleIDs(ac["excluded apps"]),
                                      stayVisible: ac.bool("stay visible") ?? false,
                                      captureHTML: ac.bool("capture html") ?? false))
        }
        if let err = info.error, actions.isEmpty { throw ManifestError.unreadable("JavaScript error: \(err)") }
        if actions.isEmpty { throw ManifestError.noActions }
        let options = (c.dicts("options") ?? []).compactMap { OptionSpec(config: ConfigDict($0)) }
        let identifier = c.string("identifier") ?? ManifestParser.derivedIdentifier(name: name)
        return ExtensionManifest(identifier: identifier, name: name, icon: icon, description: c.string("description"),
                                 author: c.string("author"), homepage: c.string("homepage"), options: options,
                                 actions: actions, moduleSource: source, bundleURL: bundleURL,
                                 snippetSource: snippetSource, isBuiltIn: isBuiltIn)
    }

    // MARK: Snippets

    /// Header lines that mark text as an installable extension snippet.
    static let headerRegex = try! NSRegularExpression(
        pattern: #"^\s*(#|//|--|;|%)?\s*#\s*(glint|popclip)\b"#, options: [.caseInsensitive])

    /// True when the selected text is an extension snippet (first non-empty line is a `#glint` / `#popclip` header).
    public static func isSnippet(_ text: String) -> Bool {
        guard let first = text.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return false
        }
        let line = String(first)
        return headerRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// Parses a snippet. Two forms are supported:
    ///  1. YAML snippets: `#glint` header line followed by YAML config.
    ///  2. Inverted snippets: code whose header comment lines hold the YAML config, e.g.
    ///     `// #glint` / `// name: Upper` / `// language: javascript` then the script body.
    public static func parseSnippet(_ text: String) throws -> ExtensionManifest {
        var lines = text.components(separatedBy: .newlines)
        while let f = lines.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        guard let header = lines.first else { throw ManifestError.missingName }
        let ns = header as NSString
        guard let match = headerRegex.firstMatch(in: header, range: NSRange(location: 0, length: ns.length)) else {
            throw ManifestError.unreadable("Snippet must start with a #glint header line")
        }
        let prefixRange = match.range(at: 1)
        let commentPrefix = prefixRange.location == NSNotFound ? nil : ns.substring(with: prefixRange)
        // Anything after the header keyword on the same line may itself be YAML (e.g. "#glint name: Foo").
        let headerRest = ns.substring(from: match.range.location + match.range.length).trimmingCharacters(in: .whitespaces)

        if let prefix = commentPrefix {
            // Inverted snippet: config is the block of comment lines after the header.
            var configLines: [String] = []
            if headerRest.contains(":") { configLines.append(headerRest) }
            var index = 1
            while index < lines.count {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(prefix) else { break }
                var content = String(trimmed.dropFirst(prefix.count))
                if content.hasPrefix(" ") { content.removeFirst() }
                configLines.append(content)
                index += 1
            }
            let code = lines[index...].joined(separator: "\n").trimmingCharacters(in: .newlines)
            let config = try parseYAMLDictionary(configLines.joined(separator: "\n"))
            let c = ConfigDict(config)
            if let lang = c.string("language"), ["javascript", "js"].contains(normalizeKey(lang)),
               c.bool("module") == true || code.contains("exports.actions") || code.contains("exports.action ")
                || code.contains("module.exports") {
                return try loadJavaScriptModule(source: code, bundleURL: nil, isBuiltIn: false, snippetSource: text,
                                                headerConfig: config)
            }
            var dict = config
            if c.string("language") == nil {
                // Infer the language from the comment style.
                switch prefix {
                case "//": dict["language"] = "javascript"
                case "--": dict["language"] = "applescript"
                default: dict["language"] = "shell"
                }
            }
            return try ManifestParser.parse(dict, inlineCode: code, snippetSource: text)
        }

        var yaml = lines.dropFirst().joined(separator: "\n")
        if headerRest.contains(":") { yaml = headerRest + "\n" + yaml }
        let dict = try parseYAMLDictionary(yaml)
        return try ManifestParser.parse(dict, snippetSource: text)
    }

    /// Converts a snippet into a bundle folder on disk so it survives restarts.
    @discardableResult
    public static func installSnippet(_ text: String, into directory: URL) throws -> URL {
        let manifest = try parseSnippet(text)
        let safe = manifest.identifier.replacingOccurrences(of: "/", with: "-")
        let folder = directory.appendingPathComponent(safe + ".glintext", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("Snippet.txt"), atomically: true, encoding: .utf8)
        return folder
    }

    /// Loads either a bundle with a Config file or a folder holding a saved Snippet.txt.
    public static func load(folder: URL, isBuiltIn: Bool = false) throws -> ExtensionManifest {
        let snippet = folder.appendingPathComponent("Snippet.txt")
        if FileManager.default.fileExists(atPath: snippet.path) {
            let text = try String(contentsOf: snippet, encoding: .utf8)
            var m = try parseSnippet(text)
            m.bundleURL = folder
            m.isBuiltIn = isBuiltIn
            return m
        }
        return try loadBundle(at: folder, isBuiltIn: isBuiltIn)
    }

    /// Loads every extension in a directory. Failures are returned alongside successes.
    public static func loadAll(in directory: URL, isBuiltIn: Bool = false) -> (extensions: [ExtensionManifest], errors: [(URL, Error)]) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return ([], []) }
        var exts: [ExtensionManifest] = []
        var errors: [(URL, Error)] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                do { exts.append(try load(folder: item, isBuiltIn: isBuiltIn)) } catch { errors.append((item, error)) }
            } else if ["yaml", "yml", "txt"].contains(item.pathExtension.lowercased()) {
                do {
                    let text = try String(contentsOf: item, encoding: .utf8)
                    var m = isSnippet(text) ? try parseSnippet(text)
                                            : try ManifestParser.parse(parseYAMLDictionary(text), isBuiltIn: isBuiltIn)
                    m.isBuiltIn = isBuiltIn
                    if m.identifier.hasPrefix("snippet."), isBuiltIn {
                        m.identifier = "builtin." + item.deletingPathExtension().lastPathComponent.lowercased()
                    }
                    exts.append(m)
                } catch { errors.append((item, error)) }
            }
        }
        return (exts, errors)
    }
}
