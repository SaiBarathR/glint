import AppKit

/// Content of one segment of the bar.
struct BarItem {
    enum Kind {
        /// A clickable action. `image` and/or `title` are shown depending on display mode.
        case button(title: String, image: NSImage?, forceText: Bool)
        /// Paging arrows.
        case nav(forward: Bool)
        /// A text result. Clickable when `handler` is set.
        case label(String)
        /// ✓ / ✗ feedback.
        case status(success: Bool)
    }
    var kind: Kind
    /// Full name shown in the hover label when the item shows only an icon.
    var tooltip: String?
    var handler: ((NSEvent.ModifierFlags) -> Void)?
}

final class BarItemView: NSView {
    let item: BarItem
    let style: BarStyle
    var onHover: ((BarItemView, Bool) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private(set) var showsTitle = false
    var visibleTitle: String? { showsTitle ? title : nil }
    private var image: NSImage?
    private var title: String?

    static let maxLabelWidth: CGFloat = 460

    init(item: BarItem, style: BarStyle) {
        self.item = item
        self.style = style
        super.init(frame: .zero)
        configure()
        frame.size = NSSize(width: intrinsicWidth, height: style.height)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(item.handler == nil ? .staticText : .button)
        // Read the content itself; the tooltip ("Click to copy") is a hint.
        setAccessibilityLabel(title ?? item.tooltip ?? "")
        if let tip = item.tooltip, tip != title { setAccessibilityHelp(tip) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func configure() {
        switch item.kind {
        case .button(let t, let img, let forceText):
            title = t
            switch style.displayMode {
            case .iconsOnly: image = img; showsTitle = img == nil || forceText
            case .textOnly: showsTitle = true; image = forceText ? nil : nil
            case .iconsAndText: image = forceText ? nil : img; showsTitle = true
            }
            if forceText { image = nil; showsTitle = true }
        case .nav(let forward):
            image = NSImage(systemSymbolName: forward ? "chevron.right" : "chevron.left", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: style.iconSize * 0.7, weight: .semibold))
            image?.isTemplate = true
        case .label(let t):
            title = t
            showsTitle = true
        case .status(let ok):
            image = NSImage(systemSymbolName: ok ? "checkmark" : "xmark", accessibilityDescription: ok ? "Done" : "Failed")?
                .withSymbolConfiguration(.init(pointSize: style.iconSize * 1.05, weight: .bold))
            image?.isTemplate = true
        }
    }

    private var attributedTitle: NSAttributedString? {
        guard showsTitle, let title else { return nil }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        var color = style.foreground
        if case .label = item.kind, item.handler == nil { color = style.foreground }
        return NSAttributedString(string: title.split(whereSeparator: \.isNewline).joined(separator: " ⏎ "),
                                  attributes: [.font: style.font, .foregroundColor: color, .paragraphStyle: para])
    }

    /// A result whose text has several lines (shown joined with ⏎ on the bar).
    var isMultilineLabel: Bool {
        if case .label(let t) = item.kind { return t.contains(where: \.isNewline) } // also \r\n
        return false
    }

    /// The title doesn't fit and is shown truncated.
    var isTruncated: Bool { naturalWidth > Self.maxLabelWidth }

    /// Width the content would need without a cap.
    private var naturalWidth: CGFloat {
        var w: CGFloat = 0
        if let image { w += imageSize(image).width }
        if let t = attributedTitle { w += (image != nil ? 6 : 0) + ceil(t.size().width) }
        return w + style.hPadding * 2
    }

    var intrinsicWidth: CGFloat {
        var w: CGFloat = 0
        if let image { w += imageSize(image).width }
        if let t = attributedTitle {
            if image != nil { w += 6 }
            w += ceil(t.size().width)
        }
        if case .nav = item.kind { return max(style.minButtonWidth * 0.75, w + style.hPadding) }
        var total = w + style.hPadding * 2
        switch item.kind {
        case .label, .button: total = min(total, Self.maxLabelWidth) // long text truncates instead of overflowing
        default: break
        }
        return max(style.minButtonWidth, total)
    }

    private func imageSize(_ img: NSImage) -> NSSize {
        let s = img.size
        guard s.width > 0, s.height > 0 else { return NSSize(width: style.iconSize, height: style.iconSize) }
        // Symbols carry their own size; other images are scaled to the icon box.
        if img.isTemplate, s.height <= style.iconSize * 1.4 { return s }
        let scale = min(style.iconSize / s.width, style.iconSize / s.height)
        return NSSize(width: round(s.width * scale), height: round(s.height * scale))
    }

    override func draw(_ dirtyRect: NSRect) {
        let isInteractive = item.handler != nil
        if isInteractive, hovering || pressing {
            let r = bounds.insetBy(dx: 2, dy: 3)
            (pressing ? style.pressed : style.hover).setFill()
            NSBezierPath(roundedRect: r, xRadius: style.cornerRadius - 3, yRadius: style.cornerRadius - 3).fill()
        }
        let fg: NSColor
        if case .status(let ok) = item.kind { fg = ok ? .systemGreen : .systemRed }
        else if pressing { fg = .white }
        else { fg = style.foreground }

        var contentWidth: CGFloat = 0
        let imgSize = image.map(imageSize)
        let t = attributedTitle.map { s -> NSAttributedString in
            let m = NSMutableAttributedString(attributedString: s)
            m.addAttribute(.foregroundColor, value: fg, range: NSRange(location: 0, length: m.length))
            return m
        }
        if let imgSize { contentWidth += imgSize.width }
        let maxTextWidth = bounds.width - style.hPadding * 2 - (imgSize.map { $0.width + 6 } ?? 0)
        let textWidth = t.map { min(ceil($0.size().width), max(0, maxTextWidth)) } ?? 0
        if t != nil { contentWidth += textWidth + (imgSize != nil ? 6 : 0) }
        var x = round((bounds.width - contentWidth) / 2)
        if let image, let imgSize {
            let r = NSRect(x: x, y: round((bounds.height - imgSize.height) / 2), width: imgSize.width, height: imgSize.height)
            style.tinted(image, color: fg).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1,
                                                respectFlipped: true, hints: nil)
            x += imgSize.width + 6
        }
        if let t {
            let h = ceil(t.size().height)
            t.draw(with: NSRect(x: x, y: round((bounds.height - h) / 2), width: textWidth, height: h),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        onHover?(self, true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressing = false
        onHover?(self, false)
    }

    override func mouseDown(with event: NSEvent) {
        guard item.handler != nil else { return }
        pressing = true
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if pressing != inside, item.handler != nil { pressing = inside }
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressing = pressing
        pressing = false
        if inside, wasPressing { item.handler?(NSEvent.modifierFlags) }
    }
}
