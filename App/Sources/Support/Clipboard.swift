import AppKit

/// Clipboard helpers: snapshot/restore and the ⌘C fallback for reading selections.
enum Clipboard {
    static var pb: NSPasteboard { .general }

    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
        let changeCount: Int
    }

    static func snapshot() -> Snapshot {
        let items = (pb.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
        return Snapshot(items: items, changeCount: pb.changeCount)
    }

    static func restore(_ s: Snapshot) {
        pb.clearContents()
        let items = s.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, data) in dict { item.setData(data, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    static var string: String? { pb.string(forType: .string) }

    static func setString(_ s: String) {
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    // MARK: Temporary use (paste-result, paste plain)

    /// The user's clipboard from before Glint borrowed it; one pending restore covers several quick pastes.
    private static var borrowed: Snapshot?
    private static var restoreWork: DispatchWorkItem?

    /// Call before putting temporary content on the clipboard. Keeps the oldest snapshot.
    static func borrow() {
        if borrowed == nil { borrowed = snapshot() }
        restoreWork?.cancel()
    }

    /// Puts the borrowed clipboard back after `delay`, unless borrowed again meanwhile.
    static func scheduleReturn(after delay: TimeInterval = 0.6) {
        restoreWork?.cancel()
        let work = DispatchWorkItem {
            if let s = borrowed { restore(s) }
            borrowed = nil
            restoreWork = nil
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// A deliberate copy: replaces the clipboard and cancels any pending restore so it stays.
    static func copy(_ s: String) {
        keepCurrent()
        setString(s)
    }

    /// Drop a pending return (the user now wants the new content to stay on the clipboard).
    static func keepCurrent() {
        restoreWork?.cancel()
        restoreWork = nil
        borrowed = nil
    }

    // MARK: ⌘C fallback

    /// Reads the selection by sending ⌘C and restoring the clipboard afterwards.
    /// Returns (text, html). Nil when nothing was copied or only files were copied.
    static func copySelection(timeout: TimeInterval = 0.35) async -> (String, String?)? {
        let before = await MainActor.run { snapshot() }
        await MainActor.run { KeySender.command(.copy) }
        let deadline = Date().addingTimeInterval(timeout)
        var changed = false
        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if await MainActor.run(body: { pb.changeCount != before.changeCount }) { changed = true; break }
        }
        guard changed else {
            // The app may still answer the ⌘C late: keep watching and put the user's clipboard back if it does.
            Task.detached {
                let lateDeadline = Date().addingTimeInterval(2)
                while Date() < lateDeadline {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    let restored = await MainActor.run { () -> Bool in
                        guard pb.changeCount != before.changeCount else { return false }
                        restore(before)
                        return true
                    }
                    if restored { break }
                }
            }
            return nil
        }
        return await MainActor.run {
            defer { restore(before) }
            if Task.isCancelled { return nil }
            let types = pb.types ?? []
            if types.contains(.fileURL), !types.contains(.rtf), !types.contains(.html) { return nil }
            guard let text = pb.string(forType: .string), !text.isEmpty else { return nil }
            return (text, pb.string(forType: .html))
        }
    }
}
