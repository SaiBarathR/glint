import AppKit
import AVFoundation
import GlintCore
import SwiftUI

/// Option values for one extension, cached so typing in a field doesn't re-read every value.
final class OptionValuesModel: ObservableObject {
    let manifest: ExtensionManifest?
    @Published private(set) var values: [String: String]

    init(manifest: ExtensionManifest?) {
        self.manifest = manifest
        values = manifest.map { Preferences.shared.optionValues(for: $0) } ?? [:]
    }

    func binding(_ id: String) -> Binding<String> {
        Binding(
            get: { self.values[id] ?? "" },
            set: { newValue in
                guard let manifest = self.manifest, self.values[id] != newValue else { return }
                self.values[id] = newValue
                Preferences.shared.setOption(newValue, id: id, for: manifest)
            }
        )
    }
}

struct ExtensionDetailView: View {
    let entry: RegistryEntry
    var onUninstall: () -> Void

    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var registry = ActionRegistry.shared
    @StateObject private var options: OptionValuesModel

    init(entry: RegistryEntry, onUninstall: @escaping () -> Void) {
        self.entry = entry
        self.onUninstall = onUninstall
        _options = StateObject(wrappedValue: OptionValuesModel(manifest: entry.manifest))
    }

    var body: some View {
        Form {
            headerSection

            if entry.builtin == .search { searchSection }
            if entry.builtin == .speak { speechSection }

            if let manifest = entry.manifest {
                ForEach(OptionGroup.groups(for: manifest.options)) { group in
                    Section {
                        if let note = group.note {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.options) { option in
                            OptionRow(option: option, value: options.binding(option.id))
                        }
                    } header: {
                        Text(group.title)
                    }
                }
                actionsSection(manifest)
            }

            if entry.builtin != .installExtension { shortcutSection }

            if entry.isUserInstalled || entry.manifest?.bundleURL != nil { manageSection }
        }
        .formStyle(.grouped)
    }

    // MARK: Header

    private var kindLabel: String {
        switch entry.source {
        case .builtin: return "Built-in action"
        case .bundled: return "Included with Glint"
        case .user: return "Installed by you"
        }
    }

    private var descriptionText: String? {
        if let builtin = entry.builtin { return builtin.summary }
        if let d = entry.manifest?.description, !d.isEmpty { return d }
        return nil
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                SpecIcon(entry: entry, size: 22)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(kindLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Toggle("Show on the bar", isOn: Binding(
                    get: { registry.isEnabled(entry.key) },
                    set: { registry.setEnabled(entry.key, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .help("Show this action on the bar")
            }
            .padding(.vertical, 2)

            if let descriptionText {
                Text(descriptionText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let author = entry.manifest?.author, !author.isEmpty {
                LabeledContent("Author") {
                    Text(author)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
            if let homepage = entry.manifest?.homepage, let url = URL(string: homepage), url.scheme != nil {
                LabeledContent("Website") {
                    Link(destination: url) {
                        Text(url.host ?? homepage)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(homepage)
                }
            }
            if let manifest = entry.manifest {
                LabeledContent("Identifier") {
                    Text(manifest.identifier)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: Built-in specifics

    private var searchSection: some View {
        Section {
            Picker("Search engine", selection: $prefs.searchEngineID) {
                ForEach(Preferences.SearchEngine.all) { engine in
                    Text(engine.id == "custom" ? "Custom" : engine.name).tag(engine.id)
                }
            }
            if prefs.searchEngineID == "custom" {
                TextField(text: $prefs.customSearchTemplate, prompt: Text(verbatim: "https://example.com/search?q=***")) {
                    Text("URL template")
                    Text(verbatim: "*** is replaced by the selected text.")
                }
                .autocorrectionDisabled()
            } else if let template = Preferences.SearchEngine.all.first(where: { $0.id == prefs.searchEngineID })?.template {
                LabeledContent("URL") {
                    Text(template)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Search Engine")
        }
    }

    private var speechSection: some View {
        Section {
            Picker("Voice", selection: $prefs.speechVoiceID) {
                Text("System Default").tag("")
                Divider()
                ForEach(VoiceCatalog.preferred, id: \.identifier) { voice in
                    Text(VoiceCatalog.label(voice)).tag(voice.identifier)
                }
                if !VoiceCatalog.others.isEmpty {
                    Divider()
                    ForEach(VoiceCatalog.others, id: \.identifier) { voice in
                        Text(VoiceCatalog.label(voice)).tag(voice.identifier)
                    }
                }
            }
            LabeledContent("Speaking rate") {
                HStack(spacing: 8) {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $prefs.speechRate, in: 0...1)
                        .frame(width: 150)
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Play Sample") {
                    VoiceCatalog.toggleSample(voiceID: prefs.speechVoiceID, rate: prefs.speechRate)
                }
            }
        } header: {
            Text("Voice")
        }
    }

    // MARK: Extension specifics

    @ViewBuilder
    private func actionsSection(_ manifest: ExtensionManifest) -> some View {
        Section {
            if manifest.actions.isEmpty {
                Text("This extension's actions are defined by its JavaScript module.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(manifest.actions.enumerated()), id: \.offset) { _, action in
                HStack(alignment: .center, spacing: 10) {
                    SpecIcon(spec: action.icon, baseURL: manifest.bundleURL, size: 16, fallbackTitle: action.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TitleAndSubtitle(title: action.title, subtitle: action.description)
                    Spacer(minLength: 0)
                }
            }
        } header: {
            Text(manifest.actions.count == 1 ? "Action" : "Actions")
        }
    }

    private var shortcutSection: some View {
        Section {
            LabeledContent {
                HotKeyRecorder(combo: Binding(
                    get: { prefs.actionHotKeys[entry.key] },
                    set: { prefs.actionHotKeys[entry.key] = $0 }
                ))
            } label: {
                Text("Keyboard shortcut")
                Text("Runs \(firstActionTitle) on the current selection, from any app.")
            }
        }
    }

    private var firstActionTitle: String {
        entry.manifest?.actions.first?.title ?? entry.name
    }

    private var manageSection: some View {
        Section {
            HStack(spacing: 8) {
                if let url = entry.manifest?.bundleURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Spacer()
                if entry.isUserInstalled {
                    Button("Uninstall…", role: .destructive, action: onUninstall)
                }
            }
        }
    }
}

// MARK: - Options form

struct OptionGroup: Identifiable {
    let id: String
    let title: String
    let note: String?
    var options: [OptionSpec]

    static func groups(for options: [OptionSpec]) -> [OptionGroup] {
        var groups = [OptionGroup(id: "_options", title: "Options", note: nil, options: [])]
        for option in options where !option.hidden {
            if option.kind == .heading {
                groups.append(OptionGroup(id: "heading." + option.id, title: option.label,
                                          note: option.description, options: []))
            } else {
                groups[groups.count - 1].options.append(option)
            }
        }
        return groups.filter { !$0.options.isEmpty || $0.note != nil }
    }
}

struct OptionRow: View {
    let option: OptionSpec
    @Binding var value: String

    var body: some View {
        Group {
            switch option.kind {
            case .string:
                TextField(text: $value, prompt: Text(option.defaultValue ?? "")) { label }
                    .autocorrectionDisabled()
            case .password, .secret:
                SecureField(text: $value, prompt: Text("Not set")) { label }
            case .boolean:
                Toggle(isOn: Binding(
                    get: { ["1", "true", "yes"].contains(value.lowercased()) },
                    set: { value = $0 ? "1" : "0" }
                )) { label }
            case .multiple:
                Picker(selection: $value) {
                    ForEach(Array(option.values.enumerated()), id: \.offset) { index, v in
                        Text(displayLabel(index)).tag(v)
                    }
                } label: { label }
            case .heading:
                EmptyView()
            }
        }
        .padding(.leading, option.inset ? 16 : 0)
    }

    private func displayLabel(_ index: Int) -> String {
        if option.valueLabels.count == option.values.count, !option.valueLabels[index].isEmpty {
            return option.valueLabels[index]
        }
        return option.values[index]
    }

    @ViewBuilder
    private var label: some View {
        Text(option.label)
        if let description = option.description, !description.isEmpty {
            Text(description)
        }
    }
}

// MARK: - Voices

enum VoiceCatalog {
    private static let all: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices().sorted {
        let a = languageName($0), b = languageName($1)
        return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                      : a.localizedStandardCompare(b) == .orderedAscending
    }

    private static var currentLanguage: String { Locale.current.language.languageCode?.identifier ?? "en" }

    /// Voices in the user's language, shown first.
    static let preferred: [AVSpeechSynthesisVoice] = all.filter { $0.language.hasPrefix(currentLanguage) }
    static let others: [AVSpeechSynthesisVoice] = all.filter { !$0.language.hasPrefix(currentLanguage) }

    static func languageName(_ voice: AVSpeechSynthesisVoice) -> String {
        Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = ", Premium"
        case .enhanced: quality = ", Enhanced"
        default: quality = ""
        }
        return "\(voice.name) (\(languageName(voice))\(quality))"
    }

    private static let synthesizer = AVSpeechSynthesizer()

    static func toggleSample(voiceID: String, rate: Double) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        let utterance = AVSpeechUtterance(string: "Glint reads the selected text aloud, like this.")
        if !voiceID.isEmpty { utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID) }
        utterance.rate = Float(rate)
        synthesizer.speak(utterance)
    }
}
