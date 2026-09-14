import Foundation

/// One physical line, tracked with a possibly-adjusted "content start" (after ancestor
/// containers have consumed their markers / indentation for this recursion level).
struct CtxLine {
    var lineIndex: Int
    var start: Int
}

/// Mutable engine that walks physical lines once with a recursive-descent container parser.
/// Not `Sendable`; a fresh instance is created per `parse(_:)` call and never escapes it.
final class BlockEngine {
    let units: [UInt16]
    let lines: [MarkdownLine]
    let options: MarkdownParserOptions
    var linkReferences: [String: String] = [:]

    init(units: [UInt16], lines: [MarkdownLine], options: MarkdownParserOptions) {
        self.units = units
        self.lines = lines
        self.options = options
    }

    func run() -> [MarkdownBlock] {
        var ctx: [CtxLine] = []
        ctx.reserveCapacity(lines.count)
        for i in 0..<lines.count { ctx.append(CtxLine(lineIndex: i, start: lines[i].range.location)) }
        return parseBlockSequence(ctx, depth: 0, ancestorMarkers: [])
    }

    func substring(_ range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        // Build directly from a pointer into `units` instead of first copying the slice into a
        // throwaway `Array` (the previous `Array(units[...])` allocated and populated a second
        // buffer purely to hand its contents to `String.init`).
        return units.withUnsafeBufferPointer { buf in
            String(utf16CodeUnits: buf.baseAddress! + range.location, count: range.length)
        }
    }

    // MARK: - Low-level line helpers

    @inline(__always) func lineRawEnd(_ line: CtxLine) -> Int { NSMaxRange(lines[line.lineIndex].range) }

    @inline(__always) func rawRange(_ line: CtxLine) -> NSRange {
        NSRange(location: line.start, length: lineRawEnd(line) - line.start)
    }

    /// Consumes leading spaces/tabs from `from` (tabs advance to the next multiple-of-4 column).
    /// Returns the accumulated width and the offset right after all leading whitespace.
    func indentWidth(from: Int, to: Int) -> (width: Int, end: Int) {
        var width = 0
        var p = from
        while p < to {
            if units[p] == CharKind.tab {
                width += 4 - (width % 4)
            } else if units[p] == CharKind.space {
                width += 1
            } else {
                break
            }
            p += 1
        }
        return (width, p)
    }

    /// Width of an arbitrary (already-known-whitespace-or-marker) span, tab-aware.
    func columnWidth(from: Int, to: Int) -> Int {
        var width = 0
        var p = from
        while p < to {
            if units[p] == CharKind.tab {
                width += 4 - (width % 4)
            } else {
                width += 1
            }
            p += 1
        }
        return width
    }

    /// Advances from `from` consuming leading whitespace until at least `targetWidth` columns
    /// have been consumed (or a non-whitespace char / `to` is reached).
    func advanceByWidth(from: Int, to: Int, targetWidth: Int) -> Int {
        var width = 0
        var p = from
        while p < to, width < targetWidth {
            if units[p] == CharKind.tab {
                width += 4 - (width % 4)
            } else if units[p] == CharKind.space {
                width += 1
            } else {
                break
            }
            p += 1
        }
        return p
    }

    @inline(__always) func isBlank(_ line: CtxLine) -> Bool {
        let end = lineRawEnd(line)
        return indentWidth(from: line.start, to: end).end == end
    }

    func filteredMarkers(_ markers: [NSRange], within range: NSRange) -> [NSRange] {
        // Most blocks (anything not nested in a blockquote) have no ancestor markers at all;
        // skip the filter+sort allocation dance entirely for that overwhelmingly common case.
        guard !markers.isEmpty else { return markers }
        let lo = range.location, hi = NSMaxRange(range)
        return markers.filter { $0.location >= lo && NSMaxRange($0) <= hi }.sorted { $0.location < $1.location }
    }

    func lineIsExactly(_ line: CtxLine, _ s: String) -> Bool {
        let end = lineRawEnd(line)
        var pos = line.start
        while pos < end, CharKind.isSpaceOrTab(units[pos]) { pos += 1 }
        var trimEnd = end
        while trimEnd > pos, CharKind.isSpaceOrTab(units[trimEnd - 1]) { trimEnd -= 1 }
        let target = Array(s.utf16)
        guard trimEnd - pos == target.count else { return false }
        for k in 0..<target.count where units[pos + k] != target[k] { return false }
        return true
    }

    // MARK: - Block-start matchers

    func matchThematicBreak(_ line: CtxLine) -> Bool {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return false }
        var pos = wend
        guard pos < end else { return false }
        let ch = units[pos]
        guard ch == CharKind.dash || ch == CharKind.asterisk || ch == CharKind.underscore else { return false }
        var count = 0
        while pos < end {
            let u = units[pos]
            if u == ch { count += 1; pos += 1 } else if CharKind.isSpaceOrTab(u) { pos += 1 } else { return false }
        }
        return count >= 3
    }

    func matchSetextUnderline(_ line: CtxLine) -> Int? {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return nil }
        var pos = wend
        guard pos < end else { return nil }
        let ch = units[pos]
        guard ch == CharKind.equals || ch == CharKind.dash else { return nil }
        var count = 0
        while pos < end {
            let u = units[pos]
            if u == ch { count += 1; pos += 1 } else if CharKind.isSpaceOrTab(u) { pos += 1 } else { return nil }
        }
        guard count >= 1 else { return nil }
        return ch == CharKind.equals ? 1 : 2
    }

    struct ATXMatch { var level: Int; var markerRange: NSRange; var closingRange: NSRange?; var contentStart: Int; var contentEnd: Int }

    func matchATXHeading(_ line: CtxLine) -> ATXMatch? {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return nil }
        var pos = wend
        var level = 0
        while pos < end, units[pos] == CharKind.hash, level < 6 { pos += 1; level += 1 }
        guard level >= 1 else { return nil }
        if pos < end, units[pos] == CharKind.hash { return nil }
        // Editor rule: the hashes must be followed by whitespace. A bare `#` with nothing after it stays
        // paragraph text so the character does not vanish the moment it is typed in the hidden-syntax editor.
        guard pos < end, CharKind.isSpaceOrTab(units[pos]) else { return nil }
        var markerEnd = pos
        while markerEnd < end, CharKind.isSpaceOrTab(units[markerEnd]) { markerEnd += 1 }
        let markerRange = NSRange(location: wend, length: markerEnd - wend)

        var trimEnd = end
        while trimEnd > markerEnd, CharKind.isSpaceOrTab(units[trimEnd - 1]) { trimEnd -= 1 }
        var hashRunStart = trimEnd
        while hashRunStart > markerEnd, units[hashRunStart - 1] == CharKind.hash { hashRunStart -= 1 }
        var contentEnd = trimEnd
        var closingRange: NSRange? = nil
        if hashRunStart < trimEnd {
            if hashRunStart == markerEnd {
                closingRange = NSRange(location: hashRunStart, length: trimEnd - hashRunStart)
                contentEnd = hashRunStart
            } else if CharKind.isSpaceOrTab(units[hashRunStart - 1]) {
                var closeStart = hashRunStart
                while closeStart > markerEnd, CharKind.isSpaceOrTab(units[closeStart - 1]) { closeStart -= 1 }
                closingRange = NSRange(location: closeStart, length: trimEnd - closeStart)
                contentEnd = closeStart
            }
        }
        return ATXMatch(level: level, markerRange: markerRange, closingRange: closingRange, contentStart: markerEnd, contentEnd: contentEnd)
    }

    struct FenceMatch { var char: UInt16; var length: Int; var markerStart: Int; var infoStart: Int; var infoEnd: Int }

    func matchFence(_ line: CtxLine) -> FenceMatch? {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return nil }
        var pos = wend
        guard pos < end else { return nil }
        let ch = units[pos]
        guard ch == CharKind.backtick || ch == CharKind.tilde else { return nil }
        var count = 0
        while pos < end, units[pos] == ch { pos += 1; count += 1 }
        guard count >= 3 else { return nil }
        var infoStart = pos
        while infoStart < end, CharKind.isSpaceOrTab(units[infoStart]) { infoStart += 1 }
        var infoEnd = end
        while infoEnd > infoStart, CharKind.isSpaceOrTab(units[infoEnd - 1]) { infoEnd -= 1 }
        if ch == CharKind.backtick {
            for p in infoStart..<infoEnd where units[p] == CharKind.backtick { return nil }
        }
        return FenceMatch(char: ch, length: count, markerStart: wend, infoStart: infoStart, infoEnd: infoEnd)
    }

    func matchClosingFence(_ line: CtxLine, char: UInt16, minLength: Int) -> Bool {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return false }
        var pos = wend
        var count = 0
        while pos < end, units[pos] == char { pos += 1; count += 1 }
        guard count >= minLength else { return false }
        while pos < end {
            guard CharKind.isSpaceOrTab(units[pos]) else { return false }
            pos += 1
        }
        return true
    }

    func matchBlockquoteMarker(_ line: CtxLine) -> Int? {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return nil }
        var pos = wend
        guard pos < end, units[pos] == CharKind.greaterThan else { return nil }
        pos += 1
        if pos < end, CharKind.isSpaceOrTab(units[pos]) { pos += 1 }
        return pos
    }

    struct ListMarkerMatch { var ordered: Bool; var bulletChar: UInt16?; var ordinal: Int?; var markerStart: Int; var afterMarker: Int }

    func matchListMarker(_ line: CtxLine) -> ListMarkerMatch? {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return nil }
        let pos = wend
        guard pos < end else { return nil }
        let u = units[pos]
        if u == CharKind.dash || u == CharKind.plus || u == CharKind.asterisk {
            let next = pos + 1
            if next >= end || CharKind.isSpaceOrTab(units[next]) {
                return ListMarkerMatch(ordered: false, bulletChar: u, ordinal: nil, markerStart: pos, afterMarker: next)
            }
            return nil
        }
        if CharKind.isASCIIDigit(u) {
            var p = pos
            var digits = 0
            var value = 0
            while p < end, CharKind.isASCIIDigit(units[p]), digits < 9 {
                value = value * 10 + Int(units[p] - 0x30)
                p += 1; digits += 1
            }
            guard p < end, (units[p] == CharKind.dot || units[p] == CharKind.closeParen) else { return nil }
            let markerEnd = p + 1
            if markerEnd >= end || CharKind.isSpaceOrTab(units[markerEnd]) {
                return ListMarkerMatch(ordered: true, bulletChar: nil, ordinal: value, markerStart: pos, afterMarker: markerEnd)
            }
            return nil
        }
        return nil
    }

    func listItemContentInfo(_ line: CtxLine, marker: ListMarkerMatch) -> (markerRange: NSRange, contentStart: Int, task: MarkdownTaskState?) {
        let end = lineRawEnd(line)
        let pos = marker.afterMarker
        if pos >= end {
            return (NSRange(location: marker.markerStart, length: pos - marker.markerStart), pos, nil)
        }
        var wsCount = 0
        var p = pos
        while p < end, CharKind.isSpaceOrTab(units[p]) { p += 1; wsCount += 1 }
        var contentStart: Int
        if p >= end {
            contentStart = min(pos + 1, end)
        } else if wsCount == 0 {
            contentStart = pos
        } else if wsCount >= 5 {
            contentStart = pos + 1
        } else {
            contentStart = p
        }
        var markerRange = NSRange(location: marker.markerStart, length: contentStart - marker.markerStart)
        var task: MarkdownTaskState? = nil
        if contentStart + 2 < end, units[contentStart] == CharKind.openBracket, units[contentStart + 2] == CharKind.closeBracket {
            let c = units[contentStart + 1]
            if c == CharKind.space || c == 0x78 || c == 0x58 {
                let afterTask = contentStart + 3
                if afterTask >= end || CharKind.isSpaceOrTab(units[afterTask]) {
                    let isChecked = (c == 0x78 || c == 0x58)
                    let taskMarkerRange = NSRange(location: contentStart, length: 3)
                    var newContentStart = afterTask
                    var extra = 3
                    if afterTask < end, CharKind.isSpaceOrTab(units[afterTask]) {
                        newContentStart = afterTask + 1
                        extra += 1
                    }
                    task = MarkdownTaskState(isChecked: isChecked, markerRange: taskMarkerRange)
                    markerRange = NSRange(location: marker.markerStart, length: markerRange.length + extra)
                    contentStart = newContentStart
                }
            }
        }
        return (markerRange, contentStart, task)
    }

    /// Detects a real HTML block start (`<tag ...>`, `</tag>`, `<!--`), not just any `<letter`
    /// (which would otherwise swallow autolinks like `<https://x>` or `<foo@bar.com>`).
    func isHTMLBlockStart(_ line: CtxLine) -> Bool {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return false }
        var pos = wend
        guard pos < end, units[pos] == CharKind.lessThan else { return false }
        pos += 1
        guard pos < end else { return false }
        if units[pos] == CharKind.bang { return true }
        var isClosing = false
        if units[pos] == CharKind.slash { isClosing = true; pos += 1 }
        guard pos < end, CharKind.isASCIIAlpha(units[pos]) else { return false }
        while pos < end, CharKind.isASCIIAlnum(units[pos]) || units[pos] == CharKind.dash { pos += 1 }
        guard pos < end else { return true }
        let u = units[pos]
        if CharKind.isSpaceOrTab(u) || u == CharKind.greaterThan { return true }
        if !isClosing, u == CharKind.slash, pos + 1 < end, units[pos + 1] == CharKind.greaterThan { return true }
        return false
    }

    func matchLinkReferenceDefinition(_ line: CtxLine) -> (label: String, destination: String)? {
        let end = lineRawEnd(line)
        let (w, wend) = indentWidth(from: line.start, to: end)
        if w > 3 { return nil }
        var pos = wend
        guard pos < end, units[pos] == CharKind.openBracket else { return nil }
        pos += 1
        let labelStart = pos
        while pos < end, units[pos] != CharKind.closeBracket { pos += 1 }
        guard pos < end, pos > labelStart else { return nil }
        let labelEnd = pos
        pos += 1
        guard pos < end, units[pos] == CharKind.colon else { return nil }
        pos += 1
        while pos < end, CharKind.isSpaceOrTab(units[pos]) { pos += 1 }
        guard pos < end else { return nil }
        var destStart = pos
        var destEnd: Int
        if units[pos] == CharKind.lessThan {
            pos += 1
            destStart = pos
            while pos < end, units[pos] != CharKind.greaterThan { pos += 1 }
            guard pos < end else { return nil }
            destEnd = pos
            pos += 1
        } else {
            destStart = pos
            while pos < end, !CharKind.isSpaceOrTab(units[pos]) { pos += 1 }
            destEnd = pos
        }
        guard destEnd >= destStart else { return nil }
        var p = pos
        while p < end, CharKind.isSpaceOrTab(units[p]) { p += 1 }
        if p < end {
            let tch = units[p]
            guard tch == CharKind.quote || tch == CharKind.singleQuote || tch == CharKind.openParen else { return nil }
            let closeCh: UInt16 = tch == CharKind.openParen ? CharKind.closeParen : tch
            p += 1
            while p < end, units[p] != closeCh { p += 1 }
            guard p < end else { return nil }
            p += 1
            while p < end, CharKind.isSpaceOrTab(units[p]) { p += 1 }
            guard p >= end else { return nil }
        }
        let label = substring(NSRange(location: labelStart, length: labelEnd - labelStart))
        let dest = substring(NSRange(location: destStart, length: destEnd - destStart))
        return (label, dest)
    }

    func isTableDelimiterRow(_ line: CtxLine) -> Bool {
        let end = lineRawEnd(line)
        var pos = line.start
        var sawCell = false
        var sawDash = false
        while pos < end {
            let u = units[pos]
            if u == CharKind.pipe || CharKind.isSpaceOrTab(u) { pos += 1; continue }
            if u == CharKind.colon || u == CharKind.dash {
                if u == CharKind.dash { sawDash = true }
                sawCell = true
                pos += 1
                continue
            }
            return false
        }
        return sawDash && sawCell
    }

    func containsPipe(_ line: CtxLine) -> Bool {
        let end = lineRawEnd(line)
        for p in line.start..<end where units[p] == CharKind.pipe { return true }
        return false
    }

    /// Whether `line` looks like the start of some other block (used to decide paragraph
    /// interruption and blockquote lazy-continuation eligibility).
    func startsNewBlock(_ line: CtxLine) -> Bool {
        if isBlank(line) { return true }
        if matchATXHeading(line) != nil { return true }
        if matchThematicBreak(line) { return true }
        if matchFence(line) != nil { return true }
        if matchBlockquoteMarker(line) != nil { return true }
        if matchListMarker(line) != nil { return true }
        if isHTMLBlockStart(line) { return true }
        return false
    }

    // MARK: - Recursive-descent block sequence parser

    func parseBlockSequence(_ ctx: [CtxLine], depth: Int, ancestorMarkers: [NSRange]) -> [MarkdownBlock] {
        var results: [MarkdownBlock] = []
        var i = 0
        while i < ctx.count {
            let line = ctx[i]
            if isBlank(line) {
                results.append(MarkdownBlock(kind: .blank, range: rawRange(line)))
                i += 1
                continue
            }
            if i == 0, line.lineIndex == 0, options.recognizesFrontMatter, let fm = tryFrontMatter(ctx, at: i) {
                results.append(fm.block)
                i = fm.nextIndex
                continue
            }
            let end = lineRawEnd(line)
            if indentWidth(from: line.start, to: end).width >= 4 {
                let (nextIndex, block) = gatherIndentedCode(ctx, from: i)
                results.append(block)
                i = nextIndex
                continue
            }
            if matchThematicBreak(line) {
                results.append(MarkdownBlock(kind: .thematicBreak, range: rawRange(line)))
                i += 1
                continue
            }
            if let atx = matchATXHeading(line) {
                results.append(makeHeadingBlock(line: line, atx: atx, ancestorMarkers: ancestorMarkers))
                i += 1
                continue
            }
            if let fence = matchFence(line) {
                let (nextIndex, block) = gatherFencedCode(ctx, from: i, fence: fence)
                results.append(block)
                i = nextIndex
                continue
            }
            if matchBlockquoteMarker(line) != nil {
                let (nextIndex, block) = gatherBlockquote(ctx, from: i, depth: depth, ancestorMarkers: ancestorMarkers)
                results.append(block)
                i = nextIndex
                continue
            }
            if matchListMarker(line) != nil {
                let (nextIndex, block) = gatherList(ctx, from: i, depth: depth, ancestorMarkers: ancestorMarkers)
                results.append(block)
                i = nextIndex
                continue
            }
            if isHTMLBlockStart(line) {
                let (nextIndex, block) = gatherHTMLBlock(ctx, from: i)
                results.append(block)
                i = nextIndex
                continue
            }
            if let refDef = matchLinkReferenceDefinition(line) {
                let key = normalizeLinkLabel(refDef.label)
                if linkReferences[key] == nil { linkReferences[key] = refDef.destination }
                results.append(MarkdownBlock(kind: .linkReferenceDefinition(label: key, destination: refDef.destination), range: rawRange(line)))
                i += 1
                continue
            }
            if containsPipe(line), i + 1 < ctx.count, isTableDelimiterRow(ctx[i + 1]) {
                let (nextIndex, block) = gatherTable(ctx, from: i)
                results.append(block)
                i = nextIndex
                continue
            }
            let (nextIndex, block) = gatherParagraph(ctx, from: i, ancestorMarkers: ancestorMarkers)
            results.append(block)
            i = nextIndex
        }
        return results
    }

    // MARK: - Leaf gatherers

    func gatherIndentedCode(_ ctx: [CtxLine], from start: Int) -> (Int, MarkdownBlock) {
        var j = start
        var lastContentIndex = start
        while j < ctx.count {
            let line = ctx[j]
            if isBlank(line) { j += 1; continue }
            let w = indentWidth(from: line.start, to: lineRawEnd(line)).width
            if w >= 4 { lastContentIndex = j; j += 1 } else { break }
        }
        let firstLine = ctx[start]
        let lastLine = ctx[lastContentIndex]
        let range = NSRange(location: firstLine.start, length: lineRawEnd(lastLine) - firstLine.start)
        return (lastContentIndex + 1, MarkdownBlock(kind: .indentedCode, range: range))
    }

    func gatherFencedCode(_ ctx: [CtxLine], from start: Int, fence: FenceMatch) -> (Int, MarkdownBlock) {
        let openingLine = ctx[start]
        let openingFenceRange = NSRange(location: fence.markerStart, length: fence.length)
        let info = substring(NSRange(location: fence.infoStart, length: fence.infoEnd - fence.infoStart))
        var j = start + 1
        var closingFenceRange: NSRange? = nil
        var lastContentLineIndex: Int? = nil
        while j < ctx.count {
            if matchClosingFence(ctx[j], char: fence.char, minLength: fence.length) {
                closingFenceRange = rawRange(ctx[j])
                break
            }
            lastContentLineIndex = j
            j += 1
        }
        let contentRange: NSRange
        if let lastIdx = lastContentLineIndex {
            let firstContentLine = ctx[start + 1]
            let lastContentLine = ctx[lastIdx]
            contentRange = NSRange(location: firstContentLine.start, length: lineRawEnd(lastContentLine) - firstContentLine.start)
        } else {
            let pos = NSMaxRange(lines[openingLine.lineIndex].terminator)
            contentRange = NSRange(location: pos, length: 0)
        }
        let endIndex: Int
        let blockEndLineIndex: Int
        if closingFenceRange != nil {
            endIndex = j + 1
            blockEndLineIndex = j
        } else {
            endIndex = ctx.count
            blockEndLineIndex = ctx.count - 1
        }
        let blockRange = NSRange(location: openingLine.start, length: lineRawEnd(ctx[blockEndLineIndex]) - openingLine.start)
        let kind = MarkdownBlockKind.fencedCode(info: info, openingFence: openingFenceRange, closingFence: closingFenceRange, contentRange: contentRange)
        return (endIndex, MarkdownBlock(kind: kind, range: blockRange))
    }

    func gatherHTMLBlock(_ ctx: [CtxLine], from start: Int) -> (Int, MarkdownBlock) {
        var j = start + 1
        while j < ctx.count, !isBlank(ctx[j]) { j += 1 }
        let firstLine = ctx[start]
        let lastLine = ctx[j - 1]
        let range = NSRange(location: firstLine.start, length: lineRawEnd(lastLine) - firstLine.start)
        return (j, MarkdownBlock(kind: .htmlBlock, range: range))
    }

    func gatherTable(_ ctx: [CtxLine], from start: Int) -> (Int, MarkdownBlock) {
        var j = start + 2
        while j < ctx.count, !isBlank(ctx[j]), containsPipe(ctx[j]) { j += 1 }
        let firstLine = ctx[start]
        let lastLine = ctx[j - 1]
        let range = NSRange(location: firstLine.start, length: lineRawEnd(lastLine) - firstLine.start)
        return (j, MarkdownBlock(kind: .table, range: range))
    }

    func tryFrontMatter(_ ctx: [CtxLine], at start: Int) -> (nextIndex: Int, block: MarkdownBlock)? {
        guard lineIsExactly(ctx[start], "---") else { return nil }
        var j = start + 1
        while j < ctx.count {
            if lineIsExactly(ctx[j], "---") || lineIsExactly(ctx[j], "...") {
                let firstLine = ctx[start]
                let lastLine = ctx[j]
                let range = NSRange(location: firstLine.start, length: lineRawEnd(lastLine) - firstLine.start)
                return (j + 1, MarkdownBlock(kind: .frontMatter, range: range))
            }
            j += 1
        }
        return nil
    }

    func gatherBlockquote(_ ctx: [CtxLine], from start: Int, depth: Int, ancestorMarkers: [NSRange]) -> (Int, MarkdownBlock) {
        var markerRanges: [NSRange] = []
        var innerLines: [CtxLine] = []
        var trailingParagraph = false
        var j = start
        while j < ctx.count {
            let line = ctx[j]
            if isBlank(line) { break }
            if let markerEnd = matchBlockquoteMarker(line) {
                markerRanges.append(NSRange(location: line.start, length: markerEnd - line.start))
                let innerLine = CtxLine(lineIndex: line.lineIndex, start: markerEnd)
                trailingParagraph = !startsNewBlock(innerLine)
                innerLines.append(innerLine)
                j += 1
            } else if trailingParagraph, !startsNewBlock(line) {
                innerLines.append(line)
                j += 1
            } else {
                break
            }
        }
        let firstLine = ctx[start]
        let lastLine = ctx[j - 1]
        let range = NSRange(location: firstLine.start, length: lineRawEnd(lastLine) - firstLine.start)
        let children = parseBlockSequence(innerLines, depth: depth, ancestorMarkers: ancestorMarkers + markerRanges)
        return (j, MarkdownBlock(kind: .blockquote(markerRanges: markerRanges), range: range, children: children))
    }

    func gatherListItemLines(_ ctx: [CtxLine], itemIndex: Int, itemFirstLine: CtxLine, contentColumnWidth: Int) -> (endIndex: Int, childLines: [CtxLine]) {
        // A fully empty first line (e.g. "-" or "- " alone) contributes no content line at all,
        // so an empty item ends up with zero children rather than a spurious blank block.
        var childLines: [CtxLine] = itemFirstLine.start < lineRawEnd(itemFirstLine) ? [itemFirstLine] : []
        var j = itemIndex + 1
        var trailingBlankCount = 0
        while j < ctx.count {
            let line = ctx[j]
            if isBlank(line) {
                childLines.append(line)
                trailingBlankCount += 1
                j += 1
                continue
            }
            let end = lineRawEnd(line)
            let w = indentWidth(from: line.start, to: end).width
            if w >= contentColumnWidth {
                let newStart = advanceByWidth(from: line.start, to: end, targetWidth: contentColumnWidth)
                childLines.append(CtxLine(lineIndex: line.lineIndex, start: newStart))
                trailingBlankCount = 0
                j += 1
            } else {
                break
            }
        }
        while trailingBlankCount > 0 {
            childLines.removeLast()
            trailingBlankCount -= 1
            j -= 1
        }
        return (j, childLines)
    }

    func gatherList(_ ctx: [CtxLine], from start: Int, depth: Int, ancestorMarkers: [NSRange]) -> (Int, MarkdownBlock) {
        guard let firstMarker = matchListMarker(ctx[start]) else {
            // Unreachable: caller already verified a match exists.
            return (start + 1, MarkdownBlock(kind: .list(ordered: false, start: 1, tight: true), range: rawRange(ctx[start])))
        }
        var idx = start
        var items: [MarkdownBlock] = []
        var loose = false
        let startOrdinal = firstMarker.ordinal ?? 1
        while idx < ctx.count {
            guard let marker = matchListMarker(ctx[idx]), marker.ordered == firstMarker.ordered, marker.bulletChar == firstMarker.bulletChar else { break }
            let (markerRangeRaw, contentStart, task) = listItemContentInfo(ctx[idx], marker: marker)
            let contentColumnWidth = columnWidth(from: ctx[idx].start, to: contentStart)
            let itemFirstLine = CtxLine(lineIndex: ctx[idx].lineIndex, start: contentStart)
            let (endIdx, childLines) = gatherListItemLines(ctx, itemIndex: idx, itemFirstLine: itemFirstLine, contentColumnWidth: contentColumnWidth)
            let itemChildren = parseBlockSequence(childLines, depth: depth + 1, ancestorMarkers: ancestorMarkers)
            if itemChildren.contains(where: { if case .blank = $0.kind { return true }; return false }) {
                loose = true
            }
            let firstRawLine = ctx[idx]
            let lastLineIdxForRange = max(endIdx - 1, idx)
            let itemRange = NSRange(location: firstRawLine.start, length: lineRawEnd(ctx[lastLineIdxForRange]) - firstRawLine.start)
            let item = MarkdownBlock(kind: .listItem(markerRange: markerRangeRaw, ordinal: marker.ordinal, task: task, depth: depth), range: itemRange, children: itemChildren)
            items.append(item)
            idx = endIdx

            var blanksBetween: [MarkdownBlock] = []
            var scanIdx = idx
            while scanIdx < ctx.count, isBlank(ctx[scanIdx]) {
                blanksBetween.append(MarkdownBlock(kind: .blank, range: rawRange(ctx[scanIdx])))
                scanIdx += 1
            }
            if !blanksBetween.isEmpty {
                if scanIdx < ctx.count, let nextMarker = matchListMarker(ctx[scanIdx]), nextMarker.ordered == firstMarker.ordered, nextMarker.bulletChar == firstMarker.bulletChar {
                    loose = true
                    items.append(contentsOf: blanksBetween)
                    idx = scanIdx
                    continue
                } else {
                    break
                }
            }
        }
        let firstLine = ctx[start]
        let lastLine = ctx[idx - 1]
        let range = NSRange(location: firstLine.start, length: lineRawEnd(lastLine) - firstLine.start)
        let listKind = MarkdownBlockKind.list(ordered: firstMarker.ordered, start: startOrdinal, tight: !loose)
        return (idx, MarkdownBlock(kind: listKind, range: range, children: items))
    }

    func gatherParagraph(_ ctx: [CtxLine], from start: Int, ancestorMarkers: [NSRange]) -> (Int, MarkdownBlock) {
        var j = start + 1
        while j < ctx.count {
            let line = ctx[j]
            if isBlank(line) { break }
            if let level = matchSetextUnderline(line) {
                let firstLine = ctx[start]
                let underlineRaw = rawRange(line)
                let textRange = NSRange(location: firstLine.start, length: lineRawEnd(ctx[j - 1]) - firstLine.start)
                let excluded = filteredMarkers(ancestorMarkers, within: textRange)
                let inlines = parseInline(range: textRange, excluded: excluded, allowLinks: true)
                let block = MarkdownBlock(kind: .setextHeading(level: level, underlineRange: underlineRaw),
                                           range: NSRange(location: firstLine.start, length: NSMaxRange(underlineRaw) - firstLine.start),
                                           inlines: inlines)
                return (j + 1, block)
            }
            if startsNewBlock(line) { break }
            j += 1
        }
        let firstLine = ctx[start]
        let lastLine = ctx[j - 1]
        let range = NSRange(location: firstLine.start, length: lineRawEnd(lastLine) - firstLine.start)
        let excluded = filteredMarkers(ancestorMarkers, within: range)
        let inlines = parseInline(range: range, excluded: excluded, allowLinks: true)
        return (j, MarkdownBlock(kind: .paragraph, range: range, inlines: inlines))
    }

    func makeHeadingBlock(line: CtxLine, atx: ATXMatch, ancestorMarkers: [NSRange]) -> MarkdownBlock {
        let raw = rawRange(line)
        let contentRange = NSRange(location: atx.contentStart, length: atx.contentEnd - atx.contentStart)
        let excluded = filteredMarkers(ancestorMarkers, within: contentRange)
        let inlines = contentRange.length > 0 ? parseInline(range: contentRange, excluded: excluded, allowLinks: true) : []
        let blockRange = NSRange(location: line.start, length: NSMaxRange(raw) - line.start)
        return MarkdownBlock(kind: .heading(level: atx.level, markerRange: atx.markerRange, closingRange: atx.closingRange), range: blockRange, inlines: inlines)
    }
}
