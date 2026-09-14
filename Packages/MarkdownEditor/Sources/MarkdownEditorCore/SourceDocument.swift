import Foundation

/// Line terminator style used when the editor inserts new lines.
public enum LineEnding: String, Sendable, Equatable {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"

    /// Detects the dominant terminator in `text`. Defaults to LF.
    public static func dominant(in text: String) -> LineEnding {
        var lf = 0, crlf = 0, cr = 0
        var previousWasCR = false
        for unit in text.utf16 {
            if unit == 0x0D {
                if previousWasCR { cr += 1 }
                previousWasCR = true
                continue
            }
            if unit == 0x0A {
                if previousWasCR { crlf += 1 } else { lf += 1 }
            } else if previousWasCR {
                cr += 1
            }
            previousWasCR = false
        }
        if previousWasCR { cr += 1 }
        if crlf > lf && crlf >= cr { return .crlf }
        if cr > lf && cr > crlf { return .cr }
        return .lf
    }
}

/// A single replacement applied to the canonical Markdown source.
/// All offsets are UTF-16 code units in the source string.
public struct SourceEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    public var replacementLength: Int { (replacement as NSString).length }
    public var lengthDelta: Int { replacementLength - range.length }
}

/// The canonical Markdown source of one open note plus a monotonically increasing revision.
/// The source keeps its original line terminators; the presentation layer hides `\r`.
public struct SourceDocument: Equatable, Sendable {
    public private(set) var text: String
    public private(set) var revision: Int
    public var lineEnding: LineEnding

    public init(text: String, revision: Int = 0, lineEnding: LineEnding? = nil) {
        self.text = text
        self.revision = revision
        self.lineEnding = lineEnding ?? LineEnding.dominant(in: text)
    }

    public var utf16Count: Int { (text as NSString).length }
    public var fullRange: NSRange { NSRange(location: 0, length: utf16Count) }

    /// Applies `edit` and returns the inverse edit that restores the previous text.
    @discardableResult
    public mutating func apply(_ edit: SourceEdit) -> SourceEdit {
        let ns = text as NSString
        precondition(edit.range.location >= 0 && NSMaxRange(edit.range) <= ns.length, "SourceEdit out of bounds")
        let removed = ns.substring(with: edit.range)
        text = ns.replacingCharacters(in: edit.range, with: edit.replacement)
        revision += 1
        return SourceEdit(range: NSRange(location: edit.range.location, length: edit.replacementLength), replacement: removed)
    }

    /// Replaces the whole text (external reload). Bumps the revision.
    public mutating func replaceAll(with newText: String, keepLineEnding: Bool = false) {
        text = newText
        revision += 1
        if !keepLineEnding { lineEnding = LineEnding.dominant(in: newText) }
    }

    public func substring(_ range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    /// Range of the line containing `offset` (excluding its terminator) and the terminator range.
    public func lineRange(at offset: Int) -> (content: NSRange, terminator: NSRange) {
        let ns = text as NSString
        let clamped = max(0, min(offset, ns.length))
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: clamped, length: 0))
        return (NSRange(location: start, length: contentsEnd - start), NSRange(location: contentsEnd, length: end - contentsEnd))
    }
}
