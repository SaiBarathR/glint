import AppKit
import GlintCore
import SwiftUI

/// Sheet for pasting an extension snippet. Validates live and installs into the user extensions folder.
struct SnippetInstallSheet: View {
    var initialText = ""
    var onInstalled: (ExtensionManifest) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var installError: String?
    @State private var didLoadInitial = false

    private enum Validation {
        case empty
        case valid(ExtensionManifest)
        case invalid(String)
    }

    /// Recomputed when the text changes (not on every render: parsing may spawn the YAML helper).
    @State private var validation: Validation = .empty
    @State private var validatedText: String?

    private static func validate(_ text: String) -> Validation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        do {
            return .valid(try ExtensionLoader.parseSnippet(text))
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    private func revalidate() {
        guard validatedText != text else { return }
        validatedText = text
        validation = Self.validate(text)
    }

    var body: some View {
        content
            .onAppear(perform: revalidate)
            .onChange(of: text) { _, _ in revalidate() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paste Extension Snippet")
                    .font(.headline)
                Text("A snippet starts with a #glint or #popclip line, followed by its settings in YAML.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CodeTextView(text: $text)
                .frame(minHeight: 200, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(verbatim: "#glint\nname: Search Wikipedia\nurl: https://en.wikipedia.org/w/index.php?search=***")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            statusRow
                .frame(minHeight: 34, alignment: .top)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Install") { install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 540, height: 440)
        .onAppear {
            if !didLoadInitial { text = initialText; didLoadInitial = true }
        }
        .onChange(of: text) { installError = nil }
    }

    private var isValid: Bool {
        if case .valid = validation { return true }
        return false
    }

    @ViewBuilder
    private var statusRow: some View {
        if let installError {
            status(icon: "xmark.octagon.fill", color: .red, text: installError)
        } else {
            switch validation {
            case .empty:
                status(icon: "doc.on.clipboard", color: .secondary, text: "Paste a snippet to check it.")
            case .valid(let manifest):
                let count = manifest.actions.count
                let detail = manifest.moduleSource != nil && count == 0 ? "JavaScript module"
                    : count == 1 ? "1 action" : "\(count) actions"
                status(icon: "checkmark.circle.fill", color: .green, text: "Ready to install “\(manifest.name)” (\(detail)).")
            case .invalid(let message):
                status(icon: "exclamationmark.triangle.fill", color: .orange, text: message)
            }
        }
    }

    private func status(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
                .foregroundStyle(color == .secondary ? Color.secondary : Color.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func install() {
        do {
            let manifest = try ActionRegistry.shared.install(snippet: text)
            onInstalled(manifest)
            dismiss()
        } catch {
            installError = error.localizedDescription
        }
    }
}

/// A monospaced plain-text editor with smart quotes, dashes and autocorrect turned off (they break YAML and code).
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
