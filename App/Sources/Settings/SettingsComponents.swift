import AppKit
import Combine
import GlintCore
import SwiftUI

/// An icon from an icon spec (see `IconRenderer`), tinted with the current foreground style when it's a template.
struct SpecIcon: View {
    let spec: String?
    var baseURL: URL?
    var size: CGFloat
    var fallbackTitle: String

    var body: some View {
        if let image = IconRenderer.image(for: spec, baseURL: baseURL, size: size, fallbackTitle: fallbackTitle) {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "questionmark.square.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }
}

extension SpecIcon {
    init(entry: RegistryEntry, size: CGFloat) {
        self.init(spec: entry.icon, baseURL: entry.iconBaseURL, size: size, fallbackTitle: entry.name)
    }
}

/// The classic macOS bordered list with a +/− button bar attached to its bottom edge.
struct ListBox<Content: View, Bar: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var bar: Bar

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 0) {
                bar
            }
            .frame(height: 24)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// A small borderless icon button for a `ListBox` bar.
struct BarIconButton: View {
    let systemImage: String
    let help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Thin vertical divider used between bar buttons.
struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 14)
    }
}

/// A row label with a secondary description underneath (for custom rows that don't get Form's automatic subtitle).
struct TitleAndSubtitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Accessibility permission status with a Grant button. Polls while visible.
struct AccessibilityStatusRow: View {
    /// Overrides the live status (snapshots).
    var forcedStatus: Bool?
    @State private var trusted = Permissions.isAccessibilityTrusted
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var isTrusted: Bool { forcedStatus ?? trusted }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(isTrusted ? Color.green : Color.orange)
                .frame(width: 22)
            TitleAndSubtitle(
                title: isTrusted ? "Accessibility access is on" : "Accessibility access is off",
                subtitle: isTrusted
                    ? "Glint can read your selection and show the bar next to it."
                    : "Glint needs Accessibility access to read the selected text and show the bar."
            )
            Spacer(minLength: 8)
            if !isTrusted {
                Button("Grant Access…") {
                    Permissions.promptForAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
        }
        .padding(.vertical, 2)
        .onReceive(timer) { _ in
            let now = Permissions.isAccessibilityTrusted
            if now != trusted { trusted = now }
        }
    }
}

/// Simple identifiable alert message.
struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension View {
    func alert(_ message: Binding<AlertMessage?>) -> some View {
        alert(message.wrappedValue?.title ?? "", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        ), presenting: message.wrappedValue) { _ in
            Button("OK", role: .cancel) {}
        } message: { m in
            Text(m.message)
        }
    }
}
