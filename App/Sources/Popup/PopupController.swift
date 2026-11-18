import AppKit
import GlintCore

/// Shows the action bar and its result / status / choice states.
final class PopupController {
    static let shared = PopupController()

    private let panel = PopupPanel()
    private let hoverLabel = HoverLabelPanel()
    private var content: BarContentView?
    private var anchor: CGRect = .zero
    private var actions: [BarAction] = []
    private var page = 0
    private var pages: [[Int]] = []
    private var dismissTimer: Timer?
    private var shownAt = Date.distantPast
    private(set) var isVisible = false
    /// Called when an action button is clicked.
    var onAction: ((BarAction, NSEvent.ModifierFlags) -> Void)?

    var frame: NSRect { panel.frame }

    // MARK: Showing

    func show(actions: [BarAction], anchor: CGRect) {
        guard !actions.isEmpty else { return }
        dismissTimer?.invalidate()
        self.anchor = anchor
        self.actions = actions
        page = 0
        let style = BarStyle.current()
        pages = paginate(actions.map { makeItemView(for: $0, style: style) }, style: style)
        render(items: itemsForPage(style: style), style: style, animate: !isVisible)
    }

    func showResult(_ text: String, preview: Bool) {
        guard isVisible || anchor != .zero else { return }
        let style = BarStyle.current()
        var item = BarItem(kind: .label(text), tooltip: preview ? "Click to copy" : nil)
        if preview {
            item.handler = { [weak self] _ in
                Clipboard.setString(text)
                self?.showStatus(success: true)
            }
        }
        render(items: [BarItemView(item: item, style: style)], style: style, animate: !isVisible)
        if !preview { scheduleDismiss(after: max(2.5, min(8, Double(text.count) / 12))) }
    }

    func showStatus(success: Bool) {
        let style = BarStyle.current()
        render(items: [BarItemView(item: BarItem(kind: .status(success: success)), style: style)], style: style,
               animate: !isVisible)
        scheduleDismiss(after: success ? 0.6 : 1.0)
    }

    /// Shows a list of text choices (spelling suggestions, multiple links...).
    func showChoices(_ choices: [String], handler: @escaping (String, NSEvent.ModifierFlags) -> Void) {
        let style = BarStyle.current()
        let views = choices.map { choice in
            BarItemView(item: BarItem(kind: .button(title: choice, image: nil, forceText: true), tooltip: choice,
                                      handler: { flags in handler(choice, flags) }), style: style)
        }
        actions = []
        pages = paginate(views, style: style)
        page = 0
        choiceViews = views
        render(items: itemsForPage(style: style), style: style, animate: !isVisible)
    }
    private var choiceViews: [BarItemView]?

    func dismiss(animated: Bool = true) {
        dismissTimer?.invalidate()
        hoverLabel.orderOut(nil)
        guard isVisible else { return }
        isVisible = false
        choiceViews = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.1
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, !self.isVisible else { return }
                self.panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }
    }

    /// Hide when the pointer wanders far away from the bar.
    func mouseMoved(to point: CGPoint) {
        guard isVisible, Preferences.shared.dismissWhenMouseLeaves, Date().timeIntervalSince(shownAt) > 0.4 else { return }
        let f = panel.frame.union(anchor)
        let dx = max(f.minX - point.x, 0, point.x - f.maxX)
        let dy = max(f.minY - point.y, 0, point.y - f.maxY)
        if hypot(dx, dy) > 180 { dismiss() }
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.dismiss() }
    }

    // MARK: Items & paging

    private func makeItemView(for action: BarAction, style: BarStyle) -> BarItemView {
        let image = action.textOnly ? nil : IconRenderer.image(for: action.icon, baseURL: action.iconBaseURL,
                                                               size: style.iconSize, fallbackTitle: action.title)
        let item = BarItem(kind: .button(title: action.title, image: image, forceText: action.textOnly),
                           tooltip: action.title,
                           handler: { [weak self] flags in self?.onAction?(action, flags) })
        return BarItemView(item: item, style: style)
    }

    private var maxWidth: CGFloat {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        return min((screen?.visibleFrame.width ?? 1200) - 24, 720)
    }

    /// Splits item views into pages that fit the max width, leaving room for nav arrows.
    private func paginate(_ views: [BarItemView], style: BarStyle) -> [[Int]] {
        allViews = views
        let navWidth = BarItemView(item: BarItem(kind: .nav(forward: true)), style: style).intrinsicWidth + 1
        let total = views.reduce(0) { $0 + $1.intrinsicWidth + 1 }
        if total <= maxWidth { return [Array(views.indices)] }
        var result: [[Int]] = []
        var current: [Int] = []
        var width: CGFloat = navWidth * 2
        for (i, v) in views.enumerated() {
            let w = v.intrinsicWidth + 1
            if !current.isEmpty, width + w > maxWidth {
                result.append(current)
                current = []
                width = navWidth * 2
            }
            current.append(i)
            width += w
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
    private var allViews: [BarItemView] = []

    private func itemsForPage(style: BarStyle) -> [BarItemView] {
        guard !pages.isEmpty else { return [] }
        var views: [BarItemView] = []
        if page > 0 {
            views.append(BarItemView(item: BarItem(kind: .nav(forward: false), tooltip: "Previous",
                                                   handler: { [weak self] _ in self?.turnPage(-1) }), style: style))
        }
        // Fresh views each render so hover state resets cleanly.
        for i in pages[page] {
            let old = allViews[i]
            views.append(BarItemView(item: old.item, style: style))
        }
        if page < pages.count - 1 {
            views.append(BarItemView(item: BarItem(kind: .nav(forward: true), tooltip: "More",
                                                   handler: { [weak self] _ in self?.turnPage(1) }), style: style))
        }
        return views
    }

    private func turnPage(_ delta: Int) {
        let style = BarStyle.current()
        page = min(max(0, page + delta), pages.count - 1)
        render(items: itemsForPage(style: style), style: style, animate: false)
    }

    // MARK: Layout

    private func render(items: [BarItemView], style: BarStyle, animate: Bool) {
        hoverLabel.orderOut(nil)
        let view = BarContentView(style: style)
        view.setItems(items)
        for item in items {
            item.onHover = { [weak self] v, inside in self?.hoverChanged(v, inside: inside, style: style) }
        }
        let width = ceil(view.contentWidth)
        let height = style.height + style.arrowHeight
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame

        var above = Preferences.shared.position == .above
        let gap: CGFloat = 3
        if above, anchor.maxY + gap + height > vf.maxY { above = false }
        if !above, anchor.minY - gap - height < vf.minY { above = true }
        var origin = NSPoint(x: round(anchor.midX - width / 2),
                             y: above ? anchor.maxY + gap : anchor.minY - gap - height)
        origin.x = min(max(origin.x, vf.minX + 6), vf.maxX - width - 6)
        origin.y = min(max(origin.y, vf.minY + 2), vf.maxY - height - 2)

        view.arrowPointsDown = above
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.arrowX = anchor.midX - origin.x
        view.setItems(items) // re-layout with final arrow direction
        content = view
        panel.contentView = view
        panel.invalidateShadow()
        let frame = NSRect(origin: origin, size: NSSize(width: width, height: height))

        if animate {
            panel.alphaValue = 0
            panel.setFrame(frame.offsetBy(dx: 0, dy: above ? -4 : 4), display: true)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
            shownAt = Date()
        } else {
            panel.alphaValue = 1
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
        isVisible = true
    }

    private func hoverChanged(_ v: BarItemView, inside: Bool, style: BarStyle) {
        guard Preferences.shared.showHoverLabels else { return }
        guard inside, !v.showsTitle, let tip = v.item.tooltip, v.item.handler != nil else {
            hoverLabel.orderOut(nil)
            return
        }
        let rectInWindow = v.convert(v.bounds, to: nil)
        let screenRect = panel.convertToScreen(rectInWindow)
        hoverLabel.show(tip, above: screenRect, style: style, preferBelow: !(content?.arrowPointsDown ?? true))
    }
}
