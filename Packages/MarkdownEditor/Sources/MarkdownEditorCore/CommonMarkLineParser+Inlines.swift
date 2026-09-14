import Foundation

extension BlockEngine {
    /// Parses `range` of `units` as inline content. `excluded` are boundary ranges (e.g.
    /// blockquote `>` markers on continuation lines) that must never be covered by a text
    /// node and must never be crossed by a delimiter run.
    func parseInline(range: NSRange, excluded: [NSRange], allowLinks: Bool) -> [MarkdownInline] {
        let scanner = InlineScanner(engine: self, range: range, excluded: excluded, allowLinks: allowLinks)
        return scanner.run()
    }
}

/// Builds a flat, append-only node list for one inline region, then resolves emphasis/strong
/// with a CommonMark-style delimiter stack (bounded by the `openersBottom` cache), and finally
/// assembles the properly nested `[MarkdownInline]` tree.
final class InlineScanner {
    unowned let engine: BlockEngine
    let units: [UInt16]
    let contentStart: Int
    let rangeEnd: Int
    let excluded: [NSRange]
    /// Precomputed once: most inline regions (anything not directly inside a blockquote/list
    /// marker continuation) have no excluded ranges at all, so every per-character check in the
    /// hot scan loop can skip straight past `excludedRangeAt` without even calling it.
    let hasExcluded: Bool
    let allowLinks: Bool
    // Copied out of `engine.options` once at init: the main scan loop tests these flags on
    // almost every character, and re-reading them through `engine` (an `unowned` reference)
    // repeatedly would re-pay an unowned-access check each time instead of a plain field load.
    let recognizesWikiLinks: Bool
    let recognizesTags: Bool
    let recognizesStrikethrough: Bool
    let recognizesBareURLs: Bool

    var pos: Int
    var textStart: Int

    var nodes: [MarkdownInline] = []
    var parentOf: [Int?] = []
    var removed: [Bool] = []

    struct Delim {
        var nodeIndex: Int
        var char: UInt16
        var count: Int
        let originalCount: Int
        var canOpen: Bool
        var canClose: Bool
    }
    var delimStack: [Delim] = []

    init(engine: BlockEngine, range: NSRange, excluded: [NSRange], allowLinks: Bool) {
        self.engine = engine
        self.units = engine.units
        self.contentStart = range.location
        self.rangeEnd = NSMaxRange(range)
        self.excluded = excluded
        self.hasExcluded = !excluded.isEmpty
        self.allowLinks = allowLinks
        self.recognizesWikiLinks = engine.options.recognizesWikiLinks
        self.recognizesTags = engine.options.recognizesTags
        self.recognizesStrikethrough = engine.options.recognizesStrikethrough
        self.recognizesBareURLs = engine.options.recognizesBareURLs
        self.pos = range.location
        self.textStart = range.location
        // Most spans produce far fewer nodes than characters (runs of plain text collapse into
        // one node each); a modest reserve avoids repeated reallocation without over-committing
        // for very large single-paragraph ranges.
        let estimate = min(4096, max(8, (self.rangeEnd - self.contentStart) / 8))
        nodes.reserveCapacity(estimate)
        parentOf.reserveCapacity(estimate)
        removed.reserveCapacity(estimate)
    }

    func run() -> [MarkdownInline] {
        while pos < rangeEnd {
            if hasExcluded, let ex = excludedRangeAt(pos) {
                flushText(before: pos)
                pos = NSMaxRange(ex)
                textStart = pos
                continue
            }
            let u = units[pos]
            // A `switch` over the raw code unit lets the compiler dispatch with a comparison
            // tree keyed on value instead of walking ~10 independent `if`s sequentially for
            // every plain character (the overwhelmingly common case, which hits `default`).
            switch u {
            case CharKind.backslash:
                if pos + 1 < rangeEnd, (!hasExcluded || excludedRangeAt(pos + 1) == nil), CharKind.isASCIIPunctuation(units[pos + 1]) {
                    flushText(before: pos)
                    appendNode(.escape(backslashRange: NSRange(location: pos, length: 1)), range: NSRange(location: pos, length: 2))
                    pos += 2
                    textStart = pos
                    continue
                }
            case 0x0A, 0x0D:
                handleTerminator()
                continue
            case CharKind.backtick:
                if tryCodeSpan() { continue }
            case CharKind.lessThan:
                if tryAutolinkOrHTML() { continue }
            case CharKind.asterisk, CharKind.underscore:
                handleDelimiterRun(char: u)
                continue
            case CharKind.tilde:
                if recognizesStrikethrough, pos + 1 < rangeEnd, units[pos + 1] == CharKind.tilde, tryStrikethrough() { continue }
            case CharKind.bang:
                if pos + 1 < rangeEnd, units[pos + 1] == CharKind.openBracket, tryLinkOrImage(isImage: true) { continue }
            case CharKind.openBracket:
                if recognizesWikiLinks, pos + 1 < rangeEnd, units[pos + 1] == CharKind.openBracket {
                    if tryWikiLink() { continue }
                }
                if tryLinkOrImage(isImage: false) { continue }
            case CharKind.hash:
                if recognizesTags, tryTag() { continue }
            case 0x68, 0x77:
                // `tryBareURL` only ever matches when the character is 'h' or 'w'.
                if recognizesBareURLs, tryBareURL() { continue }
            default:
                break
            }
            pos += 1
        }
        flushText(before: rangeEnd)
        resolveEmphasis()

        // Sort by (location, index) pairs rather than `nodes[$0].range.location < nodes[$1]...`:
        // `MarkdownInline` can hold a `String` payload (link/image/tag/... destinations), so a
        // comparator that subscripts `nodes` on every one of the O(n log n) comparisons would
        // repeatedly touch (and ARC-traffic) those payloads purely to read an unrelated `Int`.
        // Extracting the sort key up front means the sort itself only ever touches plain Ints,
        // and each node is materialized at most once, in `top`.
        var topEntries: [(location: Int, index: Int)] = []
        for i in 0..<nodes.count where !removed[i] && parentOf[i] == nil {
            topEntries.append((nodes[i].range.location, i))
        }
        topEntries.sort { $0.location < $1.location }
        var top: [MarkdownInline] = []
        top.reserveCapacity(topEntries.count)
        for entry in topEntries { top.append(nodes[entry.index]) }
        return mergeAdjacentText(top).map { deepMerge($0) }
    }

    // MARK: - Node bookkeeping

    @discardableResult
    func appendNode(_ kind: MarkdownInlineKind, range: NSRange, children: [MarkdownInline] = []) -> Int {
        nodes.append(MarkdownInline(kind: kind, range: range, children: children))
        parentOf.append(nil)
        removed.append(false)
        return nodes.count - 1
    }

    func flushText(before: Int) {
        if before > textStart {
            appendNode(.text, range: NSRange(location: textStart, length: before - textStart))
        }
        textStart = before
    }

    @inline(__always)
    func excludedRangeAt(_ p: Int) -> NSRange? {
        guard hasExcluded else { return nil }
        for r in excluded where r.location == p { return r }
        return nil
    }

    func filteredExcluded(_ r: NSRange) -> [NSRange] {
        excluded.filter { $0.location >= r.location && NSMaxRange($0) <= NSMaxRange(r) }
    }

    func deepMerge(_ node: MarkdownInline) -> MarkdownInline {
        // Leaf nodes (plain text, code spans, autolinks, ...) are the overwhelming majority and
        // have no children at all; skip the struct copy plus merge/map dance entirely for them.
        guard !node.children.isEmpty else { return node }
        var n = node
        n.children = mergeAdjacentText(n.children).map { deepMerge($0) }
        return n
    }

    func mergeAdjacentText(_ list: [MarkdownInline]) -> [MarkdownInline] {
        // Nothing to merge with 0 or 1 elements; skip allocating a new array. This is the
        // common case (most wrapped nodes have exactly one child).
        guard list.count > 1 else { return list }
        var result: [MarkdownInline] = []
        result.reserveCapacity(list.count)
        for node in list {
            if case .text = node.kind, let last = result.last, case .text = last.kind {
                result[result.count - 1] = MarkdownInline(kind: .text, range: NSRange(location: last.range.location, length: NSMaxRange(node.range) - last.range.location))
            } else {
                result.append(node)
            }
        }
        return result
    }

    // MARK: - Terminators (soft/hard breaks)

    func handleTerminator() {
        let isCRLF = units[pos] == 0x0D && pos + 1 < rangeEnd && units[pos + 1] == 0x0A
        let termLen = isCRLF ? 2 : 1
        let termEnd = pos + termLen

        if pos > textStart, excludedRangeAt(pos) == nil, units[pos - 1] == CharKind.backslash {
            flushText(before: pos - 1)
            appendNode(.hardBreak(markerRange: NSRange(location: pos - 1, length: 1)), range: NSRange(location: pos - 1, length: termEnd - (pos - 1)))
            textStart = termEnd
            pos = termEnd
            return
        }
        var spaceCount = 0
        var p = pos
        while p > textStart, units[p - 1] == CharKind.space { spaceCount += 1; p -= 1 }
        if spaceCount >= 2 {
            flushText(before: p)
            appendNode(.hardBreak(markerRange: NSRange(location: p, length: spaceCount)), range: NSRange(location: p, length: termEnd - p))
            textStart = termEnd
            pos = termEnd
            return
        }
        flushText(before: pos)
        appendNode(.softBreak, range: NSRange(location: pos, length: termEnd - pos))
        textStart = termEnd
        pos = termEnd
    }

    // MARK: - Code spans

    func tryCodeSpan() -> Bool {
        let start = pos
        var p = pos
        var count = 0
        while p < rangeEnd, units[p] == CharKind.backtick { p += 1; count += 1 }
        var searchPos = p
        while searchPos < rangeEnd {
            if let ex = excludedRangeAt(searchPos) { searchPos = NSMaxRange(ex); continue }
            if units[searchPos] == CharKind.backtick {
                var q = searchPos
                var c = 0
                while q < rangeEnd, units[q] == CharKind.backtick { q += 1; c += 1 }
                if c == count {
                    flushText(before: start)
                    var openEnd = p
                    var contentStart = p
                    var contentEnd = searchPos
                    var closeStart = searchPos
                    if contentEnd > contentStart, units[contentStart] == CharKind.space, units[contentEnd - 1] == CharKind.space {
                        var allSpace = true
                        for k in contentStart..<contentEnd where units[k] != CharKind.space { allSpace = false; break }
                        if !allSpace {
                            contentStart += 1
                            contentEnd -= 1
                            openEnd += 1
                            closeStart -= 1
                        }
                    }
                    let openRange = NSRange(location: start, length: openEnd - start)
                    let closeRange = NSRange(location: closeStart, length: q - closeStart)
                    var children: [MarkdownInline] = []
                    if contentEnd > contentStart {
                        children = [MarkdownInline(kind: .text, range: NSRange(location: contentStart, length: contentEnd - contentStart))]
                    }
                    appendNode(.code(open: openRange, close: closeRange), range: NSRange(location: start, length: q - start), children: children)
                    pos = q
                    textStart = q
                    return true
                } else {
                    searchPos = q
                    continue
                }
            }
            searchPos += 1
        }
        return false
    }

    // MARK: - Autolinks / inline HTML

    func tryAutolinkOrHTML() -> Bool {
        let start = pos
        var p = pos + 1
        var valid = true
        while p < rangeEnd {
            let u = units[p]
            if u == CharKind.greaterThan { break }
            if u == CharKind.lessThan || u <= 0x20 { valid = false; break }
            p += 1
        }
        if valid, p < rangeEnd, units[p] == CharKind.greaterThan {
            let inner = engine.substring(NSRange(location: start + 1, length: p - start - 1))
            if isAutolinkURI(inner) {
                flushText(before: start)
                appendNode(.autolink(destination: inner, open: NSRange(location: start, length: 1), close: NSRange(location: p, length: 1)), range: NSRange(location: start, length: p + 1 - start))
                pos = p + 1
                textStart = pos
                return true
            }
            if isAutolinkEmail(inner) {
                flushText(before: start)
                let dest = inner.lowercased().hasPrefix("mailto:") ? inner : "mailto:\(inner)"
                appendNode(.autolink(destination: dest, open: NSRange(location: start, length: 1), close: NSRange(location: p, length: 1)), range: NSRange(location: start, length: p + 1 - start))
                pos = p + 1
                textStart = pos
                return true
            }
        }
        if let tagEnd = matchInlineHTMLTag(from: start) {
            flushText(before: start)
            appendNode(.htmlInline, range: NSRange(location: start, length: tagEnd - start))
            pos = tagEnd
            textStart = pos
            return true
        }
        return false
    }

    func isAutolinkURI(_ s: String) -> Bool {
        let u = Array(s.utf16)
        guard let colonIdx = u.firstIndex(of: CharKind.colon) else { return false }
        guard colonIdx >= 2 && colonIdx <= 32 else { return false }
        guard CharKind.isASCIIAlpha(u[0]) else { return false }
        for k in 0..<colonIdx {
            let c = u[k]
            if !(CharKind.isASCIIAlnum(c) || c == CharKind.plus || c == CharKind.dot || c == CharKind.dash) { return false }
        }
        return colonIdx + 1 < u.count
    }

    func isAutolinkEmail(_ s: String) -> Bool {
        guard let at = s.firstIndex(of: "@") else { return false }
        let local = s[s.startIndex..<at]
        let domain = s[s.index(after: at)...]
        guard !local.isEmpty, !domain.isEmpty, domain.contains(".") else { return false }
        for c in s where c == " " || c == "<" || c == ">" { return false }
        return true
    }

    func matchInlineHTMLTag(from start: Int) -> Int? {
        var p = start + 1
        guard p < rangeEnd else { return nil }
        if units[p] == CharKind.bang {
            if p + 2 < rangeEnd, units[p + 1] == CharKind.dash, units[p + 2] == CharKind.dash {
                var q = p + 3
                while q + 2 < rangeEnd {
                    if units[q] == CharKind.dash, units[q + 1] == CharKind.dash, units[q + 2] == CharKind.greaterThan {
                        return q + 3
                    }
                    q += 1
                }
                return nil
            }
            var q = p + 1
            while q < rangeEnd, units[q] != CharKind.greaterThan { q += 1 }
            return q < rangeEnd ? q + 1 : nil
        }
        var isClosing = false
        if units[p] == CharKind.slash { isClosing = true; p += 1 }
        guard p < rangeEnd, CharKind.isASCIIAlpha(units[p]) else { return nil }
        while p < rangeEnd, CharKind.isASCIIAlnum(units[p]) || units[p] == CharKind.dash { p += 1 }
        if isClosing {
            while p < rangeEnd, CharKind.isSpaceOrTab(units[p]) { p += 1 }
            guard p < rangeEnd, units[p] == CharKind.greaterThan else { return nil }
            return p + 1
        }
        while p < rangeEnd {
            let u = units[p]
            if u == CharKind.lessThan { return nil }
            if u == CharKind.greaterThan { return p + 1 }
            if u == CharKind.slash, p + 1 < rangeEnd, units[p + 1] == CharKind.greaterThan { return p + 2 }
            p += 1
        }
        return nil
    }

    // MARK: - Emphasis delimiter runs

    func handleDelimiterRun(char: UInt16) {
        let start = pos
        var p = pos
        while p < rangeEnd, units[p] == char { p += 1 }
        let count = p - start
        flushText(before: start)

        let before = start > contentStart ? decodeScalarBefore(units, at: start) : nil
        let after = p < rangeEnd ? decodeScalar(units, at: p) : nil
        let beforeIsWhitespace = before.map { isUnicodeWhitespace($0.scalar) } ?? true
        let beforeIsPunct = before.map { isUnicodePunctuation($0.scalar) } ?? false
        let afterIsWhitespace = after.map { isUnicodeWhitespace($0.scalar) } ?? true
        let afterIsPunct = after.map { isUnicodePunctuation($0.scalar) } ?? false

        let leftFlanking = !afterIsWhitespace && (!afterIsPunct || beforeIsWhitespace || beforeIsPunct)
        let rightFlanking = !beforeIsWhitespace && (!beforeIsPunct || afterIsWhitespace || afterIsPunct)
        var canOpen = leftFlanking
        var canClose = rightFlanking
        if char == CharKind.underscore {
            canOpen = leftFlanking && (!rightFlanking || beforeIsPunct)
            canClose = rightFlanking && (!leftFlanking || afterIsPunct)
        }
        let idx = appendNode(.text, range: NSRange(location: start, length: count))
        delimStack.append(Delim(nodeIndex: idx, char: char, count: count, originalCount: count, canOpen: canOpen, canClose: canClose))
        pos = p
        textStart = p
    }

    struct OpenersBottomKey: Hashable { var char: UInt16; var closerCanOpen: Bool; var mod3: Int }

    func resolveEmphasis() {
        var openersBottom: [OpenersBottomKey: Int] = [:]
        var closerIdx = 0
        while closerIdx < delimStack.count {
            if !delimStack[closerIdx].canClose || delimStack[closerIdx].count == 0 {
                closerIdx += 1
                continue
            }
            let closer = delimStack[closerIdx]
            let key = OpenersBottomKey(char: closer.char, closerCanOpen: closer.canOpen, mod3: closer.originalCount % 3)
            let bottom = openersBottom[key] ?? -1
            var openerIdx = closerIdx - 1
            var foundOpener = -1
            while openerIdx > bottom {
                let opener = delimStack[openerIdx]
                if opener.char == closer.char, opener.canOpen, opener.count > 0 {
                    let bothMultiple = (opener.canOpen && opener.canClose) || (closer.canOpen && closer.canClose)
                    let sumMod3 = (opener.originalCount + closer.originalCount) % 3
                    let oddMatch = bothMultiple && sumMod3 == 0 && !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
                    if !oddMatch {
                        foundOpener = openerIdx
                        break
                    }
                }
                openerIdx -= 1
            }
            if foundOpener >= 0 {
                wrapEmphasis(openerIdx: foundOpener, closerIdx: closerIdx)
                if delimStack[closerIdx].count == 0 {
                    closerIdx += 1
                }
            } else {
                openersBottom[key] = closerIdx - 1
                closerIdx += 1
            }
        }
    }

    func wrapEmphasis(openerIdx: Int, closerIdx: Int) {
        let opener = delimStack[openerIdx]
        let closer = delimStack[closerIdx]
        let useDelims = (opener.count >= 2 && closer.count >= 2) ? 2 : 1

        let openerRange = nodes[opener.nodeIndex].range
        let closerRange = nodes[closer.nodeIndex].range
        let openerConsumed = NSRange(location: openerRange.location + openerRange.length - useDelims, length: useDelims)
        let closerConsumed = NSRange(location: closerRange.location, length: useDelims)

        let childLo = NSMaxRange(openerConsumed)
        let childHi = closerConsumed.location
        var childIndices: [Int] = []
        for i in 0..<nodes.count {
            if removed[i] || parentOf[i] != nil { continue }
            if i == opener.nodeIndex || i == closer.nodeIndex { continue }
            let r = nodes[i].range
            if r.location >= childLo, NSMaxRange(r) <= childHi {
                childIndices.append(i)
            }
        }
        childIndices.sort { nodes[$0].range.location < nodes[$1].range.location }
        let children = childIndices.map { nodes[$0] }

        let wrapKind: MarkdownInlineKind = useDelims == 2 ? .strong(open: openerConsumed, close: closerConsumed) : .emphasis(open: openerConsumed, close: closerConsumed)
        let wrapRange = NSRange(location: openerConsumed.location, length: NSMaxRange(closerConsumed) - openerConsumed.location)
        let wIdx = appendNode(wrapKind, range: wrapRange, children: children)
        for i in childIndices { parentOf[i] = wIdx }

        let openerLeftover = openerRange.length - useDelims
        if openerLeftover > 0 {
            nodes[opener.nodeIndex].range = NSRange(location: openerRange.location, length: openerLeftover)
        } else {
            removed[opener.nodeIndex] = true
        }
        let closerLeftover = closerRange.length - useDelims
        if closerLeftover > 0 {
            nodes[closer.nodeIndex].range = NSRange(location: closerRange.location + useDelims, length: closerLeftover)
        } else {
            removed[closer.nodeIndex] = true
        }

        delimStack[openerIdx].count -= useDelims
        delimStack[closerIdx].count -= useDelims
        if closerIdx - openerIdx > 1 {
            for k in (openerIdx + 1)..<closerIdx { delimStack[k].count = 0 }
        }
    }

    // MARK: - Strikethrough

    func tryStrikethrough() -> Bool {
        let start = pos
        var p = pos + 2
        while p + 1 < rangeEnd {
            if units[p] == CharKind.tilde, units[p + 1] == CharKind.tilde { break }
            p += 1
        }
        guard p + 1 < rangeEnd, units[p] == CharKind.tilde, units[p + 1] == CharKind.tilde else { return false }
        guard p > start + 2 else { return false } // require non-empty content
        flushText(before: start)
        let innerRange = NSRange(location: start + 2, length: p - (start + 2))
        let children = engine.parseInline(range: innerRange, excluded: filteredExcluded(innerRange), allowLinks: allowLinks)
        appendNode(.strikethrough(open: NSRange(location: start, length: 2), close: NSRange(location: p, length: 2)), range: NSRange(location: start, length: p + 2 - start), children: children)
        pos = p + 2
        textStart = pos
        return true
    }

    // MARK: - Links / images

    func tryLinkOrImage(isImage: Bool) -> Bool {
        let markerPos = pos
        let bracketPos = isImage ? pos + 1 : pos
        guard bracketPos < rangeEnd, units[bracketPos] == CharKind.openBracket else { return false }
        var p = bracketPos + 1
        var depth = 0
        var closeBracket = -1
        while p < rangeEnd {
            if let ex = excludedRangeAt(p) { p = NSMaxRange(ex); continue }
            let u = units[p]
            if u == CharKind.backslash, p + 1 < rangeEnd { p += 2; continue }
            if u == CharKind.openBracket { depth += 1; p += 1; continue }
            if u == CharKind.closeBracket {
                if depth == 0 { closeBracket = p; break }
                depth -= 1; p += 1; continue
            }
            p += 1
        }
        guard closeBracket >= 0 else { return false }
        if !isImage, !allowLinks {
            return false
        }
        let labelRange = NSRange(location: bracketPos + 1, length: closeBracket - (bracketPos + 1))
        let q = closeBracket + 1

        if q < rangeEnd, units[q] == CharKind.openParen, let (dest, endPos) = parseInlineLinkTail(from: q) {
            flushText(before: markerPos)
            emitLinkOrImage(isImage: isImage, markerPos: markerPos, closeBracket: closeBracket, endPos: endPos, dest: dest, labelRange: labelRange)
            return true
        }

        var refLabelRange: NSRange? = nil
        var endPos = closeBracket + 1
        if q < rangeEnd, units[q] == CharKind.openBracket {
            var r = q + 1
            while r < rangeEnd, units[r] != CharKind.closeBracket { r += 1 }
            guard r < rangeEnd else { return false }
            if r > q + 1 { refLabelRange = NSRange(location: q + 1, length: r - (q + 1)) }
            endPos = r + 1
        }
        let key: String
        if let refLabelRange {
            key = normalizeLinkLabel(engine.substring(refLabelRange))
        } else {
            key = normalizeLinkLabel(engine.substring(labelRange))
        }
        guard let dest = engine.linkReferences[key] else { return false }
        flushText(before: markerPos)
        emitLinkOrImage(isImage: isImage, markerPos: markerPos, closeBracket: closeBracket, endPos: endPos, dest: dest, labelRange: labelRange)
        return true
    }

    private func emitLinkOrImage(isImage: Bool, markerPos: Int, closeBracket: Int, endPos: Int, dest: String, labelRange: NSRange) {
        let openRange = isImage ? NSRange(location: markerPos, length: 2) : NSRange(location: markerPos, length: 1)
        let closeRange = NSRange(location: closeBracket, length: endPos - closeBracket)
        let children = engine.parseInline(range: labelRange, excluded: filteredExcluded(labelRange), allowLinks: false)
        let kind: MarkdownInlineKind = isImage ? .image(destination: dest, open: openRange, close: closeRange) : .link(destination: dest, open: openRange, close: closeRange)
        appendNode(kind, range: NSRange(location: markerPos, length: endPos - markerPos), children: children)
        pos = endPos
        textStart = pos
    }

    func parseInlineLinkTail(from openParenPos: Int) -> (String, Int)? {
        var p = openParenPos + 1
        while p < rangeEnd, isWhitespaceOrNewline(units[p]) { p += 1 }
        var dest = ""
        if p < rangeEnd, units[p] == CharKind.lessThan {
            p += 1
            let start = p
            while p < rangeEnd, units[p] != CharKind.greaterThan, units[p] != CharKind.lessThan { p += 1 }
            guard p < rangeEnd, units[p] == CharKind.greaterThan else { return nil }
            dest = engine.substring(NSRange(location: start, length: p - start))
            p += 1
        } else {
            let start = p
            var parenDepth = 0
            while p < rangeEnd {
                let u = units[p]
                if u == CharKind.backslash, p + 1 < rangeEnd { p += 2; continue }
                if isWhitespaceOrNewline(u) { break }
                if u == CharKind.openParen { parenDepth += 1; p += 1; continue }
                if u == CharKind.closeParen {
                    if parenDepth == 0 { break }
                    parenDepth -= 1; p += 1; continue
                }
                if u < 0x20 { return nil }
                p += 1
            }
            dest = engine.substring(NSRange(location: start, length: p - start))
        }
        while p < rangeEnd, isWhitespaceOrNewline(units[p]) { p += 1 }
        if p < rangeEnd, (units[p] == CharKind.quote || units[p] == CharKind.singleQuote || units[p] == CharKind.openParen) {
            let closeCh: UInt16 = units[p] == CharKind.openParen ? CharKind.closeParen : units[p]
            p += 1
            while p < rangeEnd, units[p] != closeCh {
                if units[p] == CharKind.backslash, p + 1 < rangeEnd { p += 2 } else { p += 1 }
            }
            guard p < rangeEnd else { return nil }
            p += 1
            while p < rangeEnd, isWhitespaceOrNewline(units[p]) { p += 1 }
        }
        guard p < rangeEnd, units[p] == CharKind.closeParen else { return nil }
        p += 1
        return (dest, p)
    }

    func isWhitespaceOrNewline(_ u: UInt16) -> Bool { u == CharKind.space || u == CharKind.tab || u == 0x0A || u == 0x0D }

    // MARK: - Wiki links

    func tryWikiLink() -> Bool {
        let start = pos
        var p = pos + 2
        var pipePos = -1
        while p < rangeEnd {
            if units[p] == CharKind.closeBracket, p + 1 < rangeEnd, units[p + 1] == CharKind.closeBracket { break }
            if units[p] == CharKind.pipe, pipePos == -1 { pipePos = p }
            if units[p] == 0x0A || units[p] == 0x0D { return false }
            p += 1
        }
        guard p + 1 < rangeEnd else { return false }
        let targetEnd = pipePos >= 0 ? pipePos : p
        let target = engine.substring(NSRange(location: start + 2, length: targetEnd - (start + 2)))
        let innerStart = pipePos >= 0 ? pipePos + 1 : start + 2
        let innerRange = NSRange(location: innerStart, length: p - innerStart)
        flushText(before: start)
        var children: [MarkdownInline] = []
        if innerRange.length > 0 {
            children = [MarkdownInline(kind: .text, range: innerRange)]
        }
        appendNode(.wikiLink(target: target, open: NSRange(location: start, length: 2), close: NSRange(location: p, length: 2)), range: NSRange(location: start, length: p + 2 - start), children: children)
        pos = p + 2
        textStart = pos
        return true
    }

    // MARK: - Tags

    func tryTag() -> Bool {
        let start = pos
        let beforeOK: Bool
        if start == contentStart || excludedRangeAt(start) != nil {
            beforeOK = true
        } else {
            let b = decodeScalarBefore(units, at: start)
            beforeOK = b.map { isUnicodeWhitespace($0.scalar) } ?? true
        }
        guard beforeOK else { return false }
        var p = start + 1
        guard p < rangeEnd, let (scalar0, w0) = decodeScalar(units, at: p), scalar0.properties.isAlphabetic else { return false }
        p += w0
        while p < rangeEnd {
            let u = units[p]
            if CharKind.isASCIIAlnum(u) || u == CharKind.underscore || u == CharKind.dash || u == CharKind.slash {
                p += 1
            } else if u >= 0x80, let (s, w) = decodeScalar(units, at: p), s.properties.isAlphabetic || (0x30...0x39).contains(s.value) {
                p += w
            } else {
                break
            }
        }
        flushText(before: start)
        let name = engine.substring(NSRange(location: start + 1, length: p - (start + 1)))
        appendNode(.tag(name: name), range: NSRange(location: start, length: p - start))
        pos = p
        textStart = p
        return true
    }

    // MARK: - Bare URLs

    /// Precomputed once (not per character scanned) since `tryBareURL` is attempted at almost
    /// every plain-text position when bare URL recognition is enabled.
    private static let bareURLPrefixes: [(units: [UInt16], isWWW: Bool)] = [
        (Array("https://".utf16), false),
        (Array("http://".utf16), false),
        (Array("www.".utf16), true),
    ]

    func tryBareURL() -> Bool {
        let start = pos
        // Fast-path bail out before any prefix comparison: a bare URL can't start mid-word.
        let firstUnit = units[start]
        if firstUnit != 0x68 /* h */ && firstUnit != 0x77 /* w */ { return false }
        if start > contentStart, excludedRangeAt(start) == nil, let b = decodeScalarBefore(units, at: start), b.scalar.value < 0x80, CharKind.isASCIIAlnum(UInt16(b.scalar.value)) {
            return false
        }
        for (putf16, isWWW) in Self.bareURLPrefixes {
            guard start + putf16.count <= rangeEnd else { continue }
            var matches = true
            for k in 0..<putf16.count where units[start + k] != putf16[k] { matches = false; break }
            guard matches else { continue }
            var p = start + putf16.count
            while p < rangeEnd, !isWhitespaceOrNewline(units[p]), units[p] != CharKind.lessThan, units[p] != CharKind.greaterThan {
                p += 1
            }
            while p > start + putf16.count {
                let last = units[p - 1]
                if last == CharKind.dot || last == 0x2C || last == CharKind.colon || last == 0x3B || last == CharKind.bang || last == 0x3F || last == CharKind.closeParen {
                    p -= 1
                } else {
                    break
                }
            }
            flushText(before: start)
            let text = engine.substring(NSRange(location: start, length: p - start))
            let dest = isWWW ? "http://\(text)" : text
            appendNode(.bareURL(destination: dest), range: NSRange(location: start, length: p - start))
            pos = p
            textStart = p
            return true
        }
        return false
    }
}
