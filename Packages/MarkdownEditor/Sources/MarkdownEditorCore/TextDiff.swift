import Foundation

/// Minimal replacement that turns `old` into `new`, computed on UTF-16 code units
/// with common prefix/suffix trimming. Boundaries never split surrogate pairs.
public struct TextDiff: Equatable, Sendable {
    /// Range in `old`.
    public var range: NSRange
    /// Replacement text taken from `new`.
    public var replacement: String

    public static func between(_ old: String, _ new: String) -> TextDiff? {
        let a = Array(old.utf16), b = Array(new.utf16)
        if a == b { return nil }
        var prefix = 0
        let minCount = min(a.count, b.count)
        while prefix < minCount, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < minCount - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        // Do not split surrogate pairs.
        if prefix > 0, prefix < a.count, UTF16.isLeadSurrogate(a[prefix - 1]) { prefix -= 1 }
        if suffix > 0, a.count - suffix < a.count, UTF16.isTrailSurrogate(a[a.count - suffix]) { suffix -= 1 }
        let range = NSRange(location: prefix, length: a.count - prefix - suffix)
        let replacementUnits = Array(b[prefix..<(b.count - suffix)])
        return TextDiff(range: range, replacement: String(utf16CodeUnits: replacementUnits, count: replacementUnits.count))
    }
}
