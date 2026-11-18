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
        generation &+= 1
        pb.clearContents()
        let items = s.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, data) in dict { item.setData(data, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    static var string: String? { pb.string(forType: .string) }

    /// Bumped whenever Glint writes the clipboard, an action runs, or the user may have copied (⌘C/⌘X,
    /// context menu, menu bar). A late-⌘C watcher stops as soon as it moves, so it never undoes a copy.
    static var generation = 0
    /// When the user last pressed ⌘C/⌘X or opened a menu that offers Copy.
    static var lastUserCopyAt = Date.distantPast
    static func noteUserCopy() {
        generation &+= 1
        lastUserCopyAt = Date()
    }
    /// An action is about to run: retire any late-⌘C watcher so it can't undo what the action writes.
    static func retireWatchers() { generation &+= 1 }

    static func setString(_ s: String) {
        generation &+= 1
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    // MARK: Temporary use (paste-result, paste plain)

    /// The user's clipboard from before Glint borrowed it; one pending return covers several quick pastes.
    private static var borrowed: Snapshot?
    private static var restoreWork: DispatchWorkItem?
    /// The clipboard's change count right after Glint's temporary write. If it moved, someone really copied
    /// something, and that copy wins over the return.
    private static var borrowedChangeCount = 0

    /// Call before putting temporary content on the clipboard. Keeps the oldest snapshot.
    static func borrow() {
        if borrowed == nil { borrowed = snapshot() }
        restoreWork?.cancel()
    }

    /// Puts the borrowed clipboard back after `delay`, unless borrowed again meanwhile or the user copied.
    static func scheduleReturn(after delay: TimeInterval = 0.6) {
        restoreWork?.cancel()
        borrowedChangeCount = pb.changeCount
        let work = DispatchWorkItem { returnBorrowed() }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func returnBorrowed() {
        if let s = borrowed, pb.changeCount == borrowedChangeCount { restore(s) }
        borrowed = nil
        restoreWork = nil
    }

    /// Puts a borrowed clipboard back right away (before reading the clipboard for something else).
    static func flushPendingReturn() {
        guard let work = restoreWork else { return }
        work.cancel()
        returnBorrowed()
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

    /// True while a ⌘C sent by Glint hasn't been answered (or given up on) yet.
    private static var copyOutstanding = false

    /// Reads the selection by sending ⌘C and restoring the clipboard afterwards.
    /// Returns (text, html). Nil when nothing was copied, only files were copied, or a fallback isn't safe now.
    static func copySelection(timeout: TimeInterval = 0.35) async -> (String, String?)? {
        // Prepare and send on the main actor in one step. Never send a second ⌘C while one is unanswered
        // (its late answer would be mistaken for ours), never after the capture was cancelled, and never
        // right after the user copied something themselves.
        let prepared = await MainActor.run { () -> (Snapshot, Int)? in
            guard !Task.isCancelled, !copyOutstanding, Date().timeIntervalSince(lastUserCopyAt) > 0.5 else { return nil }
            flushPendingReturn()
            let before = snapshot()
            KeySender.command(.copy)
            copyOutstanding = true
            return (before, generation)
        }
        guard let (before, gen) = prepared else { return nil }

        // Poll for the answer. Keep polling even if cancelled, so the clipboard is always settled.
        let deadline = Date().addingTimeInterval(timeout)
        var changed = false
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if await MainActor.run(body: { pb.changeCount != before.changeCount }) { changed = true; break }
        }
        guard changed else {
            // The app may still answer late: keep watching and put the user's clipboard back if it does,
            // unless the user (or an action) touched the clipboard first.
            Task.detached {
                let lateDeadline = Date().addingTimeInterval(1.5)
                var settled = false
                while Date() < lateDeadline, !settled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    settled = await MainActor.run { () -> Bool in
                        if generation != gen { return true }
                        guard pb.changeCount != before.changeCount else { return false }
                        restore(before)
                        return true
                    }
                }
                await MainActor.run { copyOutstanding = false }
            }
            return nil
        }
        return await MainActor.run { () -> (String, String?)? in
            defer {
                // Put the user's clipboard back, unless they copied something themselves in the meantime.
                if generation == gen { restore(before) }
                copyOutstanding = false
            }
            if Task.isCancelled { return nil }
            let types = pb.types ?? []
            if types.contains(.fileURL), !types.contains(.rtf), !types.contains(.html) { return nil }
            guard let text = pb.string(forType: .string), !text.isEmpty else { return nil }
            return (text, pb.string(forType: .html))
        }
    }
}
