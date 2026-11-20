import AppKit
import Combine
import GlintCore
import ServiceManagement

/// All user settings, persisted in UserDefaults. Observe with SwiftUI (`@ObservedObject`) or Combine.
final class Preferences: ObservableObject, UpdateSettings {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    enum DisplayMode: String, CaseIterable, Identifiable { case iconsOnly, textOnly, iconsAndText; var id: String { rawValue } }
    enum BarSize: String, CaseIterable, Identifiable { case small, medium, large; var id: String { rawValue } }
    enum Theme: String, CaseIterable, Identifiable { case system, dark, light; var id: String { rawValue } }
    enum Position: String, CaseIterable, Identifiable { case above, below; var id: String { rawValue } }

    struct SearchEngine: Identifiable, Hashable {
        var id: String
        var name: String
        var template: String
        static let all: [SearchEngine] = [
            .init(id: "google", name: "Google", template: "https://www.google.com/search?q=***"),
            .init(id: "duckduckgo", name: "DuckDuckGo", template: "https://duckduckgo.com/?q=***"),
            .init(id: "bing", name: "Bing", template: "https://www.bing.com/search?q=***"),
            .init(id: "kagi", name: "Kagi", template: "https://kagi.com/search?q=***"),
            .init(id: "brave", name: "Brave Search", template: "https://search.brave.com/search?q=***"),
            .init(id: "ecosia", name: "Ecosia", template: "https://www.ecosia.org/search?q=***"),
            .init(id: "perplexity", name: "Perplexity", template: "https://www.perplexity.ai/search?q=***"),
            .init(id: "startpage", name: "Startpage", template: "https://www.startpage.com/do/search?q=***"),
            .init(id: "custom", name: "Custom…", template: ""),
        ]
    }

    // MARK: General
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Glint: launch at login change failed: \(error)")
                // Show what macOS actually has (e.g. disabled under Login Items in System Settings).
                DispatchQueue.main.async { self.launchAtLogin = SMAppService.mainApp.status == .enabled }
            }
        }
    }

    // MARK: Activation
    @Published var activateOnDrag: Bool { didSet { d.set(activateOnDrag, forKey: "activateOnDrag") } }
    @Published var activateOnDoubleClick: Bool { didSet { d.set(activateOnDoubleClick, forKey: "activateOnDoubleClick") } }
    @Published var activateOnTripleClick: Bool { didSet { d.set(activateOnTripleClick, forKey: "activateOnTripleClick") } }
    @Published var activateOnShiftClick: Bool { didSet { d.set(activateOnShiftClick, forKey: "activateOnShiftClick") } }
    /// Long-press in an editable field shows a bar with Paste.
    @Published var activateOnLongPress: Bool { didSet { d.set(activateOnLongPress, forKey: "activateOnLongPress") } }
    /// Show after selecting with the keyboard (⇧ + arrows, ⌘A).
    @Published var activateOnKeyboardSelection: Bool { didSet { d.set(activateOnKeyboardSelection, forKey: "activateOnKeyboardSelection") } }
    /// Hold this modifier while selecting to suppress the bar (raw NSEvent.ModifierFlags value, 0 = none).
    @Published var suppressModifier: Int { didSet { d.set(suppressModifier, forKey: "suppressModifier") } }
    /// Global shortcut that shows the bar for the current selection.
    @Published var showBarHotKey: KeyCombo? { didSet { saveCodable(showBarHotKey, "showBarHotKey") } }
    /// Seconds to wait after the selection before showing the bar.
    @Published var popupDelay: Double { didSet { d.set(popupDelay, forKey: "popupDelay") } }

    // MARK: Appearance
    @Published var displayMode: DisplayMode { didSet { d.set(displayMode.rawValue, forKey: "displayMode") } }
    @Published var barSize: BarSize { didSet { d.set(barSize.rawValue, forKey: "barSize") } }
    @Published var theme: Theme { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var position: Position { didSet { d.set(position.rawValue, forKey: "position") } }
    @Published var dismissWhenMouseLeaves: Bool { didSet { d.set(dismissWhenMouseLeaves, forKey: "dismissWhenMouseLeaves") } }
    /// Show the action's name as a tooltip-style label when hovering an icon.
    @Published var showHoverLabels: Bool { didSet { d.set(showHoverLabels, forKey: "showHoverLabels") } }

    // MARK: Actions
    /// Order of registry entries (built-in and extension keys).
    @Published var actionOrder: [String] { didSet { d.set(actionOrder, forKey: "actionOrder") } }
    @Published var disabledActions: Set<String> { didSet { d.set(Array(disabledActions), forKey: "disabledActions") } }
    /// Entries enabled at least once by the user (so default-disabled entries keep their state).
    @Published var knownActions: Set<String> { didSet { d.set(Array(knownActions), forKey: "knownActions") } }
    /// Per-entry global shortcuts: run that entry's first action on the current selection.
    @Published var actionHotKeys: [String: KeyCombo] { didSet { saveCodable(actionHotKeys, "actionHotKeys") } }
    @Published var searchEngineID: String { didSet { d.set(searchEngineID, forKey: "searchEngineID") } }
    @Published var customSearchTemplate: String { didSet { d.set(customSearchTemplate, forKey: "customSearchTemplate") } }
    @Published var speechVoiceID: String { didSet { d.set(speechVoiceID, forKey: "speechVoiceID") } }
    @Published var speechRate: Double { didSet { d.set(speechRate, forKey: "speechRate") } }

    // MARK: Apps
    /// Bundle IDs where Glint never appears.
    @Published var excludedApps: [String] { didSet { d.set(excludedApps, forKey: "excludedApps") } }

    // MARK: Advanced
    /// Fall back to simulating ⌘C when the app doesn't expose the selection through Accessibility.
    @Published var useCopyFallback: Bool { didSet { d.set(useCopyFallback, forKey: "useCopyFallback") } }
    /// Put the original clipboard back after paste-result actions.
    @Published var restoreClipboardAfterPaste: Bool { didSet { d.set(restoreClipboardAfterPaste, forKey: "restoreClipboardAfterPaste") } }
    @Published var maxTextLength: Int { didSet { d.set(maxTextLength, forKey: "maxTextLength") } }
    @Published var hasCompletedOnboarding: Bool { didSet { d.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }

    // MARK: Updates
    @Published var automaticallyChecksForUpdates: Bool { didSet { d.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates") } }
    var lastUpdateCheckAt: Date? {
        get { d.object(forKey: "lastUpdateCheckAt") as? Date }
        set { d.set(newValue, forKey: "lastUpdateCheckAt") }
    }
    var cachedUpdateTag: String? {
        get { d.string(forKey: "cachedUpdateTag") }
        set { d.set(newValue, forKey: "cachedUpdateTag") }
    }
    var cachedUpdateURLString: String? {
        get { d.string(forKey: "cachedUpdateURLString") }
        set { d.set(newValue, forKey: "cachedUpdateURLString") }
    }
    var dismissedReleaseTag: String? {
        get { d.string(forKey: "dismissedReleaseTag") }
        set { d.set(newValue, forKey: "dismissedReleaseTag") }
    }

    static let defaultExcludedApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess", "com.bitwarden.desktop",
        "com.apple.loginwindow", "com.apple.ScreenSharing",
    ]

    private init() {
        d.register(defaults: [
            "enabled": true, "showMenuBarIcon": true,
            "activateOnDrag": true, "activateOnDoubleClick": true, "activateOnTripleClick": true,
            "activateOnShiftClick": true, "activateOnLongPress": true, "activateOnKeyboardSelection": false,
            "suppressModifier": 0, "popupDelay": 0.0,
            "displayMode": DisplayMode.iconsOnly.rawValue, "barSize": BarSize.medium.rawValue,
            "theme": Theme.system.rawValue, "position": Position.above.rawValue,
            "dismissWhenMouseLeaves": true, "showHoverLabels": true,
            "searchEngineID": "google", "customSearchTemplate": "", "speechVoiceID": "", "speechRate": 0.5,
            "excludedApps": Preferences.defaultExcludedApps,
            "useCopyFallback": true, "restoreClipboardAfterPaste": true, "maxTextLength": 100_000,
            "hasCompletedOnboarding": false, "automaticallyChecksForUpdates": true,
        ])
        enabled = d.bool(forKey: "enabled")
        showMenuBarIcon = d.bool(forKey: "showMenuBarIcon")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        activateOnDrag = d.bool(forKey: "activateOnDrag")
        activateOnDoubleClick = d.bool(forKey: "activateOnDoubleClick")
        activateOnTripleClick = d.bool(forKey: "activateOnTripleClick")
        activateOnShiftClick = d.bool(forKey: "activateOnShiftClick")
        activateOnLongPress = d.bool(forKey: "activateOnLongPress")
        activateOnKeyboardSelection = d.bool(forKey: "activateOnKeyboardSelection")
        suppressModifier = d.integer(forKey: "suppressModifier")
        popupDelay = d.double(forKey: "popupDelay")
        displayMode = DisplayMode(rawValue: d.string(forKey: "displayMode") ?? "") ?? .iconsOnly
        barSize = BarSize(rawValue: d.string(forKey: "barSize") ?? "") ?? .medium
        theme = Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        position = Position(rawValue: d.string(forKey: "position") ?? "") ?? .above
        dismissWhenMouseLeaves = d.bool(forKey: "dismissWhenMouseLeaves")
        showHoverLabels = d.bool(forKey: "showHoverLabels")
        actionOrder = d.stringArray(forKey: "actionOrder") ?? []
        disabledActions = Set(d.stringArray(forKey: "disabledActions") ?? [])
        knownActions = Set(d.stringArray(forKey: "knownActions") ?? [])
        searchEngineID = d.string(forKey: "searchEngineID") ?? "google"
        customSearchTemplate = d.string(forKey: "customSearchTemplate") ?? ""
        speechVoiceID = d.string(forKey: "speechVoiceID") ?? ""
        speechRate = d.double(forKey: "speechRate")
        excludedApps = d.stringArray(forKey: "excludedApps") ?? Preferences.defaultExcludedApps
        useCopyFallback = d.bool(forKey: "useCopyFallback")
        restoreClipboardAfterPaste = d.bool(forKey: "restoreClipboardAfterPaste")
        maxTextLength = d.integer(forKey: "maxTextLength")
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        automaticallyChecksForUpdates = d.bool(forKey: "automaticallyChecksForUpdates")
        showBarHotKey = Preferences.loadCodable("showBarHotKey")
        actionHotKeys = Preferences.loadCodable("actionHotKeys") ?? [:]
    }

    var searchTemplate: String {
        if searchEngineID == "custom", !customSearchTemplate.isEmpty { return customSearchTemplate }
        // "Custom" with an empty URL (or an unknown id) falls back to the first engine rather than doing nothing.
        return SearchEngine.all.first { $0.id == searchEngineID && !$0.template.isEmpty }?.template
            ?? SearchEngine.all[0].template
    }

    // MARK: Extension options

    func optionValues(for ext: ExtensionManifest) -> [String: String] {
        var values: [String: String] = [:]
        let stored = d.dictionary(forKey: "options.\(ext.identifier)") as? [String: String] ?? [:]
        for spec in ext.options where spec.kind != .heading {
            if spec.kind == .password || spec.kind == .secret {
                values[spec.id] = Keychain.get(service: "dev.saibarath.glint.options", account: "\(ext.identifier).\(spec.id)")
                    ?? spec.defaultValue ?? ""
            } else {
                values[spec.id] = stored[spec.id] ?? spec.defaultValue ?? (spec.kind == .multiple ? spec.values.first : nil)
                    ?? (spec.kind == .boolean ? "0" : "")
            }
        }
        return values
    }

    func setOption(_ value: String, id: String, for staleExt: ExtensionManifest) {
        // Use the extension as currently loaded: after a reload, a newly added option may be a secret.
        let ext = ActionRegistry.shared.entry(staleExt.identifier)?.manifest ?? staleExt
        objectWillChange.send()
        if let spec = ext.options.first(where: { $0.id == id }), spec.kind == .password || spec.kind == .secret {
            Keychain.set(value, service: "dev.saibarath.glint.options", account: "\(ext.identifier).\(id)")
            return
        }
        var stored = d.dictionary(forKey: "options.\(ext.identifier)") as? [String: String] ?? [:]
        stored[id] = value
        d.set(stored, forKey: "options.\(ext.identifier)")
    }

    // MARK: Helpers

    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains(bundleID)
    }

    private func saveCodable<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) { d.set(data, forKey: key) } else { d.removeObject(forKey: key) }
    }

    private static func loadCodable<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

enum Keychain {
    static func get(service: String, account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, service: String, account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
