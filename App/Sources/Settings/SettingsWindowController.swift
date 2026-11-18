import AppKit
import Combine
import GlintCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, actions, apps, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .actions: return "Actions"
        case .apps: return "Apps"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .actions: return "puzzlepiece.extension"
        case .apps: return "hand.raised"
        case .advanced: return "gearshape.2"
        case .about: return "info.circle"
        }
    }

    var toolbarIdentifier: NSToolbarItem.Identifier { .init("glint.settings." + rawValue) }
}

/// Which pane and which action are showing. Shared by the toolbar and the SwiftUI content.
final class SettingsNavigator: ObservableObject {
    @Published var pane: SettingsPane = .general
    @Published var selectedEntryKey: String?
    /// Snapshot only: an in-memory extension shown in the Actions list.
    var previewEntry: RegistryEntry?
    /// Snapshot only: fake load errors.
    var previewLoadErrors: [(name: String, message: String)]?
    /// Snapshot only: overrides the live Accessibility status.
    var previewAccessibilityTrusted: Bool?
}

struct SettingsRootView: View {
    @ObservedObject var nav: SettingsNavigator

    var body: some View {
        Group {
            switch nav.pane {
            case .general: GeneralPane()
            case .appearance: AppearancePane()
            case .actions: ActionsPane()
            case .apps: AppsPane()
            case .advanced: AdvancedPane()
            case .about: AboutPane()
            }
        }
        .frame(minWidth: SettingsWindowController.minimumContentSize.width,
               maxWidth: .infinity,
               minHeight: SettingsWindowController.minimumContentSize.height,
               maxHeight: .infinity)
        .environmentObject(nav)
    }
}

/// Preference-style toolbar whose selected item drives `SettingsNavigator.pane`.
final class SettingsToolbarController: NSObject, NSToolbarDelegate {
    let nav: SettingsNavigator
    let toolbar: NSToolbar
    weak var window: NSWindow?
    private var cancellable: AnyCancellable?

    init(nav: SettingsNavigator, identifier: String) {
        self.nav = nav
        toolbar = NSToolbar(identifier: identifier)
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        cancellable = nav.$pane.sink { [weak self] pane in self?.apply(pane) }
    }

    func apply(_ pane: SettingsPane) {
        toolbar.selectedItemIdentifier = pane.toolbarIdentifier
        window?.title = pane.title
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarIdentifier == itemIdentifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.toolTip = pane.title
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) else { return }
        nav.pane = pane
    }
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    static let contentSize = NSSize(width: 760, height: 500)
    static let minimumContentSize = NSSize(width: 700, height: 440)

    private let nav = SettingsNavigator()
    private var toolbarController: SettingsToolbarController?
    private var window: NSWindow?

    func show(pane: SettingsPane? = nil) {
        if let pane { nav.pane = pane }
        let window = self.window ?? makeMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func show(extensionKey: String) {
        nav.selectedEntryKey = extensionKey
        show(pane: .actions)
    }

    private func makeMainWindow() -> NSWindow {
        let toolbar = SettingsToolbarController(nav: nav, identifier: "GlintSettingsToolbar")
        let window = Self.makeWindow(nav: nav, toolbar: toolbar)
        window.setFrameAutosaveName("GlintSettingsWindow")
        if !window.setFrameUsingName("GlintSettingsWindow") { window.center() }
        toolbarController = toolbar
        self.window = window
        return window
    }

    static func makeWindow(nav: SettingsNavigator, toolbar: SettingsToolbarController) -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsRootView(nav: nav))
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.setContentSize(contentSize)
        window.contentMinSize = minimumContentSize
        window.toolbar = toolbar.toolbar
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        toolbar.window = window
        toolbar.apply(nav.pane)
        return window
    }

    // MARK: - Snapshots

    /// Renders every pane (light and dark) to PNGs. Used by `--render-settings <dir>`.
    static func renderSnapshots(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let demo = demoEntry()
        // Tall variants show content below the fold of scrolling panes.
        let tall: CGFloat = 1060
        let scenarios: [(name: String, pane: SettingsPane, selection: String?, height: CGFloat)] = [
            ("general", .general, nil, contentSize.height),
            ("general-tall-untrusted", .general, nil, tall),
            ("appearance", .appearance, nil, contentSize.height),
            ("appearance-tall", .appearance, nil, tall),
            ("actions-extension", .actions, demo.key, contentSize.height),
            ("actions-extension-tall", .actions, demo.key, tall),
            ("actions-search", .actions, BuiltinID.search.key, contentSize.height),
            ("actions-speak", .actions, BuiltinID.speak.key, contentSize.height),
            ("actions-empty", .actions, nil, contentSize.height),
            ("apps", .apps, nil, contentSize.height),
            ("advanced", .advanced, nil, contentSize.height),
            ("about", .about, nil, contentSize.height),
            ("minimum-actions", .actions, demo.key, minimumContentSize.height),
            ("minimum-appearance", .appearance, nil, minimumContentSize.height),
        ]
        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

        for (suffix, appearanceName) in appearances {
            let appearance = NSAppearance(named: appearanceName)
            NSApp.appearance = appearance
            for scenario in scenarios {
                let nav = SettingsNavigator()
                nav.pane = scenario.pane
                nav.previewEntry = demo
                nav.selectedEntryKey = scenario.selection
                if scenario.name.hasSuffix("untrusted") { nav.previewAccessibilityTrusted = false }
                if scenario.name.hasPrefix("actions-extension") {
                    nav.previewLoadErrors = [
                        ("Broken.glintext", "The extension doesn't define any action (url, shell script, AppleScript, JavaScript, key combo, service or shortcut)."),
                        ("Old.popclipext", "Couldn't read the extension: Config.plist is missing."),
                    ]
                }
                let toolbar = SettingsToolbarController(nav: nav, identifier: "GlintSettingsSnapshot-\(UUID().uuidString)")
                let window = makeWindow(nav: nav, toolbar: toolbar)
                window.appearance = appearance
                let width = scenario.name.hasPrefix("minimum") ? minimumContentSize.width : contentSize.width
                window.setContentSize(NSSize(width: width, height: scenario.height))
                capture(window, to: directory.appendingPathComponent("\(scenario.name)-\(suffix).png"))
                window.close()
            }

            for (name, trusted) in [("onboarding", false), ("onboarding-granted", true)] {
                let window = OnboardingWindowController.makeWindow(content: OnboardingView(forcedTrusted: trusted, onDone: {}))
                window.appearance = appearance
                capture(window, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
                window.close()
            }

            let sheets: [(String, String)] = [
                ("snippet-empty", ""),
                ("snippet-valid", "#glint\nname: Search Wikipedia\nicon: symbol:book\nurl: https://en.wikipedia.org/w/index.php?search=***\n"),
                ("snippet-invalid", "#glint\nname: Broken\nicon: symbol:star\n"),
            ]
            for (name, text) in sheets {
                let hosting = NSHostingController(rootView: SnippetInstallSheet(initialText: text))
                let window = NSWindow(contentViewController: hosting)
                window.styleMask = [.titled, .fullSizeContentView]
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.appearance = appearance
                capture(window, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
                window.close()
            }
        }
        NSApp.appearance = nil
    }

    private static func capture(_ window: NSWindow, to url: URL) {
        window.setFrameOrigin(NSPoint(x: 60, y: 60))
        window.alphaValue = 0
        window.orderFrontRegardless()
        for _ in 0..<6 {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        }
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        let rect = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
        view.cacheDisplay(in: rect, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
    }

    /// An in-memory extension with one option of every kind, for the Actions snapshot.
    private static func demoEntry() -> RegistryEntry {
        let options: [OptionSpec] = [
            OptionSpec(id: "target", kind: .multiple, label: "Translate to",
                       description: "Language the selection is translated into.", defaultValue: "en",
                       values: ["en", "fr", "de", "ja"], valueLabels: ["English", "French", "German", "Japanese"]),
            OptionSpec(id: "replace", kind: .boolean, label: "Replace the selection", defaultValue: "0"),
            OptionSpec(id: "heading-account", kind: .heading, label: "Account",
                       description: "Needed only for the Pro service."),
            OptionSpec(id: "endpoint", kind: .string, label: "Server URL", description: "Leave empty for the public server.",
                       defaultValue: "https://api.example.com"),
            OptionSpec(id: "apikey", kind: .password, label: "API key"),
            OptionSpec(id: "token", kind: .secret, label: "Access token", description: "Saved securely in your keychain."),
        ]
        let actions = [
            ActionSpec(id: "0", title: "Translate", icon: "symbol:globe", kind: .url(template: "https://example.com/?q=***", alternateTemplate: nil),
                       description: "Opens the translation in your browser."),
            ActionSpec(id: "1", title: "Translate and Replace with a Very Long Action Title That Should Truncate Cleanly",
                       icon: "symbol:character.bubble", kind: .url(template: "https://example.com/?q=***", alternateTemplate: nil)),
        ]
        let manifest = ExtensionManifest(
            identifier: "dev.example.snapshot.translate-pro-with-a-long-identifier", name: "Translate Pro with an Extraordinarily Long Extension Name",
            icon: "symbol:globe", description: "Translates the selected text with the Example Translate service. Supports dozens of languages and can replace the selection in place.",
            author: "Example Author", homepage: "https://example.com/glint/translate-pro",
            options: options, actions: actions,
            bundleURL: URL(fileURLWithPath: "/tmp/TranslatePro.glintext", isDirectory: true))
        return RegistryEntry(key: manifest.identifier, source: .user(manifest))
    }
}

// MARK: - Onboarding

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    static let contentSize = NSSize(width: 560, height: 640)
    private var window: NSWindow?

    func show() {
        let window = self.window ?? {
            let w = Self.makeWindow(content: OnboardingView(onDone: { [weak self] in self?.finish() }))
            w.center()
            // Closing the window counts as finishing onboarding; it reappears at launch only while
            // Accessibility access is still missing.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                Preferences.shared.hasCompletedOnboarding = true
            }
            self.window = w
            return w
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func finish() {
        Preferences.shared.hasCompletedOnboarding = true
        window?.close()
        window = nil
    }

    static func makeWindow(content: OnboardingView) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.setContentSize(contentSize)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Glint"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        return window
    }
}
