import Foundation

/// Minimal replacement that turns `old` into `new`, computed on UTF-16 code units
/// with common prefix/suffix trimming. Boundaries never split surrogate pairs.
public struct TextDiff: Equatable, Sendable {
    /// Range in `old`.
    public var range: NSRange
    /// Replacement text taken from `new`.
    public var replacement: String

    public static func between(_ old: String, _ new: String) -> TextDiff? {
        // Fast path: editor typing is overwhelmingly plain ASCII, and native Swift strings store
        // their bytes contiguously as UTF-8, so `withContiguousStorageIfAvailable` almost always
        // hands back a pointer into the existing storage with no copy at all. When both strings
        // are pure ASCII, byte offset == UTF-16 offset == scalar offset everywhere, so the whole
        // prefix/suffix scan (and the "no change at all" check) can run directly over those
        // pointers — no `Array(_.utf16)` transcoding/allocation of either string is needed, and
        // there is no surrogate-pair boundary to worry about since ASCII has none.
        switch fastASCIIDiff(old, new) {
        case .diff(let d): return d
        case .identical: return nil
        case .notApplicable: break
        }

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

    private enum FastResult {
        case notApplicable
        case identical
        case diff(TextDiff)
    }

    private static func fastASCIIDiff(_ old: String, _ new: String) -> FastResult {
        let outer: FastResult?? = old.utf8.withContiguousStorageIfAvailable { oldBuf -> FastResult? in
            new.utf8.withContiguousStorageIfAvailable { newBuf -> FastResult in
                for byte in oldBuf where byte >= 0x80 { return .notApplicable }
                for byte in newBuf where byte >= 0x80 { return .notApplicable }

                let oldCount = oldBuf.count, newCount = newBuf.count
                let minCount = min(oldCount, newCount)
                var prefix = 0
                while prefix < minCount, oldBuf[prefix] == newBuf[prefix] { prefix += 1 }
                if prefix == oldCount, prefix == newCount { return .identical }
                var suffix = 0
                while suffix < minCount - prefix, oldBuf[oldCount - 1 - suffix] == newBuf[newCount - 1 - suffix] { suffix += 1 }

                let range = NSRange(location: prefix, length: oldCount - prefix - suffix)
                let replacementSlice = UnsafeBufferPointer(rebasing: newBuf[prefix..<(newCount - suffix)])
                let replacement = String(decoding: replacementSlice, as: UTF8.self)
                return .diff(TextDiff(range: range, replacement: replacement))
            }
        }
        return (outer ?? nil) ?? .notApplicable
    }
}
