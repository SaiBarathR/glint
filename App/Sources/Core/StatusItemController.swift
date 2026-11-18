import AppKit
import Combine

/// The menu bar icon and its menu.
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let prefs = Preferences.shared
    private var cancellables = Set<AnyCancellable>()
    /// The last app the user worked in (not Glint), for "Disable in …".
    var lastApp: NSRunningApplication?
    var onShowLog: (() -> Void)?

    func start() {
        prefs.$showMenuBarIcon.sink { [weak self] show in
            DispatchQueue.main.async { show ? self?.install() : self?.remove() }
        }.store(in: &cancellables)
        prefs.$enabled.sink { [weak self] _ in DispatchQueue.main.async { self?.updateIcon() } }.store(in: &cancellables)
    }

    private func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        updateIcon()
    }

    private func remove() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func updateIcon() {
        guard let button = item?.button else { return }
        let name = prefs.enabled ? "text.cursor" : "text.cursor"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Glint")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        img?.isTemplate = true
        button.image = img
        button.appearsDisabled = !prefs.enabled
        button.toolTip = prefs.enabled ? "Glint" : "Glint (paused)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(title: prefs.enabled ? "Pause Glint" : "Resume Glint", action: #selector(toggleEnabled),
                                keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        if let app = lastApp, let bid = app.bundleIdentifier, let name = app.localizedName {
            let excluded = prefs.isExcluded(bundleID: bid)
            let appItem = NSMenuItem(title: excluded ? "Enable in \(name)" : "Disable in \(name)",
                                     action: #selector(toggleApp(_:)), keyEquivalent: "")
            appItem.target = self
            appItem.representedObject = bid
            appItem.image = app.icon.map { icon in
                let i = icon.copy() as! NSImage
                i.size = NSSize(width: 16, height: 16)
                return i
            }
            menu.addItem(appItem)
        }

        if !Permissions.isAccessibilityTrusted {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
            warn.target = self
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings), ",")
        add(menu, "Extensions…", #selector(openExtensions), "")
        add(menu, "Extension Log", #selector(showLog), "")
        menu.addItem(.separator())
        add(menu, "About Glint", #selector(openAbout), "")
        add(menu, "Quit Glint", #selector(quit), "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, _ key: String) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        menu.addItem(i)
    }

    @objc private func toggleEnabled() { prefs.enabled.toggle() }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        if let i = prefs.excludedApps.firstIndex(of: bid) { prefs.excludedApps.remove(at: i) } else { prefs.excludedApps.append(bid) }
    }

    @objc private func grantAccess() {
        Permissions.promptForAccessibility()
        Permissions.openAccessibilitySettings()
    }
    @objc private func openSettings() { SettingsWindowController.shared.show(pane: .general) }
    @objc private func openExtensions() { SettingsWindowController.shared.show(pane: .actions) }
    @objc private func openAbout() { SettingsWindowController.shared.show(pane: .about) }
    @objc private func showLog() { onShowLog?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
