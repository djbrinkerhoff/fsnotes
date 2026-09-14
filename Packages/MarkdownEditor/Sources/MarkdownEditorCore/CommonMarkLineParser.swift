import Foundation

/// A focused, line-based CommonMark-ish parser producing `MarkdownTree`.
///
/// All ranges are UTF-16 offsets into the source. Internally this operates on
/// `Array(source.utf16)` for O(1) random access and to avoid `String.Index`
/// arithmetic pitfalls with combining marks / surrogate pairs.
public struct CommonMarkLineParser: MarkdownParser {
    public var options: MarkdownParserOptions

    public init(options: MarkdownParserOptions = MarkdownParserOptions()) {
        self.options = options
    }

    public func parse(_ source: String) -> MarkdownTree {
        let units = Array(source.utf16)
        let lines = Self.splitLines(units)
        let engine = BlockEngine(units: units, lines: lines, options: options)
        let blocks = engine.run()
        return MarkdownTree(blocks: blocks, linkReferences: engine.linkReferences, lines: lines)
    }

    /// Splits `units` into physical lines, handling `\n`, `\r\n`, and lone `\r`.
    /// Always yields at least one line (possibly empty), and a trailing terminator
    /// yields one further trailing empty line.
    static func splitLines(_ units: [UInt16]) -> [MarkdownLine] {
        var lines: [MarkdownLine] = []
        let count = units.count
        // Heuristic capacity avoids most of the doubling reallocations for realistically-sized
        // documents. Markdown tends to have short lines (headings, list items, blank separator
        // lines), so this deliberately errs on the side of a smaller assumed average line length
        // (which over-reserves slightly) rather than a larger one (which would still leave a
        // reallocation on the table for exactly the short-lined documents this is meant to help).
        lines.reserveCapacity(max(16, count / 12))
        var lineStart = 0
        var i = 0
        while i < count {
            let u = units[i]
            if u == 0x0A { // \n
                lines.append(MarkdownLine(range: NSRange(location: lineStart, length: i - lineStart),
                                           terminator: NSRange(location: i, length: 1)))
                i += 1
                lineStart = i
            } else if u == 0x0D { // \r or \r\n
                let termLength: Int
                if i + 1 < count && units[i + 1] == 0x0A {
                    termLength = 2
                } else {
                    termLength = 1
                }
                lines.append(MarkdownLine(range: NSRange(location: lineStart, length: i - lineStart),
                                           terminator: NSRange(location: i, length: termLength)))
                i += termLength
                lineStart = i
            } else {
                i += 1
            }
        }
        // Final (possibly empty) line, with empty terminator.
        lines.append(MarkdownLine(range: NSRange(location: lineStart, length: count - lineStart),
                                   terminator: NSRange(location: count, length: 0)))
        return lines
    }
}

// MARK: - Shared low-level scanning helpers

enum CharKind {
    static let space: UInt16 = 0x20
    static let tab: UInt16 = 0x09
    static let backslash: UInt16 = 0x5C
    static let hash: UInt16 = 0x23
    static let greaterThan: UInt16 = 0x3E
    static let lessThan: UInt16 = 0x3C
    static let asterisk: UInt16 = 0x2A
    static let underscore: UInt16 = 0x5F
    static let tilde: UInt16 = 0x7E
    static let backtick: UInt16 = 0x60
    static let dash: UInt16 = 0x2D
    static let plus: UInt16 = 0x2B
    static let equals: UInt16 = 0x3D
    static let dot: UInt16 = 0x2E
    static let bang: UInt16 = 0x21
    static let openBracket: UInt16 = 0x5B
    static let closeBracket: UInt16 = 0x5D
    static let openParen: UInt16 = 0x28
    static let closeParen: UInt16 = 0x29
    static let colon: UInt16 = 0x3A
    static let quote: UInt16 = 0x22
    static let singleQuote: UInt16 = 0x27
    static let pipe: UInt16 = 0x7C
    static let slash: UInt16 = 0x2F
    static let backslashChar: Character = "\\"

    @inline(__always) static func isASCIIDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
    @inline(__always) static func isASCIIAlpha(_ u: UInt16) -> Bool { (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) }
    @inline(__always) static func isASCIIAlnum(_ u: UInt16) -> Bool { isASCIIAlpha(u) || isASCIIDigit(u) }
    @inline(__always) static func isSpaceOrTab(_ u: UInt16) -> Bool { u == space || u == tab }

    /// ASCII punctuation, per CommonMark's backslash-escape and flanking rules.
    @inline(__always) static func isASCIIPunctuation(_ u: UInt16) -> Bool {
        switch u {
        case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E:
            return true
        default:
            return false
        }
    }
}

/// Decodes the Unicode scalar starting at `pos` (handles surrogate pairs). Returns the scalar
/// and its UTF-16 width (1 or 2), or nil if out of bounds.
func decodeScalar(_ units: [UInt16], at pos: Int) -> (scalar: Unicode.Scalar, width: Int)? {
    guard pos >= 0 && pos < units.count else { return nil }
    let u = units[pos]
    if u >= 0xD800 && u <= 0xDBFF, pos + 1 < units.count {
        let low = units[pos + 1]
        if low >= 0xDC00 && low <= 0xDFFF {
            let high = UInt32(u)
            let lowV = UInt32(low)
            let c = 0x10000 + (high - 0xD800) * 0x400 + (lowV - 0xDC00)
            if let scalar = Unicode.Scalar(c) {
                return (scalar, 2)
            }
        }
    }
    if let scalar = Unicode.Scalar(UInt32(u)) {
        return (scalar, 1)
    }
    return (Unicode.Scalar(0xFFFD)!, 1)
}

/// Decodes the Unicode scalar ending at `pos` (i.e. the scalar immediately before `pos`).
func decodeScalarBefore(_ units: [UInt16], at pos: Int) -> (scalar: Unicode.Scalar, width: Int)? {
    guard pos > 0 && pos <= units.count else { return nil }
    let u = units[pos - 1]
    if u >= 0xDC00 && u <= 0xDFFF, pos - 2 >= 0 {
        let high = units[pos - 2]
        if high >= 0xD800 && high <= 0xDBFF {
            return decodeScalar(units, at: pos - 2)
        }
    }
    if let scalar = Unicode.Scalar(UInt32(u)) {
        return (scalar, 1)
    }
    return (Unicode.Scalar(0xFFFD)!, 1)
}

func isUnicodeWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
        return true
    default:
        return false
    }
}

func isUnicodePunctuation(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.value < 0x80 {
        return CharKind.isASCIIPunctuation(UInt16(scalar.value))
    }
    switch scalar.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
         .initialPunctuation, .finalPunctuation, .otherPunctuation, .mathSymbol,
         .currencySymbol, .modifierSymbol, .otherSymbol:
        return true
    default:
        return false
    }
}

/// Normalizes a link reference label: trims, collapses internal whitespace, lowercases.
func normalizeLinkLabel(_ s: String) -> String {
    let collapsed = s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        .joined(separator: " ")
    return collapsed.lowercased()
}
