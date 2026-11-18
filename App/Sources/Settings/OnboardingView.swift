import AppKit
import Combine
import SwiftUI

struct OnboardingView: View {
    /// Overrides the live Accessibility status (snapshots).
    var forcedTrusted: Bool?
    var onDone: () -> Void

    @ObservedObject private var prefs = Preferences.shared
    @State private var trusted = Permissions.isAccessibilityTrusted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isTrusted: Bool { forcedTrusted ?? trusted }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    VStack(spacing: 12) {
                        accessibilityStep
                        tryItStep
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 34)
                .padding(.bottom, 24)
            }

            Divider()

            HStack(spacing: 12) {
                Toggle("Launch Glint at login", isOn: $prefs.launchAtLogin)
                    .toggleStyle(.checkbox)
                    .help("You can change this later in Glint's Settings.")
                Spacer(minLength: 8)
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 520, minHeight: 560)
        .onReceive(timer) { _ in
            let now = Permissions.isAccessibilityTrusted
            if now != trusted { trusted = now }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Welcome to Glint")
                .font(.system(size: 24, weight: .bold))
            Text("Select text in any app and a small bar of actions appears next to it: search, copy, paste, translate and more.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            BarPreview(showsBackdrop: false, maxItems: 5)
                .padding(.top, 6)
        }
    }

    private var accessibilityStep: some View {
        StepCard(number: 1, done: isTrusted,
                 title: "Allow Accessibility access",
                 message: isTrusted
                    ? "Access granted. Glint can now read your selection and show the bar."
                    : "Glint uses Accessibility to read the text you select, find where it is on screen, and paste results.") {
            if !isTrusted {
                HStack(spacing: 8) {
                    Button("Grant Access…") {
                        Permissions.promptForAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Open Settings") { Permissions.openAccessibilitySettings() }
                }
            }
        }
    }

    private var tryItStep: some View {
        StepCard(number: 2, done: false,
                 title: "Try it",
                 message: "Select some text in any app, such as a word on a web page. The bar appears next to your selection. Click an action, or click anywhere else to dismiss it.") {
            EmptyView()
        }
        .opacity(isTrusted ? 1 : 0.75)
    }
}

private struct StepCard<Accessory: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let message: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
