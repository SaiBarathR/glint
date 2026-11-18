import AppKit
import Combine
import GlintCore

/// Built-in actions implemented natively.
enum BuiltinID: String, CaseIterable {
    case installExtension, search, cut, copy, paste, pasteMatchStyle, openLink, newMail, call, revealInFinder, lookUp,
         spelling, formatting, speak, stats, calculate

    var name: String {
        switch self {
        case .installExtension: return "Install Extension"
        case .search: return "Search"
        case .cut: return "Cut"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .pasteMatchStyle: return "Paste and Match Style"
        case .openLink: return "Open Link"
        case .newMail: return "New Email"
        case .call: return "Call"
        case .revealInFinder: return "Reveal in Finder"
        case .lookUp: return "Look Up"
        case .spelling: return "Spelling"
        case .formatting: return "Bold, Italic, Underline"
        case .speak: return "Speak"
        case .stats: return "Word Count"
        case .calculate: return "Calculate"
        }
    }

    /// Icon spec (see IconRenderer).
    var icon: String {
        switch self {
        case .installExtension: return "symbol:puzzlepiece.extension.fill"
        case .search: return "symbol:magnifyingglass"
        case .cut: return "symbol:scissors"
        case .copy: return "symbol:doc.on.doc"
        case .paste: return "symbol:doc.on.clipboard"
        case .pasteMatchStyle: return "symbol:list.clipboard"
        case .openLink: return "symbol:safari"
        case .newMail: return "symbol:envelope"
        case .call: return "symbol:phone"
        case .revealInFinder: return "symbol:folder"
        case .lookUp: return "symbol:character.book.closed"
        case .spelling: return "symbol:textformat.abc.dottedunderline"
        case .formatting: return "symbol:bold.italic.underline"
        case .speak: return "symbol:speaker.wave.2"
        case .stats: return "symbol:number"
        case .calculate: return "symbol:equal.circle"
        }
    }

    var summary: String {
        switch self {
        case .installExtension: return "Appears when you select an extension snippet (text starting with #glint or #popclip)."
        case .search: return "Search the web for the selected text with your chosen search engine."
        case .cut: return "Cut the selection. Only in editable text."
        case .copy: return "Copy the selection. Hold ⇧ to append it to the text already on the clipboard."
        case .paste: return "Paste over the selection, or at the cursor after a long press."
        case .pasteMatchStyle: return "Paste plain text, matching the surrounding style. Hold ⌥ on Paste to do the same."
        case .openLink: return "Open the selected link(s) in your browser. ⌘ opens in the background, ⇧ copies the link."
        case .newMail: return "Start a new email to the selected address."
        case .call: return "Call the selected phone number with FaceTime or your iPhone."
        case .revealInFinder: return "Show the selected file path in Finder."
        case .lookUp: return "Show the dictionary definition."
        case .spelling: return "Suggest corrections for a misspelled word and replace it."
        case .formatting: return "Bold, italic and underline buttons in rich-text editors."
        case .speak: return "Read the selection aloud. Click again to stop."
        case .stats: return "Show word, character and line counts."
        case .calculate: return "Show the result of a selected math expression. Click it to copy, ⇧ to paste."
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .speak, .pasteMatchStyle, .call: return false
        default: return true
        }
    }

    var key: String { "builtin." + rawValue }
}

struct RegistryEntry: Identifiable, Equatable {
    enum Source: Equatable {
        case builtin(BuiltinID)
        /// Shipped inside the app bundle (Resources/Extensions).
        case bundled(ExtensionManifest)
        /// Installed by the user.
        case user(ExtensionManifest)
    }
    let key: String
    let source: Source
    var id: String { key }

    var name: String {
        switch source {
        case .builtin(let b): return b.name
        case .bundled(let m), .user(let m): return m.name
        }
    }
    var icon: String? {
        switch source {
        case .builtin(let b): return b.icon
        case .bundled(let m), .user(let m): return m.icon ?? m.actions.first?.icon
        }
    }
    var summary: String {
        switch source {
        case .builtin(let b): return b.summary
        case .bundled(let m), .user(let m): return m.description ?? m.actions.map(\.title).joined(separator: ", ")
        }
    }
    var manifest: ExtensionManifest? {
        switch source {
        case .builtin: return nil
        case .bundled(let m), .user(let m): return m
        }
    }
    var isUserInstalled: Bool { if case .user = source { return true }; return false }
    var builtin: BuiltinID? { if case .builtin(let b) = source { return b }; return nil }
    /// Base folder for resolving icon files.
    var iconBaseURL: URL? { manifest?.bundleURL }
}

/// One button on the bar, ready to perform.
struct BarAction: Identifiable {
    enum Kind {
        case builtin(BuiltinID, variant: String?)
        case extensionAction(ExtensionManifest, ActionSpec, ActionInput, dynamicIndex: Int?)
    }
    let id: String
    let entryKey: String
    let title: String
    let icon: String?
    let iconBaseURL: URL?
    let kind: Kind
    /// Always show the title as text (e.g. a calculation result).
    var textOnly: Bool = false
}

/// The ordered set of built-ins and extensions, with enable state and install/uninstall.
final class ActionRegistry: ObservableObject {
    static let shared = ActionRegistry()

    @Published private(set) var entries: [RegistryEntry] = []
    @Published private(set) var loadErrors: [(name: String, message: String)] = []

    private let prefs = Preferences.shared

    /// Bundled extensions enabled by default (the rest start disabled, ready to switch on).
    static let defaultEnabledBundled: Set<String> = ["dev.saibarath.glint.translate", "dev.saibarath.glint.change-case"]

    static var userExtensionsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Glint/Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var bundledExtensionsDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Extensions", isDirectory: true)
    }

    private init() { reload() }

    func reload() {
        var list: [RegistryEntry] = BuiltinID.allCases.map { RegistryEntry(key: $0.key, source: .builtin($0)) }
        var errors: [(String, String)] = []
        if let dir = Self.bundledExtensionsDirectory {
            let r = ExtensionLoader.loadAll(in: dir, isBuiltIn: true)
            list += r.extensions.map { RegistryEntry(key: $0.identifier, source: .bundled($0)) }
            errors += r.errors.map { ($0.0.lastPathComponent, $0.1.localizedDescription) }
        }
        let user = ExtensionLoader.loadAll(in: Self.userExtensionsDirectory)
        // A user extension with the same identifier replaces the bundled one.
        for m in user.extensions {
            list.removeAll { $0.key == m.identifier }
            list.append(RegistryEntry(key: m.identifier, source: .user(m)))
        }
        errors += user.errors.map { ($0.0.lastPathComponent, $0.1.localizedDescription) }

        // Apply saved order; new entries go after known ones in default order.
        let order = prefs.actionOrder
        list.sort { a, b in
            let ia = order.firstIndex(of: a.key) ?? Int.max
            let ib = order.firstIndex(of: b.key) ?? Int.max
            if ia != ib { return ia < ib }
            return false
        }
        // Built-in install action always first.
        if let i = list.firstIndex(where: { $0.builtin == .installExtension }) { list.insert(list.remove(at: i), at: 0) }
        entries = list
        loadErrors = errors
    }

    // MARK: Enable / order

    func isEnabled(_ key: String) -> Bool {
        if prefs.disabledActions.contains(key) { return false }
        if prefs.knownActions.contains(key) { return true }
        guard let entry = entries.first(where: { $0.key == key }) else { return true }
        switch entry.source {
        case .builtin(let b): return b.defaultEnabled
        case .bundled(let m): return Self.defaultEnabledBundled.contains(m.identifier)
        case .user: return true
        }
    }

    func setEnabled(_ key: String, _ enabled: Bool) {
        objectWillChange.send()
        if enabled {
            prefs.disabledActions.remove(key)
            prefs.knownActions.insert(key)
        } else {
            prefs.disabledActions.insert(key)
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = entries
        let moving = source.map { list[$0] }
        for i in source.sorted(by: >) { list.remove(at: i) }
        let removedBefore = source.filter { $0 < destination }.count
        list.insert(contentsOf: moving, at: destination - removedBefore)
        entries = list
        prefs.actionOrder = list.map(\.key)
    }

    func resetOrder() {
        prefs.actionOrder = []
        reload()
    }

    // MARK: Install / uninstall

    /// Installs a snippet. Returns the installed manifest.
    @discardableResult
    func install(snippet text: String) throws -> ExtensionManifest {
        let folder = try ExtensionLoader.installSnippet(text, into: Self.userExtensionsDirectory)
        let m = try ExtensionLoader.load(folder: folder)
        finishInstall(m)
        return m
    }

    /// Copies an extension package (.glintext / .popclipext folder) into the user directory.
    @discardableResult
    func install(bundleAt url: URL) throws -> ExtensionManifest {
        let manifest = try ExtensionLoader.loadBundle(at: url)
        let fm = FileManager.default
        let dest = Self.userExtensionsDirectory.appendingPathComponent(url.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: url, to: dest)
        _ = manifest
        let installed = try ExtensionLoader.loadBundle(at: dest)
        finishInstall(installed)
        return installed
    }

    private func finishInstall(_ m: ExtensionManifest) {
        prefs.disabledActions.remove(m.identifier)
        prefs.knownActions.insert(m.identifier)
        reload()
    }

    func uninstall(_ key: String) {
        guard let entry = entries.first(where: { $0.key == key }), entry.isUserInstalled,
              let url = entry.manifest?.bundleURL else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        prefs.disabledActions.remove(key)
        prefs.knownActions.remove(key)
        prefs.actionHotKeys.removeValue(forKey: key)
        reload()
    }

    func entry(_ key: String) -> RegistryEntry? { entries.first { $0.key == key } }
}
