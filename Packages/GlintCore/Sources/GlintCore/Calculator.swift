import Foundation

/// A small, safe arithmetic evaluator (no NSExpression, which can raise ObjC exceptions).
/// Supports + - * / % ^ (power), parentheses, unary minus, thousands separators,
/// constants pi/e and functions sqrt, abs, sin, cos, tan, ln, log, round, floor, ceil.
public enum Calculator {
    public enum CalcError: Error { case syntax, divisionByZero, unknownIdentifier(String) }

    public static func looksLikeExpression(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: " ", with: "")
        guard t.count >= 3 else { return false }
        // Hex literals (0x20) aren't decimal arithmetic.
        if t.range(of: #"(?<![\d.])0[xX][0-9a-fA-F]"#, options: .regularExpression) != nil { return false }
        // Dates (2026-11-18, 10/12/2026, 18.11.2026) and times aren't arithmetic.
        let datePatterns = [#"^\d{4}([-/.])\d{1,2}\1\d{1,2}$"#, #"^\d{1,2}([-/.])\d{1,2}\1\d{2,4}$"#]
        if datePatterns.contains(where: { t.range(of: $0, options: .regularExpression) != nil }) { return false }
        // Must contain at least one operator between operands and one digit.
        guard t.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        let ops = CharacterSet(charactersIn: "+-*/×÷^%")
        // Needs a real operator after the first character, or a function call like sqrt(2); "(2019)" is not math.
        let hasFunctionCall = t.range(of: #"[A-Za-z]\("#, options: .regularExpression) != nil
        guard t.dropFirst().rangeOfCharacter(from: ops) != nil || hasFunctionCall else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,+-*/×÷^%() =").union(.letters)
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        // Letters only allowed when they form known function or constant names.
        let words = t.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let known: Set<String> = ["sqrt", "abs", "sin", "cos", "tan", "ln", "log", "round", "floor", "ceil", "pi", "e", "x"]
        return words.allSatisfy { known.contains($0.lowercased()) }
    }

    public static func evaluate(_ input: String) throws -> Double {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("=") { text.removeLast() }
        text = text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
        // Remove thousands separators like 1,234,567 (comma followed by exactly three digits).
        text = text.replacingOccurrences(of: #"(?<=\d),(?=\d{3}(\D|$))"#, with: "", options: .regularExpression)
        var parser = Parser(Array(text))
        let value = try parser.parseExpression()
        parser.skipSpaces()
        guard parser.atEnd else { throw CalcError.syntax }
        guard value.isFinite else { throw CalcError.divisionByZero }
        return value
    }

    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        // Integers are exact up to 2^53: print them in full.
        if value == value.rounded(), abs(value) <= 9_007_199_254_740_992 {
            return value == 0 ? "0" : String(format: "%.0f", value)
        }
        // Beyond that (or huge fractions) only ~15 significant digits are real.
        if abs(value) > 9_007_199_254_740_992 { return String(format: "%.15g", value) }
        // Below the 10 decimals shown: float noise (0.3-0.2-0.1 ≈ 3e-17) is 0, real tiny results (2^-40) use
        // scientific notation instead of collapsing to "0".
        if abs(value) < 1e-15 { return "0" }
        if abs(value) < 5e-11 { return String(format: "%.15g", value) }
        // Up to 10 decimals, but never more than 15 significant digits (427452.59, not 427452.5900000001).
        let integerDigits = abs(value) < 1 ? 1 : Int(floor(log10(abs(value)))) + 1
        let places = max(0, min(10, 15 - integerDigits))
        var s = String(format: "%.\(places)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        init(_ chars: [Character]) { self.chars = chars }
        var atEnd: Bool { i >= chars.count }
        mutating func skipSpaces() { while i < chars.count, chars[i] == " " { i += 1 } }
        mutating func peek() -> Character? { skipSpaces(); return atEnd ? nil : chars[i] }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while let c = peek(), c == "+" || c == "-" {
                i += 1
                let rhs = try parseTerm()
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parseFactor()
            while let c = peek(), c == "*" || c == "/" || c == "%" || c == "x" {
                i += 1
                let rhs = try parseFactor()
                switch c {
                case "*", "x": value *= rhs
                case "/":
                    guard rhs != 0 else { throw CalcError.divisionByZero }
                    value /= rhs
                default:
                    guard rhs != 0 else { throw CalcError.divisionByZero }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        /// Unary signs bind looser than powers: -2^2 = -(2^2) = -4.
        mutating func parseFactor() throws -> Double {
            if let c = peek(), c == "-" || c == "+" {
                i += 1
                let v = try parseFactor()
                return c == "-" ? -v : v
            }
            let base = try parsePrimary()
            if let c = peek(), c == "^" {
                i += 1
                let exp = try parseFactor() // right associative, may carry its own sign: 2^-1
                return pow(base, exp)
            }
            return base
        }

        mutating func parsePrimary() throws -> Double {
            guard let c = peek() else { throw CalcError.syntax }
            if c == "(" {
                i += 1
                let v = try parseExpression()
                guard peek() == ")" else { throw CalcError.syntax }
                i += 1
                return v
            }
            if c.isNumber || c == "." {
                let start = i
                while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
                // Scientific notation: 1e5
                if i < chars.count, chars[i] == "e" || chars[i] == "E",
                   i + 1 < chars.count, chars[i + 1].isNumber || chars[i + 1] == "-" {
                    i += 1
                    if chars[i] == "-" { i += 1 }
                    while i < chars.count, chars[i].isNumber { i += 1 }
                }
                guard let v = Double(String(chars[start..<i])) else { throw CalcError.syntax }
                return v
            }
            if c.isLetter {
                let start = i
                while i < chars.count, chars[i].isLetter { i += 1 }
                let name = String(chars[start..<i]).lowercased()
                switch name {
                case "pi": return Double.pi
                case "e": return M_E
                default: break
                }
                guard peek() == "(" else { throw CalcError.unknownIdentifier(name) }
                i += 1
                let arg = try parseExpression()
                guard peek() == ")" else { throw CalcError.syntax }
                i += 1
                switch name {
                case "sqrt": return sqrt(arg)
                case "abs": return abs(arg)
                case "sin": return sin(arg)
                case "cos": return cos(arg)
                case "tan": return tan(arg)
                case "ln": return log(arg)
                case "log": return log10(arg)
                case "round": return arg.rounded()
                case "floor": return floor(arg)
                case "ceil": return ceil(arg)
                default: throw CalcError.unknownIdentifier(name)
                }
            }
            throw CalcError.syntax
        }
    }
}
