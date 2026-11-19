import Foundation
import Yams

public enum ExtensionLoader {
    /// File names searched (in order) inside an extension bundle folder.
    public static let configNames = ["Config.yaml", "Config.yml", "Config.json", "Config.plist", "config.yaml",
                                     "config.yml", "config.json", "config.plist", "Config.js", "Config.ts", "config.js"]
    public static let bundleExtensions = ["glintext", "popclipext"]

    // MARK: Bundles

    /// File inside an installed bundle recording the identity of an extension that has no `identifier`, so it
    /// stays the same extension when it had to be installed as "<name>-2".
    public static let identityMarker = ".glint-identity"

    /// Identity of a bundle without an `identifier`: the recorded one, else "bundle.<folder name>".
    public static func derivedIdentity(of url: URL) -> String {
        if let recorded = try? String(contentsOf: url.appendingPathComponent(identityMarker), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), recorded.hasPrefix("bundle."), recorded.count < 300 {
            return recorded
        }
        return "bundle." + url.deletingPathExtension().lastPathComponent.lowercased()
    }

    /// - Parameter evaluateModules: false reads only static information (no JavaScript runs), for showing an
    ///   install prompt before the user has agreed to anything; module actions are then left out.
    public static func loadBundle(at url: URL, isBuiltIn: Bool = false, evaluateModules: Bool = true) throws -> ExtensionManifest {
        let fm = FileManager.default
        for name in configNames {
            let file = url.appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else { continue }
            let ext = file.pathExtension.lowercased()
            if (ext == "js" || ext == "ts"), !evaluateModules {
                let folder = url.deletingPathExtension().lastPathComponent
                return ExtensionManifest(identifier: derivedIdentity(of: url), name: folder, actions: [],
                                         bundleURL: url, isBuiltIn: isBuiltIn)
            }
            if ext == "js" || ext == "ts" {
                let src = try String(contentsOf: file, encoding: .utf8)
                var m = try loadJavaScriptModule(source: src, bundleURL: url, isBuiltIn: isBuiltIn)
                if m.identifier.hasPrefix("snippet.") {
                    m.identifier = derivedIdentity(of: url)
                }
                m.sourceURL = url
                return m
            }
            let dict = try readDictionary(file, trusted: isBuiltIn)
            var manifest = try ManifestParser.parse(dict, bundleURL: url, isBuiltIn: isBuiltIn)
            // `module: file.js` in a static config: the module supplies the actions.
            if evaluateModules, manifest.actions.isEmpty, let source = manifest.moduleSource {
                var module = try loadJavaScriptModule(source: source, bundleURL: url, isBuiltIn: isBuiltIn, headerConfig: dict,
                                                      moduleDir: manifest.moduleDir)
                if module.options.isEmpty { module.options = manifest.options }
                manifest = module
            }
            if manifest.identifier.hasPrefix("snippet.") {
                manifest.identifier = derivedIdentity(of: url)
            }
            manifest.sourceURL = url
            return manifest
        }
        throw ManifestError.unreadable("No Config.yaml, Config.json or Config.plist in \(url.lastPathComponent)")
    }

    /// Config files larger than this are refused (any format).
    static let configMaxBytes = 256 * 1024

    public static func readDictionary(_ file: URL, trusted: Bool = false) throws -> [String: Any] {
        let data = try Data(contentsOf: file)
        guard data.count <= configMaxBytes else { throw ManifestError.unreadable("The extension config is too large.") }
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
            return try parseYAMLDictionary(text, trusted: trusted)
        }
    }

    /// Largest YAML document (in nodes, aliases expanded) accepted. Configs are tiny; this stops "billion laughs"
    /// alias bombs before they're expanded, since snippets are parsed before the user agrees to install.
    static let yamlNodeBudget = 50_000

    /// Configs larger than this are refused before parsing.
    static let yamlMaxBytes = 256 * 1024
    /// Alias references allowed (`*name`). Real configs use a handful (`<<: *defaults`); bounding them bounds how
    /// much aliases can expand, including work Yams does while composing (e.g. hashing aliased keys).
    static let yamlMaxAliases = 24
    private static let aliasPattern = try! NSRegularExpression(pattern: #"(?:^|[\s\[\{,:?])\*[A-Za-z0-9_\-]+"#,
                                                               options: [.anchorsMatchLines])

    /// Parses YAML that didn't ship with the app. The app installs a parser that runs in a separate process with
    /// a deadline, so a pathological document can't hang or crash Glint. Nil means parse in-process.
    public static var isolatedYAMLParser: ((String) throws -> [String: Any])?

    public static func parseYAMLDictionary(_ text: String, trusted: Bool = false) throws -> [String: Any] {
        if !trusted, let isolated = isolatedYAMLParser { return try isolated(text) }
        return try parseYAMLInProcess(text)
    }

    /// Yams' default constructor turns "1:00:00:…" into a base-60 Int with trapping arithmetic (crash on
    /// overflow). Such values are kept as strings instead.
    static let safeConstructor: Constructor = {
        var scalars = Constructor.defaultScalarMap
        let int = scalars[.int], float = scalars[.float]
        // YAML 1.1 reads yes/no/on/off as booleans; as config text they must stay words ("on", "Off").
        scalars[.bool] = { s in
            switch s.string.lowercased() {
            case "true": return true
            case "false": return false
            default: return s.string
            }
        }
        scalars[.int] = { s in s.string.contains(":") ? s.string : int?(s) }
        // Keep the author's text for values that don't survive as config strings: dates, binary, inf/NaN.
        scalars[.float] = { s in
            if let d = float?(s) as? Double, !d.isFinite { return s.string }
            return float?(s)
        }
        scalars[.timestamp] = { s in s.string }
        scalars[.binary] = { s in s.string }
        return Constructor(scalars)
    }()

    public static func parseYAMLInProcess(_ text: String) throws -> [String: Any] {
        // libyaml skips a byte-order mark at the start of any line, which could hide aliases from the count.
        if text.unicodeScalars.dropFirst().contains("\u{FEFF}") { throw ManifestError.invalidYAML("Unexpected byte-order mark.") }
        guard text.utf8.count <= yamlMaxBytes else { throw ManifestError.invalidYAML("The extension config is too large.") }
        let aliases = aliasPattern.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        guard aliases <= yamlMaxAliases else { throw ManifestError.invalidYAML("The extension config uses too many aliases.") }
        let object: Any?
        do {
            if let root = try Yams.compose(yaml: text, .default, safeConstructor) { // every node constructs safely
                var count = 0
                func walk(_ node: Node) throws {
                    count += 1
                    if count > yamlNodeBudget { throw ManifestError.invalidYAML("The extension config is too large.") }
                    switch node {
                    case .mapping(let m):
                        for (k, v) in m {
                            // Keys must be plain values (Yams crashes constructing others).
                            guard case .scalar = k else { throw ManifestError.invalidYAML("Keys must be plain text.") }
                            try walk(k); try walk(v)
                        }
                    case .sequence(let s): for v in s { try walk(v) }
                    default: break
                    }
                }
                try walk(root)
                object = root.any
            } else {
                object = nil
            }
        } catch let e as ManifestError { throw e } catch {
            // Keep messages short: some Yams errors embed the source line once per problem.
            if let y = error as? YamlError, case .duplicatedKeysInMapping = y {
                throw ManifestError.invalidYAML("The extension config has duplicate keys.")
            }
            throw ManifestError.invalidYAML(String(String(describing: error).prefix(300)))
        }
        guard let dict = object as? [String: Any] else { throw ManifestError.notADictionary }
        return dict
    }

    /// A Config.js module: the whole extension is defined in JavaScript (`module.exports = { name, actions }`).
    /// The static parts (name, icon, options) are read by evaluating the module once.
    public static func loadJavaScriptModule(source: String, bundleURL: URL?, isBuiltIn: Bool,
                                            snippetSource: String? = nil, headerConfig: [String: Any] = [:],
                                            moduleDir: String = "") throws -> ExtensionManifest {
        let info = JavaScriptRunner.describeModule(source: source, bundleURL: bundleURL, entryDir: moduleDir)
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
                                          requirements: defaults.requirements ?? ["text"],
                                          after: AfterAction(config: defaults.after),
                                          requiredApps: defaults.apps, excludedApps: defaults.excludedApps,
                                          stayVisible: defaults.stayVisible ?? false,
                                          restoreClipboard: defaults.restoreClipboard ?? false,
                                          captureHTML: defaults.captureHTML ?? false))
                continue
            }
            let req = ac.strings("requirements") ?? defaults.requirements ?? ["text"]
            actions.append(ActionSpec(id: ac.string("identifier") ?? "\(i)", title: ac.string("title") ?? name,
                                      icon: ac.string("icon") ?? icon, kind: .jsModuleAction(index: i),
                                      requirements: req, regex: ac.string("regex") ?? defaults.regex,
                                      after: AfterAction(config: ac.string("after") ?? defaults.after),
                                      requiredApps: nonEmpty(ManifestParser.ActionDefaults.bundleIDs(ac["apps", "required apps"]))
                                          ?? defaults.apps,
                                      excludedApps: nonEmpty(ManifestParser.ActionDefaults.bundleIDs(ac["excluded apps"]))
                                          ?? defaults.excludedApps,
                                      stayVisible: ac.bool("stay visible") ?? defaults.stayVisible ?? false,
                                      restoreClipboard: ac.bool("restore pasteboard") ?? defaults.restoreClipboard ?? false,
                                      captureHTML: ac.bool("capture html") ?? defaults.captureHTML ?? false,
                                      description: ac.string("description")))
        }
        if let err = info.error, actions.isEmpty { throw ManifestError.unreadable("JavaScript error: \(err)") }
        if actions.isEmpty { throw ManifestError.noActions }
        let options = (c.dicts("options") ?? []).compactMap { OptionSpec(config: ConfigDict($0)) }
        let identifier = c.string("identifier") ?? ManifestParser.derivedIdentifier(name: name)
        var manifest = ExtensionManifest(identifier: identifier, name: name, icon: icon, description: c.string("description"),
                                 author: c.string("author"), homepage: c.string("homepage"), options: options,
                                 actions: actions, moduleSource: source, bundleURL: bundleURL,
                                 snippetSource: snippetSource, isBuiltIn: isBuiltIn)
        manifest.moduleDir = moduleDir
        return manifest
    }

    private static func nonEmpty(_ a: [String]) -> [String]? { a.isEmpty ? nil : a }

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
    public static func parseSnippet(_ text: String, evaluateModules: Bool = true, trusted: Bool = false) throws -> ExtensionManifest {
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
            let config = try parseYAMLDictionary(configLines.joined(separator: "\n"), trusted: trusted)
            let c = ConfigDict(config)
            if let lang = c.string("language"), ["javascript", "js"].contains(normalizeKey(lang)),
               c.bool("module") == true || code.contains("exports.actions") || code.contains("exports.action ")
                || code.contains("module.exports") {
                guard evaluateModules else {
                    // Static preview: name and identifier from the header, no JavaScript evaluated.
                    let name = c.string("name") ?? "JavaScript Extension"
                    return ExtensionManifest(identifier: c.string("identifier") ?? ManifestParser.derivedIdentifier(name: name),
                                             name: name, description: c.string("description"), actions: [],
                                             snippetSource: text)
                }
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
        let dict = try parseYAMLDictionary(yaml, trusted: trusted)
        return try ManifestParser.parse(dict, snippetSource: text)
    }

    /// `<name>.glintext` in `directory`, unless that folder holds a *different* extension (or something unreadable);
    /// then `<name>-2.glintext`, `<name>-3.glintext`, … so an unrelated extension is never replaced.
    public static func availableFolder(named name: String, forIdentifier identifier: String, in directory: URL,
                                       pathExtension: String = "glintext") -> URL {
        let fm = FileManager.default
        // First look for this extension's own copy among "<name>" and "<name>-N" folders (any bundle suffix);
        // installed extensions are evaluated on every reload anyway, so their real identifiers are read.
        let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let lower = name.lowercased()
        let sameName = items.filter { url in
            guard bundleExtensions.contains(url.pathExtension.lowercased()) || url.pathExtension.lowercased() == pathExtension.lowercased()
            else { return false }
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            if base == lower { return true }
            guard base.hasPrefix(lower + "-") else { return false }
            return !base.dropFirst(lower.count + 1).isEmpty && base.dropFirst(lower.count + 1).allSatisfy(\.isNumber)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for candidate in sameName where (try? load(folder: candidate))?.identifier == identifier {
            return candidate
        }
        // Otherwise the first free "<name>" / "<name>-N" slot; never an occupied folder of another extension.
        for n in 1..<1000 {
            let candidate = directory.appendingPathComponent(n == 1 ? "\(name).\(pathExtension)" : "\(name)-\(n).\(pathExtension)",
                                                             isDirectory: true)
            if !fm.fileExists(atPath: candidate.path), (try? candidate.checkResourceIsReachable()) != true,
               (try? fm.destinationOfSymbolicLink(atPath: candidate.path)) == nil {
                return candidate
            }
        }
        return directory.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).\(pathExtension)", isDirectory: true)
    }

    /// Moves to the Trash, or deletes when the volume has no Trash (some network homes).
    public static func discard(_ url: URL) throws {
        let fm = FileManager.default
        do { try fm.trashItem(at: url, resultingItemURL: nil) } catch { try fm.removeItem(at: url) }
    }

    /// Converts a snippet into a bundle folder on disk so it survives restarts.
    @discardableResult
    public static func installSnippet(_ text: String, into directory: URL) throws -> URL {
        let manifest = try parseSnippet(text)
        var safe = manifest.identifier.replacingOccurrences(of: "/", with: "-")
        while safe.hasPrefix(".") { safe.removeFirst() } // hidden folders are never loaded
        if safe.isEmpty { safe = "extension-\(UUID().uuidString.prefix(8))" }
        let folder = availableFolder(named: safe, forIdentifier: manifest.identifier, in: directory)
        let fm = FileManager.default
        // Replacing the same extension: the old copy goes to the Trash, not deleted outright.
        if fm.fileExists(atPath: folder.path) { try discard(folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("Snippet.txt"), atomically: true, encoding: .utf8)
        return folder
    }

    /// Loads either a bundle with a Config file or a folder holding a saved Snippet.txt.
    public static func load(folder: URL, isBuiltIn: Bool = false, evaluateModules: Bool = true) throws -> ExtensionManifest {
        let snippet = folder.appendingPathComponent("Snippet.txt")
        if FileManager.default.fileExists(atPath: snippet.path) {
            let text = try String(contentsOf: snippet, encoding: .utf8)
            var m = try parseSnippet(text, evaluateModules: evaluateModules, trusted: isBuiltIn)
            m.bundleURL = folder
            m.sourceURL = folder
            m.isBuiltIn = isBuiltIn
            return m
        }
        return try loadBundle(at: folder, isBuiltIn: isBuiltIn, evaluateModules: evaluateModules)
    }

    /// Loads every extension in a directory. Failures are returned alongside successes.
    public static func loadAll(in directory: URL, isBuiltIn: Bool = false) -> (extensions: [ExtensionManifest], errors: [(URL, Error)]) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return ([], []) }
        var exts: [ExtensionManifest] = []
        var errors: [(URL, Error)] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !item.lastPathComponent.hasPrefix(".") {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                do { exts.append(try load(folder: item, isBuiltIn: isBuiltIn)) } catch { errors.append((item, error)) }
            } else if ["yaml", "yml", "txt"].contains(item.pathExtension.lowercased()) {
                do {
                    let text = try String(contentsOf: item, encoding: .utf8)
                    var m = isSnippet(text) ? try parseSnippet(text, trusted: isBuiltIn)
                                            : try ManifestParser.parse(parseYAMLDictionary(text, trusted: isBuiltIn), isBuiltIn: isBuiltIn)
                    m.isBuiltIn = isBuiltIn
                    m.sourceURL = item
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
