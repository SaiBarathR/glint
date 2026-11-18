import AppKit
import Combine
import GlintCore

final class AppDelegate: NSObject, NSApplicationDelegate, SelectionMonitorDelegate {
    private let prefs = Preferences.shared
    private let monitor = SelectionMonitor()
    private let statusItem = StatusItemController()
    private let popup = PopupController.shared
    private let performer = ActionPerformer.shared
    private var cancellables = Set<AnyCancellable>()
    private var pendingCapture: Task<Void, Never>?
    private var lastShownText: String?
    private var lastShownAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = argumentValue("--render-settings") {
            SettingsWindowController.renderSnapshots(to: URL(fileURLWithPath: dir))
            exit(0)
        }
        if let dir = argumentValue("--render-bar") {
            BarSnapshots.render(to: URL(fileURLWithPath: dir))
            exit(0)
        }
        _ = ActionRegistry.shared
        if let text = argumentValue("--demo-bar") {
            // Debug aid: show the real bar for a fake selection at the screen centre.
            popup.onAction = { [weak self] action, flags in self?.performer.perform(action, flags: flags) }
            let f = NSScreen.main?.visibleFrame ?? .zero
            let ctx = SelectionContext(text: text, appBundleID: "com.apple.TextEdit", appName: "TextEdit", canCut: true,
                                       canPaste: true, canFormat: true, clipboardText: "clip")
            let sel = CapturedSelection(context: ctx, anchor: CGRect(x: f.midX - 40, y: f.midY, width: 80, height: 16),
                                        isPasteOnly: false)
            performer.selection = sel
            popup.show(actions: ActionBuilder.actions(for: sel), anchor: sel.anchor)
            return
        }
        popup.onAction = { [weak self] action, flags in self?.performer.perform(action, flags: flags) }
        monitor.delegate = self
        monitor.start()
        statusItem.start()
        statusItem.onShowLog = { LogWindow.shared.show() }
        trackFrontmostApp()
        observeHotKeys()

        if !Permissions.isAccessibilityTrusted || !prefs.hasCompletedOnboarding {
            OnboardingWindowController.shared.show()
        }
        if !Permissions.isAccessibilityTrusted {
            // Global key monitors only work once trusted; restart them when access is granted.
            Permissions.waitForAccessibility { [weak self] in self?.monitor.start() }
        }
    }

    /// Launching the app again (e.g. from Finder) opens settings — useful when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show(pane: .general)
        return true
    }

    // MARK: Opening extensions & URLs

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "glint" { handleURL(url); continue }
            guard url.isFileURL else { continue }
            installBundle(at: url)
        }
    }

    private func installBundle(at original: URL) {
        var url = original
        do {
            // Zipped packages (.glintextz / .popclipextz): expand first.
            if ["glintextz", "popclipextz", "zip"].contains(url.pathExtension.lowercased()) {
                url = try Self.unzipExtension(url)
            }
            let manifest = try ExtensionLoader.loadBundle(at: url)
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Install “\(manifest.name)”?"
            let kinds = manifest.actions.map(\.title).joined(separator: ", ")
            alert.informativeText = "\(manifest.description ?? "")\n\nActions: \(kinds)\n\nOnly install extensions from people you trust: they can run scripts on your Mac."
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                try ActionRegistry.shared.install(bundleAt: url)
                SettingsWindowController.shared.show(extensionKey: manifest.identifier)
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    static func unzipExtension(_ zip: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("glint-unzip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        if let bundle = items.first(where: { ["glintext", "popclipext"].contains($0.pathExtension.lowercased()) }) { return bundle }
        if items.count == 1 { return items[0] }
        return dir
    }

    /// glint://install?snippet=<url-encoded snippet>, glint://settings, glint://pause, glint://resume
    private func handleURL(_ url: URL) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.host {
        case "install":
            guard let snippet = comps?.queryItems?.first(where: { $0.name == "snippet" })?.value else { return }
            NSApp.activate(ignoringOtherApps: true)
            do {
                let m = try ExtensionLoader.parseSnippet(snippet)
                let alert = NSAlert()
                alert.messageText = "Install “\(m.name)”?"
                alert.informativeText = "Only install extensions from people you trust: they can run scripts on your Mac."
                alert.addButton(withTitle: "Install")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    try ActionRegistry.shared.install(snippet: snippet)
                    SettingsWindowController.shared.show(extensionKey: m.identifier)
                }
            } catch { NSAlert(error: error).runModal() }
        case "pause": prefs.enabled = false
        case "resume": prefs.enabled = true
        default: SettingsWindowController.shared.show(pane: .general)
        }
    }

    // MARK: Hotkeys

    private func observeHotKeys() {
        prefs.$showBarHotKey.combineLatest(prefs.$actionHotKeys)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] showBar, actionKeys in self?.registerHotKeys(showBar: showBar, actionKeys: actionKeys) }
            .store(in: &cancellables)
    }

    private func registerHotKeys(showBar: KeyCombo?, actionKeys: [String: KeyCombo]) {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        if let showBar,
           !center.register(showBar, handler: { [weak self] in self?.capture(trigger: .hotKey, mouse: NSEvent.mouseLocation, iBeam: false) }) {
            performer.log("The show-bar shortcut \(showBar) is used by another app and couldn't be registered.", extensionID: "glint")
        }
        for (key, combo) in actionKeys.sorted(by: { $0.key < $1.key }) {
            if !center.register(combo, handler: { [weak self] in self?.runActionHotKey(key) }) {
                performer.log("Shortcut \(combo) for \(key) is already in use and couldn't be registered.", extensionID: "glint")
            }
        }
    }

    private func runActionHotKey(_ key: String) {
        pendingCapture?.cancel()
        pendingCapture = Task { @MainActor [weak self] in
            await self?.waitForModifierRelease()
            guard let sel = await SelectionReader.capture(mouse: nil, allowCopyFallback: true) else { NSSound.beep(); return }
            self?.performer.performFirstAction(of: key, selection: sel)
        }
    }

    /// Waits (up to 0.5 s) for the hotkey's modifier keys to be released so they don't alter our ⌘C / ⌘V.
    @MainActor private func waitForModifierRelease() async {
        for _ in 0..<20 where !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    // MARK: Selection → bar

    func selectionMonitor(_ monitor: SelectionMonitor, didDetect trigger: SelectionTrigger, at mouse: CGPoint, iBeam: Bool) {
        capture(trigger: trigger, mouse: mouse, iBeam: iBeam)
    }

    private func capture(trigger: SelectionTrigger, mouse: CGPoint, iBeam: Bool) {
        guard prefs.enabled || trigger == .hotKey else { return }
        pendingCapture?.cancel()
        pendingCapture = Task { @MainActor [weak self] in
            guard let self else { return }
            if trigger == .hotKey { await self.waitForModifierRelease() }
            // Give the app a moment to update its selection (and honour the user's delay).
            let delay = max(trigger == .hotKey ? 0.0 : 0.06, prefs.popupDelay)
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            if Task.isCancelled { return }
            if trigger.isMouse, trigger != .longPress, NSEvent.pressedMouseButtons & 1 != 0 { return }
            // ⌘C fallback only when the drag looked like a text selection, to avoid copying files or drawings.
            let allowFallback = trigger == .hotKey || trigger == .keyboard || iBeam
            guard let sel = await SelectionReader.capture(mouse: trigger.isMouse ? mouse : nil,
                                                          allowCopyFallback: allowFallback,
                                                          pasteOnly: trigger == .longPress,
                                                          requireNearMouse: trigger.isMouse && !iBeam) else { return }
            if Task.isCancelled { return }
            // Re-clicking an already-shown selection shouldn't flash the bar again.
            if trigger == .shiftClick, sel.context.text == lastShownText, Date().timeIntervalSince(lastShownAt) < 0.5 { return }
            let actions = ActionBuilder.actions(for: sel)
            guard !actions.isEmpty else { return }
            performer.selection = sel
            lastShownText = sel.context.text
            lastShownAt = Date()
            popup.show(actions: actions, anchor: sel.anchor)
        }
    }

    func selectionMonitorShouldDismiss(_ monitor: SelectionMonitor, reason: SelectionMonitor.DismissReason) {
        // Any new input means the user moved on: drop a capture that hasn't shown its bar yet.
        pendingCapture?.cancel()
        if reason != .scroll { performer.cancelPendingClick() }
        popup.dismiss()
    }

    func selectionMonitor(_ monitor: SelectionMonitor, mouseMovedTo point: CGPoint) {
        popup.mouseMoved(to: point)
    }

    func selectionMonitor(_ monitor: SelectionMonitor, modifiersChanged flags: NSEvent.ModifierFlags) {}

    // MARK: Helpers

    private func trackFrontmostApp() {
        statusItem.lastApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.statusItem.lastApp = app
        }
    }

    private func argumentValue(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
