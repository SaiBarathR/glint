import AppKit

/// Shows recent extension output and errors.
final class LogWindow: NSObject, NSWindowDelegate {
    static let shared = LogWindow()
    private var window: NSWindow?
    private var textView: NSTextView?
    private var timer: Timer?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Glint Extension Log"
            w.isReleasedWhenClosed = false
            w.delegate = self
            let scroll = NSTextView.scrollableTextView()
            let tv = scroll.documentView as! NSTextView
            tv.isEditable = false
            tv.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
            tv.textContainerInset = NSSize(width: 10, height: 10)
            let clear = NSButton(title: "Clear", target: self, action: #selector(clear))
            clear.bezelStyle = .rounded
            let container = NSView()
            scroll.translatesAutoresizingMaskIntoConstraints = false
            clear.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(scroll)
            container.addSubview(clear)
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: container.topAnchor),
                scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scroll.bottomAnchor.constraint(equalTo: clear.topAnchor, constant: -10),
                clear.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
                clear.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            ])
            w.contentView = container
            w.center()
            window = w
            textView = tv
        }
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        let lines = ActionPerformer.shared.log
        let text = lines.isEmpty ? "No messages yet. Output written to stderr by scripts and console.log() calls appears here." : lines.joined(separator: "\n")
        if textView?.string != text { textView?.string = text; textView?.scrollToEndOfDocument(nil) }
    }

    @objc private func clear() {
        ActionPerformer.shared.clearLog()
        refresh()
    }

    func windowWillClose(_ notification: Notification) { timer?.invalidate() }
}
