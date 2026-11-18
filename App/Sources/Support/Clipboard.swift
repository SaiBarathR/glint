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

    /// Reads the selection by sending ⌘C and restoring the clipboard afterwards.
    /// Returns (text, html). Nil when nothing was copied or only files were copied.
    static func copySelection(timeout: TimeInterval = 0.35) async -> (String, String?)? {
        let before = await MainActor.run { snapshot() }
        await MainActor.run { KeySender.command(.copy) }
        let deadline = Date().addingTimeInterval(timeout)
        var changed = false
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if await MainActor.run(body: { pb.changeCount != before.changeCount }) { changed = true; break }
        }
        guard changed else { return nil }
        return await MainActor.run {
            defer { restore(before) }
            let types = pb.types ?? []
            if types.contains(.fileURL), !types.contains(.rtf), !types.contains(.html) { return nil }
            guard let text = pb.string(forType: .string), !text.isEmpty else { return nil }
            return (text, pb.string(forType: .html))
        }
    }
}
