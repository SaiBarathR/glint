import Foundation

public struct TextStats: Equatable {
    public var characters: Int
    public var charactersNoSpaces: Int
    public var words: Int
    public var lines: Int
    public var sentences: Int

    public init(_ text: String) {
        characters = text.count
        charactersNoSpaces = text.filter { !$0.isWhitespace }.count
        var words = 0
        var sentences = 0
        let range = text.startIndex..<text.endIndex
        text.enumerateSubstrings(in: range, options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        text.enumerateSubstrings(in: range, options: [.bySentences, .substringNotRequired]) { _, _, _, _ in sentences += 1 }
        self.words = words
        self.sentences = sentences
        lines = text.isEmpty ? 0 : text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    /// Short summary shown in the bar, e.g. "12 words · 64 chars".
    public var summary: String {
        var parts = ["\(words) word\(words == 1 ? "" : "s")", "\(characters) char\(characters == 1 ? "" : "s")"]
        if sentences > 1 { parts.append("\(sentences) sentences") }
        if lines > 1 { parts.append("\(lines) lines") }
        return parts.joined(separator: " · ")
    }
}
