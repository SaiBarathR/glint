import AppKit
import GlintCore
import SwiftUI
import UniformTypeIdentifiers

struct ActionsPane: View {
    @EnvironmentObject private var nav: SettingsNavigator
    @ObservedObject private var registry = ActionRegistry.shared

    @State private var showingSnippetSheet = false
    @State private var uninstallCandidate: RegistryEntry?
    @State private var dismissedErrorsSignature: String?
    @State private var alertMessage: AlertMessage?

    /// Registry entries, plus the in-memory demo entry used by snapshots.
    private var entries: [RegistryEntry] {
        var list = registry.entries
        if let demo = nav.previewEntry, !list.contains(where: { $0.key == demo.key }) {
            list.insert(demo, at: min(4, list.count))
        }
        return list
    }

    private var loadErrors: [(name: String, message: String)] {
        nav.previewLoadErrors ?? registry.loadErrors
    }

    private var errorsSignature: String {
        loadErrors.map { "\($0.name)|\($0.message)" }.joined(separator: "\n")
    }

    private var selectedEntry: RegistryEntry? {
        guard let key = nav.selectedEntryKey else { return nil }
        return entries.first { $0.key == key }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if !loadErrors.isEmpty && dismissedErrorsSignature != errorsSignature {
                    LoadErrorsBanner(errors: loadErrors) { dismissedErrorsSignature = errorsSignature }
                }
                ListBox {
                    entryList
                } bar: {
                    addMenu
                    BarDivider()
                    BarIconButton(systemImage: "minus", help: "Uninstall the selected extension") {
                        if let e = selectedEntry, e.isUserInstalled { uninstallCandidate = e }
                    }
                    .disabled(!(selectedEntry?.isUserInstalled ?? false))
                    Spacer(minLength: 8)
                    Text("Drag to reorder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.trailing, 8)
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.vertical, 20)
            .frame(width: 312)

            Divider()

            Group {
                if let entry = selectedEntry {
                    ExtensionDetailView(entry: entry) { uninstallCandidate = entry }
                        // Rebuild when the extension is reloaded with different options.
                        .id(entry.key + "|" + (entry.manifest?.options.map { "\($0.id):\($0.kind.rawValue)" }.joined(separator: ",") ?? ""))
                } else {
                    emptyDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingSnippetSheet) {
            SnippetInstallSheet { manifest in
                nav.selectedEntryKey = manifest.identifier
            }
        }
        .alert(uninstallTitle, isPresented: Binding(
            get: { uninstallCandidate != nil },
            set: { if !$0 { uninstallCandidate = nil } }
        ), presenting: uninstallCandidate) { entry in
            Button("Move to Trash", role: .destructive) {
                if nav.selectedEntryKey == entry.key { nav.selectedEntryKey = nil }
                registry.uninstall(entry.key)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The extension is moved to the Trash, and its shortcut is removed.")
        }
        .alert($alertMessage)
    }

    private var uninstallTitle: String {
        "Uninstall “\(uninstallCandidate?.name ?? "")”?"
    }

    // MARK: List

    private var entryList: some View {
        List(selection: $nav.selectedEntryKey) {
            ForEach(entries) { entry in
                EntryRow(entry: entry)
                    .tag(entry.key)
                    .moveDisabled(entry.builtin == .installExtension)
            }
            .onMove(perform: move)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 40)
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard nav.previewEntry == nil else { return }
        var destination = destination
        // "Install Extension" stays pinned to the top.
        if registry.entries.first?.builtin == .installExtension { destination = max(1, destination) }
        registry.move(fromOffsets: source, toOffset: destination)
    }

    private var addMenu: some View {
        Menu {
            Button("Install from File…", action: installFromFile)
            Button("Paste Snippet…") { showingSnippetSheet = true }
            Divider()
            Button("Open Extensions Folder") {
                NSWorkspace.shared.open(ActionRegistry.userExtensionsDirectory)
            }
            Button("Reload Extensions") {
                dismissedErrorsSignature = nil
                registry.reload()
            }
            Divider()
            Button("Reset Order") { registry.resetOrder() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 30, height: 22)
        .help("Add an extension")
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Select an action to see its settings")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Switch actions on or off, drag them to change their order on the bar, or add extensions with the + button.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(24)
    }

    // MARK: Install

    private func installFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Install Extension"
        panel.message = "Choose a Glint or PopClip extension (.glintext, .popclipext, or a zipped .glintextz / .popclipextz)."
        panel.prompt = "Install"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            install(urls: panel.urls)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private func install(urls: [URL]) {
        var failures: [String] = []
        var lastInstalled: String?
        for original in urls {
            var url = original
            let ext = url.pathExtension.lowercased()
            let zipped = ["glintextz", "popclipextz", "zip"].contains(ext)
            guard ExtensionLoader.bundleExtensions.contains(ext) || zipped else {
                failures.append("“\(url.lastPathComponent)” isn't a Glint or PopClip extension.")
                continue
            }
            do {
                if zipped { url = try AppDelegate.unzipExtension(url) }
                lastInstalled = try registry.install(bundleAt: url).identifier
            } catch {
                failures.append("“\(url.lastPathComponent)”: \(error.localizedDescription)")
            }
        }
        if let lastInstalled { nav.selectedEntryKey = lastInstalled }
        if !failures.isEmpty {
            alertMessage = AlertMessage(title: failures.count == 1 ? "Couldn't install the extension"
                                                                   : "Couldn't install \(failures.count) extensions",
                                        message: failures.joined(separator: "\n\n"))
        }
    }
}

// MARK: - Row

private struct EntryRow: View {
    let entry: RegistryEntry
    @ObservedObject private var registry = ActionRegistry.shared

    var body: some View {
        let enabled = registry.isEnabled(entry.key)
        HStack(spacing: 10) {
            SpecIcon(entry: entry, size: 18)
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .opacity(enabled ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if entry.isUserInstalled {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .help("Installed by you")
                    }
                }
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .opacity(enabled ? 1 : 0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Enabled", isOn: Binding(
                get: { registry.isEnabled(entry.key) },
                set: { registry.setEnabled(entry.key, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 3)
        .help(entry.summary)
    }
}

// MARK: - Load errors

private struct LoadErrorsBanner: View {
    let errors: [(name: String, message: String)]
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(errors.count == 1 ? "1 extension couldn't be loaded" : "\(errors.count) extensions couldn't be loaded")
                    .font(.callout.weight(.semibold))
                ForEach(Array(errors.prefix(3).enumerated()), id: \.offset) { _, error in
                    Text("\(error.name): \(error.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                if errors.count > 3 {
                    Text("and \(errors.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
        .help(errors.map { "\($0.name): \($0.message)" }.joined(separator: "\n"))
    }
}
