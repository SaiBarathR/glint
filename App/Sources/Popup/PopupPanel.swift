import AppKit

/// A borderless panel that never takes focus from the app the user is working in.
final class PopupPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the rounded bar with its pointer arrow and lays out item views.
final class BarContentView: NSView {
    var style: BarStyle
    /// Arrow points down (bar above the selection) or up (bar below).
    var arrowPointsDown = true
    /// Arrow tip x position in view coordinates.
    var arrowX: CGFloat = 0
    private(set) var itemViews: [BarItemView] = []

    init(style: BarStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The bar body (without the arrow) in view coordinates.
    var barRect: NSRect {
        NSRect(x: 0, y: arrowPointsDown ? 0 : style.arrowHeight, width: bounds.width, height: style.height)
    }

    func setItems(_ views: [BarItemView]) {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = views
        var x: CGFloat = 0
        for v in views {
            v.frame = NSRect(x: x, y: barRect.minY, width: v.intrinsicWidth, height: style.height)
            addSubview(v)
            x += v.frame.width + 1 // 1pt separator
        }
        needsDisplay = true
    }

    var contentWidth: CGFloat {
        guard !itemViews.isEmpty else { return 0 }
        return itemViews.reduce(0) { $0 + $1.intrinsicWidth } + CGFloat(itemViews.count - 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = barRect.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bar, xRadius: style.cornerRadius, yRadius: style.cornerRadius)
        // Pointer arrow merged into the body.
        let tipX = min(max(arrowX, bar.minX + style.cornerRadius + style.arrowWidth / 2),
                       bar.maxX - style.cornerRadius - style.arrowWidth / 2)
        let arrow = NSBezierPath()
        if arrowPointsDown {
            arrow.move(to: NSPoint(x: tipX - style.arrowWidth / 2, y: bar.maxY - 0.5))
            arrow.line(to: NSPoint(x: tipX, y: bar.maxY + style.arrowHeight - 0.5))
            arrow.line(to: NSPoint(x: tipX + style.arrowWidth / 2, y: bar.maxY - 0.5))
        } else {
            arrow.move(to: NSPoint(x: tipX - style.arrowWidth / 2, y: bar.minY + 0.5))
            arrow.line(to: NSPoint(x: tipX, y: bar.minY - style.arrowHeight + 0.5))
            arrow.line(to: NSPoint(x: tipX + style.arrowWidth / 2, y: bar.minY + 0.5))
        }
        arrow.close()

        style.background.setFill()
        path.fill()
        arrow.fill()
        style.border.setStroke()
        path.lineWidth = 1
        // Stroke the outline except where the arrow joins.
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: bounds)
        clip.append(NSBezierPath(rect: NSRect(x: tipX - style.arrowWidth / 2 + 1, y: arrowPointsDown ? bar.maxY - 2 : bar.minY - 1,
                                              width: style.arrowWidth - 2, height: 3)))
        clip.windingRule = .evenOdd
        clip.addClip()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let arrowEdge = NSBezierPath()
        if arrowPointsDown {
            arrowEdge.move(to: NSPoint(x: tipX - style.arrowWidth / 2, y: bar.maxY))
            arrowEdge.line(to: NSPoint(x: tipX, y: bar.maxY + style.arrowHeight - 0.5))
            arrowEdge.line(to: NSPoint(x: tipX + style.arrowWidth / 2, y: bar.maxY))
        } else {
            arrowEdge.move(to: NSPoint(x: tipX - style.arrowWidth / 2, y: bar.minY))
            arrowEdge.line(to: NSPoint(x: tipX, y: bar.minY - style.arrowHeight + 0.5))
            arrowEdge.line(to: NSPoint(x: tipX + style.arrowWidth / 2, y: bar.minY))
        }
        arrowEdge.lineWidth = 1
        arrowEdge.stroke()

        // Separators between items.
        style.separator.setFill()
        for v in itemViews.dropFirst() {
            NSRect(x: v.frame.minX - 1, y: bar.minY + 7, width: 1, height: bar.height - 14).fill()
        }
    }
}

/// Small floating label showing the hovered action's name.
final class HoverLabelPanel: NSPanel {
    private let field = NSTextField(labelWithString: "")
    private let box = NSView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        box.wantsLayer = true
        box.layer?.cornerRadius = 5
        field.font = .systemFont(ofSize: 11.5, weight: .medium)
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 12
        box.addSubview(field)
        contentView = box
    }
    override var canBecomeKey: Bool { false }

    func show(_ text: String, above rect: NSRect, style: BarStyle, preferBelow: Bool) {
        field.stringValue = text
        field.textColor = style.foreground
        box.layer?.backgroundColor = style.background.cgColor
        box.layer?.borderColor = style.border.cgColor
        box.layer?.borderWidth = 1
        // One line when it fits, otherwise wrapped at 560 pt (long results, multi-line messages).
        let maxText: CGFloat = 544
        field.preferredMaxLayoutWidth = maxText
        let size = field.sizeThatFits(NSSize(width: maxText, height: .greatestFiniteMagnitude))
        let w = min(ceil(size.width), maxText) + 16
        let h = max(22, ceil(size.height) + 8)
        field.frame = NSRect(x: 8, y: (h - ceil(size.height)) / 2, width: w - 16, height: ceil(size.height))
        var origin = NSPoint(x: rect.midX - w / 2, y: preferBelow ? rect.minY - h - 4 : rect.maxY + 4)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.x = min(max(origin.x, vf.minX + 4), vf.maxX - w - 4)
            if origin.y + h > vf.maxY { origin.y = rect.minY - h - 4 }
            if origin.y < vf.minY { origin.y = rect.maxY + 4 }
        }
        setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
        orderFrontRegardless()
    }
}
