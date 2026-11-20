import AppKit
import SwiftUI

struct AboutPane: View {
    static let repositoryURL = URL(string: "https://github.com/SaiBarathR/glint")!

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    private var copyright: String? {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text("Glint")
                        .font(.system(size: 26, weight: .semibold))
                    Text(version)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text("Select text in any app and Glint shows a small bar of actions right next to it: search, copy, paste, translate, and anything else you add with extensions.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)

                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(Self.repositoryURL)
                    } label: {
                        Label("View on GitHub", systemImage: "arrow.up.right.square")
                    }
                    UpdateButton()
                }
                .controlSize(.large)
                UpdateStatusText()

                extensionsCard
                    .frame(maxWidth: 540)
                    .padding(.top, 6)

                if let copyright {
                    Text(copyright)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var extensionsCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 8) {
                Text("Write your own extensions")
                    .font(.headline)
                Text("Select a snippet that starts with #glint (or #popclip) in any app, and Glint offers Install Extension on the bar. Packages (.glintext, .popclipext) install from the + menu in Actions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "#glint\nname: Search Wikipedia\nicon: symbol:book\nurl: https://en.wikipedia.org/w/index.php?search=***")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }
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


/// "Check for Updates" / "Download vX" button driven by `UpdateChecker`.
struct UpdateButton: View {
    @ObservedObject private var checker = UpdateChecker.shared
    var body: some View {
        if let release = checker.availableRelease {
            Button {
                checker.openRelease(release)
            } label: {
                Label("Download \(release.tagName)", systemImage: "arrow.down.circle")
            }
        } else {
            Button {
                Task { await checker.check(manual: true) }
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(checker.state == .checking)
        }
    }
}

struct UpdateStatusText: View {
    @ObservedObject private var checker = UpdateChecker.shared
    var body: some View {
        Group {
            switch checker.state {
            case .checking: Text("Checking for updates…")
            case .current: Text("Glint is up to date.")
            case .available(let release): Text("Glint \(release.tagName.drop(while: { $0 == "v" })) is available.")
            case .failed(let message): Text(message)
            case .idle: EmptyView()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
