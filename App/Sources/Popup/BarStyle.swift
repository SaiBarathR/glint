import AppKit

/// Colours and metrics for the bar, from the user's appearance settings.
struct BarStyle {
    let height: CGFloat
    let iconSize: CGFloat
    let fontSize: CGFloat
    let hPadding: CGFloat
    let minButtonWidth: CGFloat
    let cornerRadius: CGFloat
    let arrowHeight: CGFloat = 7
    let arrowWidth: CGFloat = 16
    let isDark: Bool
    let displayMode: Preferences.DisplayMode

    var background: NSColor { isDark ? NSColor(white: 0.12, alpha: 0.97) : NSColor(white: 0.985, alpha: 0.98) }
    var border: NSColor { isDark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.14) }
    var foreground: NSColor { isDark ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.12, alpha: 1) }
    var secondary: NSColor { isDark ? NSColor(white: 0.7, alpha: 1) : NSColor(white: 0.4, alpha: 1) }
    var separator: NSColor { isDark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.1) }
    var hover: NSColor { isDark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.07) }
    var pressed: NSColor { NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.75 : 0.55) }
    var font: NSFont { .systemFont(ofSize: fontSize, weight: .medium) }

    static func current() -> BarStyle {
        let p = Preferences.shared
        let dark: Bool
        switch p.theme {
        case .dark: dark = true
        case .light: dark = false
        case .system: dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        switch p.barSize {
        case .small:
            return BarStyle(height: 28, iconSize: 15, fontSize: 12, hPadding: 9, minButtonWidth: 30, cornerRadius: 7,
                            isDark: dark, displayMode: p.displayMode)
        case .medium:
            return BarStyle(height: 34, iconSize: 17, fontSize: 13, hPadding: 11, minButtonWidth: 36, cornerRadius: 8,
                            isDark: dark, displayMode: p.displayMode)
        case .large:
            return BarStyle(height: 42, iconSize: 21, fontSize: 15, hPadding: 13, minButtonWidth: 44, cornerRadius: 10,
                            isDark: dark, displayMode: p.displayMode)
        }
    }

    func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        guard image.isTemplate else { return image }
        let out = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return out
    }
}
