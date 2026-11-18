import AppKit

/// Detects whether the system cursor is the text I-beam, a strong hint that a drag selects text.
enum CursorProbe {
    private static let iBeamData: [Data] = [NSCursor.iBeam, NSCursor.iBeamCursorForVerticalLayout]
        .compactMap { $0.image.tiffRepresentation }

    static var isIBeam: Bool {
        guard let current = NSCursor.currentSystem else { return false }
        if current.hotSpot == NSCursor.iBeam.hotSpot, current.image.size == NSCursor.iBeam.image.size { return true }
        guard let data = current.image.tiffRepresentation else { return false }
        return iBeamData.contains(data)
    }
}
