import AppKit

/// Renders sample bars to PNG for visual review (`--render-bar <dir>`).
enum BarSnapshots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let samples: [(String, String)] = [("Search", "symbol:magnifyingglass"), ("Cut", "symbol:scissors"),
                                           ("Copy", "symbol:doc.on.doc"), ("Paste", "symbol:doc.on.clipboard"),
                                           ("Look Up", "symbol:character.book.closed"), ("Bold", "symbol:bold"),
                                           ("Translate", "symbol:translate"), ("Change Case", "Aa"), ("Emoji", "😀"),
                                           ("Wikipedia", "square W")]
        for dark in [true, false] {
            for size in Preferences.BarSize.allCases {
                for mode in Preferences.DisplayMode.allCases {
                    let style = makeStyle(size: size, dark: dark, mode: mode)
                    var items = samples.map { s in
                        BarItemView(item: BarItem(kind: .button(title: s.0, image: IconRenderer.image(for: s.1, baseURL: nil, size: style.iconSize, fallbackTitle: s.0), forceText: false),
                                                  tooltip: s.0, handler: { _ in }), style: style)
                    }
                    items.append(BarItemView(item: BarItem(kind: .button(title: "= 1,024", image: nil, forceText: true), handler: { _ in }), style: style))
                    items.append(BarItemView(item: BarItem(kind: .nav(forward: true), handler: { _ in }), style: style))
                    write(items: items, style: style, down: true, name: "bar-\(dark ? "dark" : "light")-\(size.rawValue)-\(mode.rawValue)", dir: dir)
                }
            }
            let style = makeStyle(size: .medium, dark: dark, mode: .iconsOnly)
            write(items: [BarItemView(item: BarItem(kind: .label("12 words · 64 chars · 2 lines"), handler: { _ in }), style: style)],
                  style: style, down: false, name: "result-\(dark ? "dark" : "light")", dir: dir)
            write(items: [BarItemView(item: BarItem(kind: .status(success: true)), style: style)], style: style, down: true,
                  name: "status-ok-\(dark ? "dark" : "light")", dir: dir)
            write(items: [BarItemView(item: BarItem(kind: .status(success: false)), style: style)], style: style, down: true,
                  name: "status-fail-\(dark ? "dark" : "light")", dir: dir)
            write(items: [BarItemView(item: BarItem(kind: .label(String(repeating: "A very long result text that must truncate ", count: 4)), handler: nil), style: style)],
                  style: style, down: true, name: "result-long-\(dark ? "dark" : "light")", dir: dir)
        }
    }

    static func makeStyle(size: Preferences.BarSize, dark: Bool, mode: Preferences.DisplayMode) -> BarStyle {
        switch size {
        case .small: return BarStyle(height: 28, iconSize: 15, fontSize: 12, hPadding: 9, minButtonWidth: 30, cornerRadius: 7, isDark: dark, displayMode: mode)
        case .medium: return BarStyle(height: 34, iconSize: 17, fontSize: 13, hPadding: 11, minButtonWidth: 36, cornerRadius: 8, isDark: dark, displayMode: mode)
        case .large: return BarStyle(height: 42, iconSize: 21, fontSize: 15, hPadding: 13, minButtonWidth: 44, cornerRadius: 10, isDark: dark, displayMode: mode)
        }
    }

    static func write(items: [BarItemView], style: BarStyle, down: Bool, name: String, dir: URL) {
        let bar = BarContentView(style: style)
        bar.arrowPointsDown = down
        bar.setItems(items)
        let w = ceil(bar.contentWidth), h = style.height + style.arrowHeight
        bar.frame = NSRect(x: 0, y: 0, width: w, height: h)
        bar.arrowX = w / 2
        bar.setItems(items)
        // Put it on a contrasting backdrop so edges are visible.
        let pad: CGFloat = 16
        let backdrop = NSView(frame: NSRect(x: 0, y: 0, width: w + pad * 2, height: h + pad * 2))
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = (style.isDark ? NSColor(white: 0.32, alpha: 1) : NSColor(white: 0.86, alpha: 1)).cgColor
        bar.frame.origin = NSPoint(x: pad, y: pad)
        backdrop.addSubview(bar)
        backdrop.appearance = NSAppearance(named: style.isDark ? .darkAqua : .aqua)
        guard let rep = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { return }
        backdrop.cacheDisplay(in: backdrop.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + ".png"))
    }
}
