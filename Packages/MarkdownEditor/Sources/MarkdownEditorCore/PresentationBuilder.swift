import Foundation

/// Builds a `Presentation` (display text, source/display map, and per-line styling) from a
/// parsed `MarkdownTree`. Pure and safe to call off the main actor.
///
/// Overview of the algorithm:
/// 1. A single depth-first pass over `tree.blocks` collects, per source line, its
///    `BlockPresentationKind` / quote depth / list depth / list marker, plus two flat lists of
///    spans in *source* coordinates: `delimiterSpans` (syntax markers that `.rich` mode hides
///    and `.source` mode dims) and `contentSpans` (visible content that always carries a style,
///    e.g. emphasis text, link text, raw syntax lines such as fences/front matter).
/// 2. The hidden runs (delimiter spans, plus the `\r` of every `\r\n` terminator) become a
///    `SourceDisplayMap` in `.rich` mode, or the identity map in `.source` mode.
/// 3. The display text is assembled once from the source's UTF-16 units, skipping hidden runs.
/// 4. Per-line display ranges come straight from the map; style spans are converted to display
///    coordinates, clipped to line boundaries, and adjacent identical runs are merged.
public struct PresentationBuilder: PresentationBuilding {
    public init() {}

    public func build(source: String, tree: MarkdownTree, mode: EditorMode) -> Presentation {
        let utf16 = Array(source.utf16)
        let sourceLength = utf16.count
        let sourceLines: [MarkdownLine] = tree.lines.isEmpty
            ? [MarkdownLine(range: NSRange(location: 0, length: sourceLength), terminator: NSRange(location: sourceLength, length: 0))]
            : tree.lines

        // MARK: Pass 1 — walk blocks, collect per-line info and source-coordinate spans.

        var lineInfos = [LineInfo?](repeating: nil, count: sourceLines.count)
        var delimiterSpans: [DelimiterSpan] = []
        var contentSpans: [ContentSpan] = []
        delimiterSpans.reserveCapacity(sourceLines.count)
        contentSpans.reserveCapacity(sourceLines.count)
        var markerByLine: [Int: (ListMarker, NSRange?)] = [:]
        var leadingHiddenEnd: [Int: Int] = [:]

        // `lineIndex` is queried, throughout the depth-first `visit` walk below, with offsets
        // that are *almost always* non-decreasing (a container's own range starts at or before
        // its children's, siblings are visited in source order), with one notable exception: a
        // multi-line blockquote's marker ranges are all handled before its child block, whose
        // range can start earlier than the blockquote's later markers (e.g. `> a\n> b`, where the
        // one child paragraph spans both lines but starts right after the first `>`). So this
        // keeps a forward-scanning cursor for the common case — turning what used to be a binary
        // search per query into an amortized O(1) advance — but detects a backward query (cursor
        // now points past `offset`) and falls back to a full binary search, exactly reproducing
        // the original algorithm's result, before resyncing the cursor.
        var lineIndexCursor = 0
        func lineIndex(at offset: Int) -> Int {
            if sourceLines[lineIndexCursor].range.location > offset {
                var lo = 0, hi = sourceLines.count - 1, result = 0
                while lo <= hi {
                    let mid = (lo + hi) / 2
                    if sourceLines[mid].range.location <= offset { result = mid; lo = mid + 1 } else { hi = mid - 1 }
                }
                lineIndexCursor = result
                return result
            }
            while lineIndexCursor + 1 < sourceLines.count, sourceLines[lineIndexCursor + 1].range.location <= offset {
                lineIndexCursor += 1
            }
            return lineIndexCursor
        }

        func lineSpan(of range: NSRange) -> ClosedRange<Int> {
            let startLi = lineIndex(at: range.location)
            let endLi = lineIndex(at: max(range.location, NSMaxRange(range) - 1))
            return startLi...max(startLi, endLi)
        }

        // Quote/list depth for the block currently being visited is threaded down as two plain
        // Ints during the walk (see `visit`) instead of being recomputed from an ancestor-block
        // array at every leaf: the array (`parents + [block]`) previously had to be reallocated
        // and its elements retained (each `MarkdownBlock` carries nested arrays/strings) once per
        // child, at every level of the tree, purely to re-derive these two numbers on demand.
        func assignLines(_ range: NSRange, kind: BlockPresentationKind, quoteDepth: Int, listDepth: Int) {
            for li in lineSpan(of: range) {
                lineInfos[li] = LineInfo(blockKind: kind, quoteDepth: quoteDepth, listDepth: listDepth)
            }
        }

        func fullLineSyntaxSpans(_ range: NSRange) {
            for li in lineSpan(of: range) where sourceLines[li].range.length > 0 {
                contentSpans.append(ContentSpan(range: sourceLines[li].range, style: .syntax, destination: nil))
            }
        }

        func extendedLeadingStart(markerLocation: Int, lineIdx: Int) -> Int {
            let lineStart = sourceLines[lineIdx].range.location
            let boundary = max(lineStart, leadingHiddenEnd[lineIdx] ?? lineStart)
            var pos = markerLocation
            while pos > boundary, utf16[pos - 1] == 0x20 || utf16[pos - 1] == 0x09 {
                pos -= 1
            }
            return pos
        }

        func walkInline(_ node: MarkdownInline, style: InlineStyle, destination: String?) {
            switch node.kind {
            case .text, .softBreak, .htmlInline:
                if !style.isEmpty || destination != nil {
                    contentSpans.append(ContentSpan(range: node.range, style: style, destination: destination))
                }

            case .hardBreak(let markerRange):
                if markerRange.length > 0 { delimiterSpans.append(DelimiterSpan(range: markerRange, attachment: .trailing)) }

            case .emphasis(let open, let close):
                wrapDelimited(node, open: open, close: close, addedStyle: .emphasis, style: style, destination: destination)

            case .strong(let open, let close):
                wrapDelimited(node, open: open, close: close, addedStyle: .strong, style: style, destination: destination)

            case .strikethrough(let open, let close):
                wrapDelimited(node, open: open, close: close, addedStyle: .strikethrough, style: style, destination: destination)

            case .code(let open, let close):
                if open.length > 0 { delimiterSpans.append(DelimiterSpan(range: open, attachment: .leading)) }
                if close.length > 0 { delimiterSpans.append(DelimiterSpan(range: close, attachment: .trailing)) }
                let inner = NSRange(location: NSMaxRange(open), length: max(0, close.location - NSMaxRange(open)))
                if inner.length > 0 { contentSpans.append(ContentSpan(range: inner, style: style.union(.code), destination: destination)) }

            case .link(let dest, let open, let close):
                if open.length > 0 { delimiterSpans.append(DelimiterSpan(range: open, attachment: .leading)) }
                if close.length > 0 { delimiterSpans.append(DelimiterSpan(range: close, attachment: .trailing)) }
                let childStyle = style.union(.link)
                if node.children.isEmpty {
                    let inner = NSRange(location: NSMaxRange(open), length: max(0, close.location - NSMaxRange(open)))
                    if inner.length > 0 { contentSpans.append(ContentSpan(range: inner, style: childStyle, destination: dest)) }
                } else {
                    for child in node.children { walkInline(child, style: childStyle, destination: dest) }
                }

            case .image(let dest, let open, let close):
                if open.length > 0 { delimiterSpans.append(DelimiterSpan(range: open, attachment: .leading)) }
                if close.length > 0 { delimiterSpans.append(DelimiterSpan(range: close, attachment: .trailing)) }
                let childStyle = style.union(.image)
                if node.children.isEmpty {
                    let inner = NSRange(location: NSMaxRange(open), length: max(0, close.location - NSMaxRange(open)))
                    if inner.length > 0 { contentSpans.append(ContentSpan(range: inner, style: childStyle, destination: dest)) }
                } else {
                    for child in node.children { walkInline(child, style: childStyle, destination: dest) }
                }

            case .autolink(let dest, let open, let close):
                if open.length > 0 { delimiterSpans.append(DelimiterSpan(range: open, attachment: .leading)) }
                if close.length > 0 { delimiterSpans.append(DelimiterSpan(range: close, attachment: .trailing)) }
                let inner = NSRange(location: NSMaxRange(open), length: max(0, close.location - NSMaxRange(open)))
                // The spec doesn't state a style for autolink text explicitly (only "hide the angle
                // brackets"); we style it like a link for visual consistency with bareURL/link.
                if inner.length > 0 { contentSpans.append(ContentSpan(range: inner, style: style.union(.link), destination: dest)) }

            case .bareURL(let dest):
                contentSpans.append(ContentSpan(range: node.range, style: style.union(.link), destination: dest))

            case .wikiLink(let target, _, _):
                // Brackets are never hidden or dimmed; the whole node (including them) is one styled span.
                contentSpans.append(ContentSpan(range: node.range, style: style.union(.wikiLink), destination: target))

            case .tag:
                contentSpans.append(ContentSpan(range: node.range, style: style.union(.tag), destination: nil))

            case .escape(let backslashRange):
                if backslashRange.length > 0 { delimiterSpans.append(DelimiterSpan(range: backslashRange, attachment: .leading)) }
                let escapedRange = NSRange(location: NSMaxRange(backslashRange), length: max(0, NSMaxRange(node.range) - NSMaxRange(backslashRange)))
                if !style.isEmpty, escapedRange.length > 0 {
                    contentSpans.append(ContentSpan(range: escapedRange, style: style, destination: destination))
                }
            }
        }

        func wrapDelimited(_ node: MarkdownInline, open: NSRange, close: NSRange, addedStyle: InlineStyle, style: InlineStyle, destination: String?) {
            if open.length > 0 { delimiterSpans.append(DelimiterSpan(range: open, attachment: .leading)) }
            if close.length > 0 { delimiterSpans.append(DelimiterSpan(range: close, attachment: .trailing)) }
            let childStyle = style.union(addedStyle)
            if node.children.isEmpty {
                let inner = NSRange(location: NSMaxRange(open), length: max(0, close.location - NSMaxRange(open)))
                if inner.length > 0 { contentSpans.append(ContentSpan(range: inner, style: childStyle, destination: destination)) }
            } else {
                for child in node.children { walkInline(child, style: childStyle, destination: destination) }
            }
        }

        func walkInlines(_ inlines: [MarkdownInline]) {
            for inline in inlines { walkInline(inline, style: [], destination: nil) }
        }

        for block in tree.blocks {
            visit(block, quoteDepth: 0, listDepth: 0)
        }
        func visit(_ block: MarkdownBlock, quoteDepth: Int, listDepth: Int) {
            switch block.kind {
            case .paragraph:
                assignLines(block.range, kind: .paragraph, quoteDepth: quoteDepth, listDepth: listDepth)
                walkInlines(block.inlines)

            case .heading(let level, let markerRange, let closingRange):
                assignLines(block.range, kind: .heading(level: level), quoteDepth: quoteDepth, listDepth: listDepth)
                if markerRange.length > 0 { delimiterSpans.append(DelimiterSpan(range: markerRange, attachment: .leading)) }
                if let closing = closingRange, closing.length > 0 { delimiterSpans.append(DelimiterSpan(range: closing, attachment: .trailing)) }
                walkInlines(block.inlines)

            case .setextHeading(let level, let underlineRange):
                let textLi = lineIndex(at: block.range.location)
                let underlineLi = lineIndex(at: underlineRange.location)
                lineInfos[textLi] = LineInfo(blockKind: .heading(level: level), quoteDepth: quoteDepth, listDepth: listDepth)
                lineInfos[underlineLi] = LineInfo(blockKind: .paragraph, quoteDepth: quoteDepth, listDepth: listDepth)
                if underlineRange.length > 0 { contentSpans.append(ContentSpan(range: underlineRange, style: .syntax, destination: nil)) }
                walkInlines(block.inlines)

            case .thematicBreak:
                assignLines(block.range, kind: .thematicBreak, quoteDepth: quoteDepth, listDepth: listDepth)
                fullLineSyntaxSpans(block.range)

            case .fencedCode(_, let openingFence, let closingFence, _):
                assignLines(block.range, kind: .codeBlock(isFence: true), quoteDepth: quoteDepth, listDepth: listDepth)
                if openingFence.length > 0 { contentSpans.append(ContentSpan(range: openingFence, style: .syntax, destination: nil)) }
                if let closing = closingFence, closing.length > 0 { contentSpans.append(ContentSpan(range: closing, style: .syntax, destination: nil)) }

            case .indentedCode:
                assignLines(block.range, kind: .codeBlock(isFence: false), quoteDepth: quoteDepth, listDepth: listDepth)

            case .blockquote(let markerRanges):
                for marker in markerRanges where marker.length > 0 {
                    let li = lineIndex(at: marker.location)
                    leadingHiddenEnd[li] = max(leadingHiddenEnd[li] ?? 0, NSMaxRange(marker))
                    delimiterSpans.append(DelimiterSpan(range: marker, attachment: .leading))
                }

            case .list:
                break // container; children (listItems) carry the presentation.

            case .listItem(let markerRange, let ordinal, let task, _):
                let li = lineIndex(at: markerRange.location)
                let extendedStart = extendedLeadingStart(markerLocation: markerRange.location, lineIdx: li)
                let full = NSRange(location: extendedStart, length: NSMaxRange(markerRange) - extendedStart)
                if full.length > 0 { delimiterSpans.append(DelimiterSpan(range: full, attachment: .leading)) }
                leadingHiddenEnd[li] = max(leadingHiddenEnd[li] ?? 0, NSMaxRange(markerRange))
                let marker: ListMarker = task != nil ? .task(isChecked: task!.isChecked) : (ordinal != nil ? .number(ordinal!) : .bullet)
                markerByLine[li] = (marker, task?.markerRange)

            case .htmlBlock:
                assignLines(block.range, kind: .html, quoteDepth: quoteDepth, listDepth: listDepth)
                fullLineSyntaxSpans(block.range)

            case .table:
                assignLines(block.range, kind: .table, quoteDepth: quoteDepth, listDepth: listDepth)
                fullLineSyntaxSpans(block.range)

            case .frontMatter:
                assignLines(block.range, kind: .frontMatter, quoteDepth: quoteDepth, listDepth: listDepth)
                fullLineSyntaxSpans(block.range)

            case .linkReferenceDefinition:
                assignLines(block.range, kind: .paragraph, quoteDepth: quoteDepth, listDepth: listDepth)
                fullLineSyntaxSpans(block.range)

            case .blank:
                assignLines(block.range, kind: .blank, quoteDepth: quoteDepth, listDepth: listDepth)
            }
            guard !block.children.isEmpty else { return }
            // Matches the previous `depths(parents)` semantics exactly: quote depth accumulates
            // across nested blockquotes, while list depth is *overwritten* by the innermost
            // listItem's own recorded depth (already nesting-aware from the parser), not summed.
            var childQuoteDepth = quoteDepth
            var childListDepth = listDepth
            switch block.kind {
            case .blockquote:
                childQuoteDepth += 1
            case .listItem(_, _, _, let depth):
                childListDepth = depth + 1
            default:
                break
            }
            for child in block.children { visit(child, quoteDepth: childQuoteDepth, listDepth: childListDepth) }
        }

        for (li, (marker, taskRange)) in markerByLine {
            var info = lineInfos[li] ?? LineInfo(blockKind: .paragraph, quoteDepth: 0, listDepth: 0)
            info.listMarker = marker
            info.taskMarkerSourceRange = taskRange
            lineInfos[li] = info
        }


        // MARK: CRLF terminators — hide the `\r` only when immediately followed by `\n`.

        var hiddenRuns: [SourceDisplayMap.Run] = delimiterSpans.map { SourceDisplayMap.Run(sourceRange: $0.range, attachment: $0.attachment) }
        for line in sourceLines where line.terminator.length == 2 {
            hiddenRuns.append(SourceDisplayMap.Run(sourceRange: NSRange(location: line.terminator.location, length: 1), attachment: .trailing))
        }


        // MARK: Build the map.

        let map: SourceDisplayMap
        switch mode {
        case .rich:
            map = SourceDisplayMap(sourceLength: sourceLength, runs: hiddenRuns)
        case .source:
            map = SourceDisplayMap.identity(sourceLength: sourceLength)
        }


        // MARK: Build display text.

        let displayText: String
        switch mode {
        case .source:
            displayText = source
        case .rich:
            var displayUnits: [UInt16] = []
            displayUnits.reserveCapacity(sourceLength)
            var cursor = 0
            for run in map.runs {
                if run.sourceRange.location > cursor {
                    displayUnits.append(contentsOf: utf16[cursor..<run.sourceRange.location])
                }
                cursor = NSMaxRange(run.sourceRange)
            }
            if cursor < sourceLength { displayUnits.append(contentsOf: utf16[cursor...]) }
            displayText = displayUnits.isEmpty ? "" : displayUnits.withUnsafeBufferPointer { buf in
                String(utf16CodeUnits: buf.baseAddress!, count: buf.count)
            }
        }


        // MARK: Style spans -> display coordinates.

        var allSpans: [ContentSpan] = contentSpans
        if mode == .source {
            for delimiter in delimiterSpans where delimiter.range.length > 0 {
                allSpans.append(ContentSpan(range: delimiter.range, style: .syntax, destination: nil))
            }
        }

        var displaySpans: [ContentSpan] = []
        displaySpans.reserveCapacity(allSpans.count)
        for span in allSpans {
            let displayRange = map.displayRange(forSource: span.range)
            if displayRange.length > 0 {
                displaySpans.append(ContentSpan(range: displayRange, style: span.style, destination: span.destination))
            }
        }
        displaySpans.sort { $0.range.location < $1.range.location }

        // MARK: Assemble lines.

        var lines: [PresentationLine] = []
        lines.reserveCapacity(sourceLines.count)
        var displayLineRanges: [NSRange] = []
        displayLineRanges.reserveCapacity(sourceLines.count)
        // `sourceLines` is strictly ordered and non-overlapping, so the (start, end) offsets
        // queried below are non-decreasing across the whole loop. That lets a forward-scanning
        // cursor over `map.runs` (sorted, public) stand in for `map.displayRange(forSource:)`'s
        // internal binary search — amortized O(1) instead of O(log runs.count) per line — while
        // falling back to the real (always-correct) implementation if that assumption is ever
        // violated, so this can never produce a different result than calling `map` directly.
        var lineRunCursor = 0
        var lineDeltaBeforeCursor = 0
        var lastLineQuery = -1
        func fastDisplayOffset(forSource source: Int) -> Int {
            let s = max(0, min(source, sourceLength))
            guard s >= lastLineQuery else { return map.displayOffset(forSource: s) }
            lastLineQuery = s
            while lineRunCursor < map.runs.count, map.runs[lineRunCursor].sourceRange.location <= s {
                let run = map.runs[lineRunCursor]
                if s < NSMaxRange(run.sourceRange) {
                    return run.sourceRange.location - lineDeltaBeforeCursor
                }
                lineDeltaBeforeCursor += run.sourceRange.length
                lineRunCursor += 1
            }
            return s - lineDeltaBeforeCursor
        }
        for line in sourceLines {
            let start = fastDisplayOffset(forSource: line.range.location)
            let end = fastDisplayOffset(forSource: NSMaxRange(line.range))
            displayLineRanges.append(NSRange(location: start, length: max(0, end - start)))
        }

        var cursor = 0
        for (li, displayRange) in displayLineRanges.enumerated() {
            while cursor < displaySpans.count, NSMaxRange(displaySpans[cursor].range) <= displayRange.location {
                cursor += 1
            }
            // Builds directly in merged form (folding what used to be a separate `mergeAdjacent`
            // pass over a freshly-appended `runs` array into the same loop that appends them).
            var runs: [StyleRun] = []
            var j = cursor
            while j < displaySpans.count, displaySpans[j].range.location < NSMaxRange(displayRange) {
                let span = displaySpans[j]
                let interLoc = max(span.range.location, displayRange.location)
                let interEnd = min(NSMaxRange(span.range), NSMaxRange(displayRange))
                if interEnd > interLoc {
                    if let last = runs.last, NSMaxRange(last.displayRange) == interLoc, last.style == span.style, last.destination == span.destination {
                        runs[runs.count - 1] = StyleRun(displayRange: NSRange(location: last.displayRange.location, length: interEnd - last.displayRange.location), style: last.style, destination: last.destination)
                    } else {
                        runs.append(StyleRun(displayRange: NSRange(location: interLoc, length: interEnd - interLoc), style: span.style, destination: span.destination))
                    }
                }
                j += 1
            }

            let info = lineInfos[li] ?? LineInfo(blockKind: .blank, quoteDepth: 0, listDepth: 0)
            let block = BlockPresentation(kind: info.blockKind, quoteDepth: info.quoteDepth, listDepth: info.listDepth, listMarker: info.listMarker, taskMarkerSourceRange: info.taskMarkerSourceRange)
            lines.append(PresentationLine(displayRange: displayRange, block: block, runs: runs))
        }

        return Presentation(displayText: displayText, map: map, lines: lines, mode: mode)
    }

    // MARK: - Helpers

    private struct DelimiterSpan {
        var range: NSRange
        var attachment: HiddenRunAttachment
    }

    private struct ContentSpan {
        var range: NSRange
        var style: InlineStyle
        var destination: String?
    }

    private struct LineInfo {
        var blockKind: BlockPresentationKind
        var quoteDepth: Int
        var listDepth: Int
        var listMarker: ListMarker?
        var taskMarkerSourceRange: NSRange?

        init(blockKind: BlockPresentationKind, quoteDepth: Int, listDepth: Int, listMarker: ListMarker? = nil, taskMarkerSourceRange: NSRange? = nil) {
            self.blockKind = blockKind
            self.quoteDepth = quoteDepth
            self.listDepth = listDepth
            self.listMarker = listMarker
            self.taskMarkerSourceRange = taskMarkerSourceRange
        }
    }

}
