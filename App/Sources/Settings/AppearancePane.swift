import AppKit
import SwiftUI

struct AppearancePane: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                BarPreview()
            } header: {
                Text("Preview")
            }

            Section("Bar") {
                LabeledContent("Show") {
                    Picker("Show", selection: $prefs.displayMode) {
                        Text("Icons").tag(Preferences.DisplayMode.iconsOnly)
                        Text("Text").tag(Preferences.DisplayMode.textOnly)
                        Text("Icons and Text").tag(Preferences.DisplayMode.iconsAndText)
                    }
                    .segmentedStyle()
                }
                LabeledContent("Size") {
                    Picker("Size", selection: $prefs.barSize) {
                        Text("Small").tag(Preferences.BarSize.small)
                        Text("Medium").tag(Preferences.BarSize.medium)
                        Text("Large").tag(Preferences.BarSize.large)
                    }
                    .segmentedStyle()
                }
                LabeledContent("Theme") {
                    Picker("Theme", selection: $prefs.theme) {
                        Text("Match System").tag(Preferences.Theme.system)
                        Text("Light").tag(Preferences.Theme.light)
                        Text("Dark").tag(Preferences.Theme.dark)
                    }
                    .segmentedStyle()
                }
                LabeledContent("Position") {
                    Picker("Position", selection: $prefs.position) {
                        Text("Above Selection").tag(Preferences.Position.above)
                        Text("Below Selection").tag(Preferences.Position.below)
                    }
                    .segmentedStyle()
                }
            }

            Section("Behavior") {
                Toggle(isOn: $prefs.showHoverLabels) {
                    Text("Show labels on hover")
                    Text("Shows an action's name when you point at its icon.")
                }
                Toggle(isOn: $prefs.dismissWhenMouseLeaves) {
                    Text("Hide when the mouse moves away")
                    Text("Otherwise the bar stays until you click elsewhere or press Esc.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private extension View {
    func segmentedStyle() -> some View {
        pickerStyle(.segmented).labelsHidden().fixedSize()
    }
}

/// A static drawing of the action bar that follows the Appearance settings. Preview only.
struct BarPreview: View {
    /// Draw without the surrounding "document" backdrop.
    var showsBackdrop = true
    var maxItems = 5

    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var registry = ActionRegistry.shared
    @Environment(\.colorScheme) private var colorScheme

    private struct Metrics {
        var icon: CGFloat, font: CGFloat, height: CGFloat, hPad: CGFloat, radius: CGFloat
    }

    private var metrics: Metrics {
        switch prefs.barSize {
        case .small: return Metrics(icon: 14, font: 12, height: 26, hPad: 8, radius: 7)
        case .medium: return Metrics(icon: 16, font: 13, height: 31, hPad: 10, radius: 8)
        case .large: return Metrics(icon: 19, font: 15, height: 37, hPad: 12, radius: 10)
        }
    }

    private var isDark: Bool {
        switch prefs.theme {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    private var foreground: Color { isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.82) }
    private var barFill: Color { isDark ? Color(white: 0.17) : Color(white: 0.985) }
    private var barStroke: Color { isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.13) }

    private var items: [RegistryEntry] {
        Array(registry.entries
            .filter { $0.builtin != .installExtension && registry.isEnabled($0.key) }
            .prefix(maxItems))
    }

    private var showsHoverLabel: Bool {
        prefs.showHoverLabels && prefs.displayMode == .iconsOnly && !items.isEmpty
    }

    var body: some View {
        let content = VStack(spacing: 6) {
            if prefs.position == .above {
                labelSpace
                bar
                sampleText
            } else {
                sampleText
                bar
                labelSpace
            }
        }
        .frame(maxWidth: .infinity)

        if showsBackdrop {
            content
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of the action bar")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of the action bar")
        }
    }

    private var sampleText: some View {
        var before = AttributedString("Select ")
        before.foregroundColor = .primary
        var selected = AttributedString("any text")
        selected.backgroundColor = Color.accentColor.opacity(0.28)
        selected.foregroundColor = .primary
        var after = AttributedString(" and the bar appears.")
        after.foregroundColor = .primary
        return Text(before + selected + after)
            .font(.system(size: 13))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    /// Room reserved for the hover label so the preview doesn't jump when it's toggled.
    private var labelSpace: some View {
        Color.clear.frame(width: 1, height: 20)
    }

    private var hoverLabel: some View {
        Text(items.first?.name ?? "")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(barFill))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(barStroke, lineWidth: 1))
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.12), radius: 2, y: 1)
            .fixedSize()
    }

    private var bar: some View {
        HStack(spacing: 0) {
            if items.isEmpty {
                Text("No actions enabled")
                    .font(.system(size: metrics.font))
                    .foregroundStyle(foreground.opacity(0.7))
                    .padding(.horizontal, metrics.hPad + 4)
                    .frame(height: metrics.height)
            }
            ForEach(Array(items.enumerated()), id: \.element.key) { index, entry in
                if index > 0 {
                    Rectangle()
                        .fill(foreground.opacity(0.2))
                        .frame(width: 1, height: metrics.height * 0.48)
                }
                if index == 0 && showsHoverLabel {
                    item(entry)
                        .padding(.horizontal, metrics.hPad)
                        .frame(height: metrics.height)
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: metrics.radius, bottomLeadingRadius: metrics.radius,
                                                   style: .continuous)
                                .fill(foreground.opacity(0.13))
                        )
                        .overlay(alignment: prefs.position == .above ? .top : .bottom) {
                            hoverLabel
                                .alignmentGuide(.top) { $0[.bottom] + 6 }
                                .alignmentGuide(.bottom) { $0[.top] - 6 }
                        }
                } else {
                    item(entry)
                        .padding(.horizontal, metrics.hPad)
                        .frame(height: metrics.height)
                }
            }
        }
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: metrics.radius, style: .continuous).fill(barFill))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius, style: .continuous).strokeBorder(barStroke, lineWidth: 1))
        .shadow(color: .black.opacity(isDark ? 0.4 : 0.16), radius: 5, y: 2)
        .environment(\.colorScheme, isDark ? .dark : .light)
    }

    @ViewBuilder
    private func item(_ entry: RegistryEntry) -> some View {
        switch prefs.displayMode {
        case .iconsOnly:
            SpecIcon(entry: entry, size: metrics.icon)
                .foregroundStyle(foreground)
        case .textOnly:
            Text(entry.name)
                .font(.system(size: metrics.font, weight: .medium))
                .foregroundStyle(foreground)
                .lineLimit(1)
        case .iconsAndText:
            HStack(spacing: 5) {
                SpecIcon(entry: entry, size: metrics.icon * 0.9)
                Text(entry.name)
                    .font(.system(size: metrics.font, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
        }
    }
}
