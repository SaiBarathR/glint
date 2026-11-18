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
        ownChangeCount = pb.changeCount
    }

    static var string: String? { pb.string(forType: .string) }

    /// The clipboard's change count right after Glint's most recent write, so watchers can tell Glint's own
    /// writes from an app answering ⌘C.
    static var ownChangeCount = -1
    /// Bumped only by the user's own ⌘C / ⌘X key presses: a late-⌘C restore must never undo those.
    static var userCopyGeneration = 0
    /// When the user last pressed ⌘C/⌘X, right-clicked or clicked the menu bar (menus offer Copy).
    static var lastUserCopyAt = Date.distantPast
    static var lastClickHintAt = Date.distantPast

    static func noteUserCopy() {
        userCopyGeneration &+= 1
        lastUserCopyAt = Date()
    }

    /// A right-click or menu-bar click: the user *may* copy from a menu shortly.
    static func noteClickHint() {
        lastClickHintAt = Date()
        lastUserCopyAt = lastClickHintAt
    }

    static func setString(_ s: String) {
        pb.clearContents()
        pb.setString(s, forType: .string)
        ownChangeCount = pb.changeCount
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
        // A Glint ⌘C is in flight: its restore will re-base the change count. Decide once it has settled.
        if copyOutstanding, borrowed != nil {
            // Runs again as soon as the ⌘C settles (settleOutstandingCopy); the timer is only a safety net.
            waitingForCopy = true
            let work = DispatchWorkItem { returnBorrowed() }
            restoreWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
            return
        }
        waitingForCopy = false
        if let s = borrowed, pb.changeCount == borrowedChangeCount { restore(s) }
        borrowed = nil
        restoreWork = nil
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
    private(set) static var copyOutstanding = false

    /// Marks the outstanding ⌘C as settled and runs a paste-result return that was waiting for it.
    private static func settleOutstandingCopy() {
        copyOutstanding = false
        if borrowed != nil, let work = restoreWork, work.isCancelled == false, waitingForCopy {
            waitingForCopy = false
            work.cancel()
            returnBorrowed()
        }
    }
    /// A paste-result return deferred itself because a ⌘C was outstanding.
    private static var waitingForCopy = false

    /// Waits (up to ~2 s, longer than a watcher lives) until no Glint ⌘C is outstanding. Actions call this first, so an app's late
    /// answer can never interleave with an action's own clipboard writes or keystrokes.
    static func waitForOutstandingCopy() async {
        for _ in 0..<50 where await MainActor.run(body: { copyOutstanding }) {
            await pause(0.04)
        }
    }

    /// A sleep that ignores task cancellation (a cancelled `Task.sleep` returns at once and would spin).
    private static func pause(_ seconds: TimeInterval) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { c.resume() }
        }
    }

    /// Should an app's answer to Glint's ⌘C, arriving now, be undone? Not if the user copied in the meantime:
    /// a ⌘C/⌘X key, or a change arriving well after a right-click / menu-bar click (a menu's Copy item).
    private static func shouldRestore(userGen: Int, sentAt: Date) -> Bool {
        if userCopyGeneration != userGen { return false }
        if lastClickHintAt > sentAt, Date().timeIntervalSince(lastClickHintAt) > 0.4 { return false }
        return true
    }

    /// Reads the selection by sending ⌘C and restoring the clipboard afterwards.
    /// Returns (text, html). Nil when nothing was copied, only files were copied, or a fallback isn't safe now.
    static func copySelection(timeout: TimeInterval = 0.35) async -> (String, String?)? {
        // Prepare and send on the main actor in one step. Never send a second ⌘C while one is unanswered
        // (its late answer would be mistaken for ours), never after the capture was cancelled, and never
        // right after the user copied (or may be copying) something themselves.
        let prepared = await MainActor.run { () -> (Snapshot, Int, Date)? in
            guard !Task.isCancelled, !copyOutstanding, Date().timeIntervalSince(lastUserCopyAt) > 0.5 else { return nil }
            // A pending paste-result return is left alone (flushing it could race the app's queued ⌘V); the
            // restores below keep its change count current, so it still returns the user's clipboard.
            let before = snapshot()
            KeySender.command(.copy)
            copyOutstanding = true
            return (before, userCopyGeneration, Date())
        }
        guard let (sentBaseline, userGen, sentAt) = prepared else { return nil }

        // Poll for the answer (even if cancelled, so the clipboard always settles). Glint's own writes in the
        // meantime (a slow action finishing) aren't the answer: they become the baseline to return to.
        let deadline = Date().addingTimeInterval(timeout)
        var changed = false
        var current = sentBaseline
        while Date() < deadline {
            await pause(0.02)
            let answered = await MainActor.run { () -> Bool in
                guard pb.changeCount != current.changeCount else { return false }
                if pb.changeCount == ownChangeCount { current = snapshot(); return false }
                return true
            }
            if answered { changed = true; break }
        }
        let before = current
        guard changed else {
            // The app may still answer late. Keep watching until it does or the window ends; Glint's own writes
            // in the meantime become the new baseline to return to.
            Task.detached {
                // Web and Electron apps copy in another process that can answer late even when the app itself
                // responds, so always watch the full window.
                let lateDeadline = sentAt.addingTimeInterval(1.85)
                var baseline = before
                var settled = false
                while Date() < lateDeadline, !settled {
                    await pause(0.05)
                    settled = await MainActor.run { () -> Bool in
                        guard pb.changeCount != baseline.changeCount else { return false }
                        if pb.changeCount == ownChangeCount {
                            baseline = snapshot()
                            return false
                        }
                        if shouldRestore(userGen: userGen, sentAt: sentAt) {
                            restore(baseline)
                            // A paste-result return pending from before must compare against this restore.
                            if borrowed != nil { borrowedChangeCount = pb.changeCount }
                        }
                        return true
                    }
                }
                await MainActor.run { settleOutstandingCopy() }
            }
            return nil
        }
        return await MainActor.run { () -> (String, String?)? in
            defer {
                if shouldRestore(userGen: userGen, sentAt: sentAt) {
                    restore(before)
                    if borrowed != nil { borrowedChangeCount = pb.changeCount }
                }
                settleOutstandingCopy()
            }
            if Task.isCancelled { return nil }
            let types = pb.types ?? []
            if types.contains(.fileURL), !types.contains(.rtf), !types.contains(.html) { return nil }
            guard let text = pb.string(forType: .string), !text.isEmpty else { return nil }
            return (text, pb.string(forType: .html))
        }
    }
}
