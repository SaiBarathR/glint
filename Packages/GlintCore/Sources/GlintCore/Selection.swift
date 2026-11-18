import Foundation

/// Everything known about the current selection and the app it lives in.
public struct SelectionContext: Equatable {
    public var text: String
    /// Rich text (HTML) of the selection, when the app exposes it.
    public var html: String?
    public var appBundleID: String?
    public var appName: String?
    /// The selection can be replaced by typing (editable field).
    public var canCut: Bool
    public var canCopy: Bool
    public var canPaste: Bool
    /// The target supports rich text formatting (Bold/Italic/Underline).
    public var canFormat: Bool
    /// Text the system clipboard currently holds (for paste requirements).
    public var clipboardText: String?
    /// URL of the document or web page the selection came from, if known.
    public var sourceURL: String?

    public init(text: String, html: String? = nil, appBundleID: String? = nil, appName: String? = nil,
                canCut: Bool = false, canCopy: Bool = true, canPaste: Bool = false, canFormat: Bool = false,
                clipboardText: String? = nil, sourceURL: String? = nil) {
        self.text = text
        self.html = html
        self.appBundleID = appBundleID
        self.appName = appName
        self.canCut = canCut
        self.canCopy = canCopy
        self.canPaste = canPaste
        self.canFormat = canFormat
        self.clipboardText = clipboardText
        self.sourceURL = sourceURL
    }

    public var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Detected content, computed lazily by callers via `ContentDetector`.
    public var detected: DetectedContent { ContentDetector.detect(in: text) }
}

/// Modifier keys held when an action was clicked.
public struct ModifierState: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = ModifierState(rawValue: 1 << 17)
    public static let control = ModifierState(rawValue: 1 << 18)
    public static let option = ModifierState(rawValue: 1 << 19)
    public static let command = ModifierState(rawValue: 1 << 20)

    public var asDictionary: [String: Bool] {
        ["shift": contains(.shift), "control": contains(.control), "option": contains(.option), "command": contains(.command)]
    }
}
