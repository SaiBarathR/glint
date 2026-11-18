import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Name and icon for a bundle ID, looked up once through NSWorkspace.
struct AppInfo {
    let bundleID: String
    let name: String
    let icon: NSImage
    let isInstalled: Bool

    private static var cache: [String: AppInfo] = [:]

    static func lookup(_ bundleID: String) -> AppInfo {
        if let hit = cache[bundleID] { return hit }
        let info: AppInfo
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            info = AppInfo(bundleID: bundleID, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                           icon: NSWorkspace.shared.icon(forFile: url.path), isInstalled: true)
        } else {
            info = AppInfo(bundleID: bundleID, name: bundleID,
                           icon: NSWorkspace.shared.icon(for: .applicationBundle), isInstalled: false)
        }
        cache[bundleID] = info
        return info
    }

    /// A copy of an icon sized for menus.
    static func menuIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

struct AppsPane: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var selection = Set<String>()
    @State private var runningApps: [RunningApp] = []

    struct RunningApp: Identifiable {
        let bundleID: String
        let name: String
        let icon: NSImage
        var id: String { bundleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Excluded Apps")
                        .font(.headline)
                    Text("Glint never appears in these apps, even when you select text. Password managers and other security apps are excluded by default.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ListBox {
                if prefs.excludedApps.isEmpty {
                    VStack(spacing: 6) {
                        Text("No excluded apps")
                            .foregroundStyle(.secondary)
                        Text("Click + to add one.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selection) {
                        ForEach(prefs.excludedApps, id: \.self) { bundleID in
                            AppRow(info: AppInfo.lookup(bundleID))
                                .tag(bundleID)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .onDeleteCommand(perform: removeSelected)
                }
            } bar: {
                addMenu
                BarDivider()
                BarIconButton(systemImage: "minus", help: "Remove the selected apps", action: removeSelected)
                    .disabled(selection.isEmpty)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshRunningApps)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshRunningApps()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshRunningApps()
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Choose Application…", action: chooseApplications)
            let candidates = runningApps.filter { !prefs.excludedApps.contains($0.bundleID) }
            if !candidates.isEmpty {
                Divider()
                Section("Running Apps") {
                    ForEach(candidates) { app in
                        Button {
                            add([app.bundleID])
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: AppInfo.menuIcon(app.icon))
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 22)
        .help("Add an app")
    }

    private func refreshRunningApps() {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, id != own, seen.insert(id).inserted else { return nil }
                return RunningApp(bundleID: id, name: app.localizedName ?? id,
                                  icon: app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "Exclude Apps"
        panel.prompt = "Exclude"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            add(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private func add(_ ids: [String]) {
        let new = ids.filter { !prefs.excludedApps.contains($0) }
        guard !new.isEmpty else { return }
        prefs.excludedApps.append(contentsOf: new)
        selection = Set(new)
    }

    private func removeSelected() {
        guard !selection.isEmpty else { return }
        prefs.excludedApps.removeAll { selection.contains($0) }
        selection.removeAll()
    }
}

private struct AppRow: View {
    let info: AppInfo

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if info.isInstalled {
                    Image(nsImage: info.icon)
                        .resizable()
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .fontWeight(.light)
                        .foregroundStyle(.tertiary)
                        .padding(2)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(info.isInstalled ? info.bundleID : "Not installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
