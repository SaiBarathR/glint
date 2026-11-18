import AppKit

/// Turns an icon spec string into an image.
///
/// Supported specs:
///  - `symbol:name`  SF Symbol (also bare SF Symbol names like `star.fill`)
///  - `text:Ab`, `square Ab`, `circle Ab`, `square filled Ab`  text drawn as an icon (also short text / emoji)
///  - `iconify:mdi:home`  downloaded once from the Iconify API and cached
///  - a file name inside the extension folder (png, pdf, svg, tiff)
enum IconRenderer {
    private static var cache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    static func image(for spec: String?, baseURL: URL?, size: CGFloat, fallbackTitle: String? = nil) -> NSImage? {
        // The title only matters when there's no icon spec; keeping it out of the key stops the cache growing
        // with every "Open <host>" / "Email <address>" title.
        let hasSpec = !(spec ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let key = "\(spec ?? "")|\(baseURL?.path ?? "")|\(size)|\(hasSpec ? "" : (fallbackTitle ?? ""))"
        cacheLock.lock()
        if let hit = cache[key] { cacheLock.unlock(); return hit }
        cacheLock.unlock()
        let img = render(spec: spec, baseURL: baseURL, size: size, fallbackTitle: fallbackTitle)
        if let img {
            cacheLock.lock()
            if cache.count > 400 { cache.removeAll() }
            cache[key] = img
            cacheLock.unlock()
        }
        return img
    }

    private static func render(spec rawSpec: String?, baseURL: URL?, size: CGFloat, fallbackTitle: String?) -> NSImage? {
        guard var spec = rawSpec?.trimmingCharacters(in: .whitespaces), !spec.isEmpty else {
            return fallbackTitle.map { textIcon(initials($0), shape: .none, filled: false, size: size) }
        }
        var shape: Shape = .none
        var filled = false
        // Modifiers like "square", "circle", "filled", "monospaced" before the content.
        while true {
            let lower = spec.lowercased()
            if lower.hasPrefix("square ") { shape = .square; spec = String(spec.dropFirst(7)) }
            else if lower.hasPrefix("circle ") { shape = .circle; spec = String(spec.dropFirst(7)) }
            else if lower.hasPrefix("filled ") { filled = true; spec = String(spec.dropFirst(7)) }
            else if lower.hasPrefix("monospaced ") || lower.hasPrefix("strike ") || lower.hasPrefix("flip-x ")
                        || lower.hasPrefix("flip-y ") || lower.hasPrefix("search ") || lower.hasPrefix("shape=") {
                spec = String(spec.drop { $0 != " " }.dropFirst())
            } else { break }
        }
        let lower = spec.lowercased()

        if lower.hasPrefix("symbol:") || lower.hasPrefix("sf:") {
            let name = String(spec.drop { $0 != ":" }.dropFirst()).trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? nil : symbol(name, size: size, shape: shape, filled: filled))
                ?? textIcon(initials(fallbackTitle ?? "?"), shape: shape, filled: filled, size: size)
        }
        if lower.hasPrefix("text:") {
            return textIcon(String(spec.dropFirst(5)), shape: shape, filled: filled, size: size)
        }
        if lower.hasPrefix("iconify:") {
            return iconify(String(spec.dropFirst(8)), size: size)
                ?? textIcon(initials(fallbackTitle ?? "?"), shape: shape, filled: filled, size: size)
        }
        if let baseURL, ["png", "pdf", "svg", "tiff", "tif", "jpg", "jpeg", "icns"].contains((spec as NSString).pathExtension.lowercased()) {
            let url = baseURL.appendingPathComponent(spec)
            if let img = NSImage(contentsOf: url) {
                img.isTemplate = !spec.lowercased().contains("color")
                img.size = NSSize(width: size, height: size)
                return img
            }
            return textIcon(initials(fallbackTitle ?? "?"), shape: shape, filled: filled, size: size)
        }
        if spec.contains("."), !spec.contains(" "), let img = symbol(spec, size: size, shape: shape, filled: filled) {
            return img
        }
        if let img = NSImage(systemSymbolName: spec, accessibilityDescription: nil), !spec.contains(" "), spec.count > 3 {
            _ = img
            return symbol(spec, size: size, shape: shape, filled: filled)
        }
        // Short text or emoji.
        return textIcon(spec.count <= 4 ? spec : initials(spec), shape: shape, filled: filled, size: size)
    }

    enum Shape { case none, square, circle }

    static func initials(_ title: String) -> String {
        let words = title.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String(title.prefix(2)).capitalized
    }

    static func symbol(_ name: String, size: CGFloat, shape: Shape, filled: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size * (shape == .none ? 0.82 : 0.55), weight: .medium)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: name)?.withSymbolConfiguration(config) else {
            return nil
        }
        guard shape != .none else { base.isTemplate = true; return base }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawShape(shape, filled: filled, in: rect)
            let s = base.size
            let r = NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height)
            if filled {
                base.draw(in: r, from: .zero, operation: .destinationOut, fraction: 1)
            } else {
                base.draw(in: r)
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    static func drawShape(_ shape: Shape, filled: Bool, in rect: NSRect) {
        let inset = rect.insetBy(dx: 1, dy: 1)
        let path: NSBezierPath = shape == .circle ? NSBezierPath(ovalIn: inset)
            : NSBezierPath(roundedRect: inset, xRadius: rect.width * 0.2, yRadius: rect.width * 0.2)
        NSColor.black.set()
        if filled { path.fill() } else { path.lineWidth = max(1, rect.width / 14); path.stroke() }
    }

    static func textIcon(_ text: String, shape: Shape, filled: Bool, size: CGFloat) -> NSImage {
        let isEmoji = text.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if shape != .none { drawShape(shape, filled: filled, in: rect) }
            let count = max(1, text.count)
            let scale: CGFloat = shape == .none ? (count == 1 ? 0.8 : count == 2 ? 0.62 : count == 3 ? 0.46 : 0.38)
                                                : (count == 1 ? 0.6 : count == 2 ? 0.45 : 0.34)
            let font = NSFont.systemFont(ofSize: size * scale, weight: .semibold)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: para]
            let str = NSAttributedString(string: text, attributes: attrs)
            let bounds = str.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin])
            let drawRect = NSRect(x: 0, y: (rect.height - bounds.height) / 2, width: rect.width, height: bounds.height)
            if filled && shape != .none {
                NSGraphicsContext.current?.compositingOperation = .destinationOut
            }
            str.draw(in: drawRect)
            return true
        }
        img.isTemplate = !isEmoji
        return img
    }

    // MARK: Iconify

    static var iconifyCacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.saibarath.glint/iconify", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Loads an Iconify icon from the disk cache, or downloads it in the background for next time.
    static func iconify(_ name: String, size: CGFloat) -> NSImage? {
        let parts = name.split(separator: ":")
        guard parts.count == 2 else { return nil }
        let file = iconifyCacheDirectory.appendingPathComponent("\(parts[0])-\(parts[1]).svg")
        if let img = NSImage(contentsOf: file) {
            img.isTemplate = true
            img.size = NSSize(width: size, height: size)
            return img
        }
        if let url = URL(string: "https://api.iconify.design/\(parts[0])/\(parts[1]).svg?height=64") {
            URLSession.shared.dataTask(with: url) { data, response, _ in
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                try? data.write(to: file)
                cacheLock.lock(); cache.removeAll(); cacheLock.unlock()
            }.resume()
        }
        return nil
    }
}
