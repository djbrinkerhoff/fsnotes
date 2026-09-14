import Foundation

public enum InlineFormat: Sendable, Equatable {
    case strong, emphasis, code, strikethrough

    var delimiter: String {
        switch self {
        case .strong: return "**"
        case .emphasis: return "*"
        case .code: return "`"
        case .strikethrough: return "~~"
        }
    }
}

public enum ListKind: Sendable, Equatable {
    case bullet, ordered, task
}

/// Markers that begin a physical line, as found in the parse tree.
struct LineMarkers {
    var quoteMarkers: [NSRange] = []
    var listItem: MarkdownBlock?
    var listMarker: NSRange?
    var heading: (block: MarkdownBlock, marker: NSRange)?
    var setextUnderline: NSRange?
    /// Source offset where the line's own content begins (after indentation and markers).
    var contentStart: Int
}

// MARK: - Semantic commands

public extension EditorSession {

    // MARK: Return

    /// Inserts a line break, continuing lists, tasks and quotes; exits an empty list item or quote line.
    func insertNewline() {
        let sel = sourceSelection()
        let eol = document.lineEnding.rawValue
        if sel.length > 0 {
            perform([SourceEdit(range: sel, replacement: eol)])
            return
        }
        let s = sel.location
        let line = document.lineRange(at: s)
        let markers = lineMarkers(for: line.content)

        if let item = markers.listItem, let marker = markers.listMarker, s >= NSMaxRange(marker) {
            let contentRange = NSRange(location: NSMaxRange(marker), length: max(0, NSMaxRange(line.content) - NSMaxRange(marker)))
            let content = document.substring(contentRange)
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty item: outdent nested items, exit the list for top-level items.
                if case .listItem(_, _, _, let depth) = item.kind, depth > 0, outdent() { return }
                let removeRange = NSRange(location: line.content.location, length: NSMaxRange(marker) - line.content.location)
                perform([SourceEdit(range: removeRange, replacement: "")], selectionAfterSource: NSRange(location: line.content.location, length: 0))
                return
            }
            var prefix = document.substring(NSRange(location: line.content.location, length: NSMaxRange(marker) - line.content.location))
            if case .listItem(_, let ordinal, let task, _) = item.kind {
                if let ordinal { prefix = Self.incrementOrdinal(in: prefix, from: ordinal) }
                if let task, task.isChecked {
                    let local = NSRange(location: task.markerRange.location - line.content.location + 1, length: 1)
                    prefix = (prefix as NSString).replacingCharacters(in: local, with: " ")
                }
            }
            perform([SourceEdit(range: sel, replacement: eol + prefix)])
            return
        }

        if !markers.quoteMarkers.isEmpty, markers.listItem == nil {
            let lastMarkerEnd = markers.quoteMarkers.map(NSMaxRange).max() ?? line.content.location
            let contentRange = NSRange(location: lastMarkerEnd, length: max(0, NSMaxRange(line.content) - lastMarkerEnd))
            if document.substring(contentRange).trimmingCharacters(in: .whitespaces).isEmpty, s >= lastMarkerEnd {
                let removeRange = NSRange(location: line.content.location, length: lastMarkerEnd - line.content.location)
                perform([SourceEdit(range: removeRange, replacement: "")], selectionAfterSource: NSRange(location: line.content.location, length: 0))
                return
            }
            if s >= lastMarkerEnd {
                let prefix = document.substring(NSRange(location: line.content.location, length: lastMarkerEnd - line.content.location))
                perform([SourceEdit(range: sel, replacement: eol + prefix)])
                return
            }
        }

        perform([SourceEdit(range: sel, replacement: eol)])
    }

    // MARK: Backspace

    /// Handles Backspace at the visible start of a line that has hidden block markers by removing the innermost marker.
    /// Returns false when the caret is elsewhere so the adapter performs a normal deletion.
    @discardableResult
    func handleBackspace() -> Bool {
        guard selection.length == 0, mode == .rich else { return false }
        let d = clampDisplay(selection).location
        let line = presentation.line(atDisplay: d)
        guard d == line.displayRange.location else { return false }
        let leadingRuns = presentation.map.runs(touchingDisplay: NSRange(location: d, length: 0)).filter {
            $0.attachment == .leading && presentation.map.displayOffset(forSource: $0.sourceRange.location) == d
        }
        guard let run = leadingRuns.last else { return false }
        // Only treat block markers (which start at a line start or right after another marker) as removable.
        let lineStart = document.lineRange(at: run.sourceRange.location).content.location
        let between = document.substring(NSRange(location: lineStart, length: run.sourceRange.location - lineStart))
        let markers = lineMarkers(for: document.lineRange(at: run.sourceRange.location).content)
        let isBlockMarker = between.allSatisfy { $0 == " " || $0 == "\t" || $0 == ">" } || markers.contentStart >= NSMaxRange(run.sourceRange)
        guard isBlockMarker else { return false }
        perform([SourceEdit(range: run.sourceRange, replacement: "")], selectionAfterSource: NSRange(location: run.sourceRange.location, length: 0), actionName: "Remove Marker")
        return true
    }

    // MARK: Indent / outdent

    /// Indents list items on the selected lines. Returns false when no list item was affected.
    @discardableResult
    func indent() -> Bool {
        let itemLines = selectedListItemLines()
        guard !itemLines.isEmpty else { return false }
        var edits: [SourceEdit] = []
        for (line, markers) in itemLines.reversed() {
            let unit = indentUnit(for: markers, line: line)
            edits.append(SourceEdit(range: NSRange(location: line.location, length: 0), replacement: String(repeating: " ", count: unit)))
        }
        let sel = sourceSelection()
        let firstUnit = itemLines.first.map { indentUnit(for: $0.markers, line: $0.line) } ?? 2
        let after = NSRange(location: sel.location + firstUnit, length: sel.length + (edits.count - 1) * firstUnit)
        perform(edits, selectionAfterSource: after, actionName: "Indent")
        return true
    }

    /// Outdents list items on the selected lines. Returns false when nothing could be outdented.
    @discardableResult
    func outdent() -> Bool {
        let itemLines = selectedListItemLines()
        guard !itemLines.isEmpty else { return false }
        var edits: [SourceEdit] = []
        var removedFirst = 0
        var removedTotal = 0
        for (index, entry) in itemLines.enumerated().reversed() {
            let (line, markers) = entry
            let leading = leadingWhitespaceLength(of: line)
            guard leading > 0 else { continue }
            let unit = min(leading, outdentUnit(for: markers, line: line))
            edits.append(SourceEdit(range: NSRange(location: line.location, length: unit), replacement: ""))
            removedTotal += unit
            if index == 0 { removedFirst = unit }
        }
        guard !edits.isEmpty else { return false }
        let sel = sourceSelection()
        let after = NSRange(location: max(0, sel.location - removedFirst), length: max(0, sel.length - (removedTotal - removedFirst)))
        perform(edits, selectionAfterSource: after, actionName: "Outdent")
        return true
    }

    /// Inserts a literal tab (used when Tab is pressed outside a list).
    func insertTab() {
        perform([SourceEdit(range: sourceSelection(), replacement: "\t")])
    }

    // MARK: Tasks

    /// Toggles the task whose `[ ]`/`[x]` marker is at `markerSourceRange`. One undo step; selection preserved.
    @discardableResult
    func toggleTask(markerSourceRange: NSRange) -> Bool {
        guard markerSourceRange.length == 3, NSMaxRange(markerSourceRange) <= document.utf16Count else { return false }
        let marker = document.substring(markerSourceRange)
        guard marker.hasPrefix("["), marker.hasSuffix("]") else { return false }
        let isChecked = marker.lowercased() == "[x]"
        let stateRange = NSRange(location: markerSourceRange.location + 1, length: 1)
        let sel = sourceSelection()
        perform([SourceEdit(range: stateRange, replacement: isChecked ? " " : "x")], selectionAfterSource: sel, actionName: "Toggle Task")
        return true
    }

    /// Toggles the task on the display line at `index`.
    @discardableResult
    func toggleTask(atDisplayLine index: Int) -> Bool {
        guard index >= 0, index < presentation.lines.count, let range = presentation.lines[index].block.taskMarkerSourceRange else { return false }
        return toggleTask(markerSourceRange: range)
    }

    // MARK: Headings

    /// Heading level of the line at the selection start, nil for non-headings.
    func headingLevelAtSelection() -> Int? {
        let line = document.lineRange(at: sourceSelection().location)
        guard let heading = lineMarkers(for: line.content).heading else { return nil }
        switch heading.block.kind {
        case .heading(let level, _, _), .setextHeading(let level, _): return level
        default: return nil
        }
    }

    /// Sets (or removes with nil/0) the ATX heading level of the line at the selection start.
    func setHeadingLevel(_ level: Int?) {
        let sel = sourceSelection()
        let line = document.lineRange(at: sel.location)
        let markers = lineMarkers(for: line.content)
        let newMarker = (level ?? 0) > 0 ? String(repeating: "#", count: min(6, level!)) + " " : ""
        var edits: [SourceEdit] = []
        var delta = 0
        if let heading = markers.heading {
            if case .heading(_, let markerRange, let closing) = heading.block.kind {
                if let closing { edits.append(SourceEdit(range: closing, replacement: "")) }
                edits.append(SourceEdit(range: markerRange, replacement: newMarker))
                delta = (newMarker as NSString).length - markerRange.length
            } else if case .setextHeading(_, let underline) = heading.block.kind {
                let underlineLine = document.lineRange(at: underline.location)
                let removeRange = NSRange(location: underlineLine.content.location - document.lineRange(at: underlineLine.content.location - 1).terminator.length, length: underlineLine.content.length + document.lineRange(at: underlineLine.content.location - 1).terminator.length)
                edits.append(SourceEdit(range: removeRange, replacement: ""))
                edits.append(SourceEdit(range: NSRange(location: markers.contentStart, length: 0), replacement: newMarker))
                delta = (newMarker as NSString).length
            }
        } else if !newMarker.isEmpty {
            edits.append(SourceEdit(range: NSRange(location: markers.contentStart, length: 0), replacement: newMarker))
            delta = (newMarker as NSString).length
        }
        guard !edits.isEmpty else { return }
        let after = NSRange(location: max(markers.contentStart, sel.location + delta), length: sel.length)
        perform(edits, selectionAfterSource: after, actionName: "Heading")
    }

    // MARK: Inline formatting

    /// Wraps the selection in `format` delimiters, unwraps it when already formatted,
    /// or, with a collapsed caret inside such a span, moves the caret past the span.
    func toggleInline(_ format: InlineFormat) {
        let sel = sourceSelection()
        let delimiter = format.delimiter
        let dLen = (delimiter as NSString).length
        if let node = inlineNode(matching: format, coveringSource: sel) {
            let (open, close) = delimiterRanges(of: node)
            let edits = [SourceEdit(range: close, replacement: ""), SourceEdit(range: open, replacement: "")]
            let after = NSRange(location: sel.location - open.length, length: max(0, sel.length - (sel.length == node.range.length ? open.length + close.length : 0)))
            perform(edits, selectionAfterSource: after, actionName: "Formatting")
            return
        }
        if sel.length == 0, let node = inlineNode(matching: format, containingSource: sel.location) {
            selection = presentation.map.displayRange(forSource: NSRange(location: NSMaxRange(node.range), length: 0))
            delegate?.session(self, didApply: PresentationUpdate(replacedDisplayRange: NSRange(location: 0, length: 0), replacementText: "", restyleDisplayRange: NSRange(location: 0, length: 0), selection: selection, isFullReplacement: false, revision: revision))
            return
        }
        var insertRange = sel
        if sel.length > 0 {
            // Keep surrounding whitespace outside the delimiters.
            let text = document.substring(sel) as NSString
            var start = 0, end = text.length
            while start < end, text.character(at: start) == 0x20 { start += 1 }
            while end > start, text.character(at: end - 1) == 0x20 { end -= 1 }
            insertRange = NSRange(location: sel.location + start, length: end - start)
        }
        let edits = [
            SourceEdit(range: NSRange(location: NSMaxRange(insertRange), length: 0), replacement: delimiter),
            SourceEdit(range: NSRange(location: insertRange.location, length: 0), replacement: delimiter)
        ]
        let after = NSRange(location: insertRange.location + dLen, length: insertRange.length)
        perform(edits, selectionAfterSource: after, actionName: "Formatting")
    }

    /// Inline formats active at the selection start.
    func inlineFormatsAtSelection() -> Set<InlineFormat> {
        let s = sourceSelection().location
        var result = Set<InlineFormat>()
        for format in [InlineFormat.strong, .emphasis, .code, .strikethrough] where inlineNode(matching: format, containingSource: s) != nil {
            result.insert(format)
        }
        return result
    }

    // MARK: Links

    func insertLink(text: String? = nil, destination: String) {
        let sel = sourceSelection()
        let label = sel.length > 0 ? document.substring(sel) : (text ?? destination)
        let replacement = "[\(label)](\(destination))"
        let after = NSRange(location: sel.location + 1, length: (label as NSString).length)
        perform([SourceEdit(range: sel, replacement: replacement)], selectionAfterSource: after, actionName: "Insert Link")
    }

    // MARK: Lists

    /// List kind of the item starting on the line at the selection start.
    func listKindAtSelection() -> ListKind? {
        let line = document.lineRange(at: sourceSelection().location)
        guard let item = lineMarkers(for: line.content).listItem, case .listItem(_, let ordinal, let task, _) = item.kind else { return nil }
        if task != nil { return .task }
        return ordinal != nil ? .ordered : .bullet
    }

    /// Converts the selected lines to `kind` list items, or back to paragraphs when they already are that kind.
    func toggleList(_ kind: ListKind) {
        let sel = sourceSelection()
        let lines = selectedLines()
        guard !lines.isEmpty else { return }
        let allAlready = lines.allSatisfy { listKind(of: lineMarkers(for: $0)) == kind }
        var edits: [SourceEdit] = []
        var firstDelta = 0
        var totalDelta = 0
        for (index, line) in lines.enumerated().reversed() {
            let markers = lineMarkers(for: line)
            var edit: SourceEdit
            if allAlready, let marker = markers.listMarker {
                let removeRange = NSRange(location: line.location + leadingWhitespaceLength(of: line), length: NSMaxRange(marker) - line.location - leadingWhitespaceLength(of: line))
                edit = SourceEdit(range: removeRange, replacement: "")
            } else {
                let newMarker: String
                switch kind {
                case .bullet: newMarker = "- "
                case .ordered: newMarker = "\(index + 1). "
                case .task: newMarker = "- [ ] "
                }
                if let marker = markers.listMarker {
                    edit = SourceEdit(range: marker, replacement: newMarker)
                } else {
                    edit = SourceEdit(range: NSRange(location: markers.contentStart, length: 0), replacement: newMarker)
                }
            }
            edits.append(edit)
            totalDelta += edit.lengthDelta
            if index == 0 { firstDelta = edit.lengthDelta }
        }
        let after: NSRange
        if lines.count == 1 {
            let markers = lineMarkers(for: lines[0])
            after = NSRange(location: max(markers.contentStart + min(0, firstDelta), sel.location + firstDelta), length: sel.length)
        } else {
            after = NSRange(location: max(lines[0].location, sel.location + firstDelta), length: max(0, sel.length + totalDelta - firstDelta))
        }
        perform(edits, selectionAfterSource: after, actionName: "List")
    }
}

// MARK: - Tree helpers

extension EditorSession {

    func lineMarkers(for line: NSRange) -> LineMarkers {
        var markers = LineMarkers(contentStart: line.location)
        let lineEnd = NSMaxRange(line)
        tree.forEachBlock { block, _ in
            switch block.kind {
            case .blockquote(let ranges):
                for r in ranges where r.location >= line.location && r.location <= lineEnd {
                    markers.quoteMarkers.append(r)
                }
            case .listItem(let markerRange, _, _, _):
                if markerRange.location >= line.location && markerRange.location <= lineEnd {
                    markers.listItem = block
                    markers.listMarker = markerRange
                }
            case .heading(_, let markerRange, _):
                if markerRange.location >= line.location && markerRange.location <= lineEnd {
                    markers.heading = (block, markerRange)
                }
            case .setextHeading(_, let underline):
                if block.range.location >= line.location && block.range.location <= lineEnd {
                    markers.heading = (block, NSRange(location: block.range.location, length: 0))
                }
                if underline.location >= line.location && underline.location <= lineEnd {
                    markers.setextUnderline = underline
                }
            default:
                break
            }
        }
        // Content start: skip whitespace and markers from the line start.
        let ns = document.text as NSString
        var pos = line.location
        let markerRanges = (markers.quoteMarkers + [markers.listMarker, markers.heading?.marker].compactMap { $0 }).sorted { $0.location < $1.location }
        var progressed = true
        while progressed {
            progressed = false
            while pos < lineEnd, [0x20, 0x09].contains(ns.character(at: pos)) { pos += 1 }
            if let r = markerRanges.first(where: { $0.location == pos && $0.length > 0 }) {
                pos = NSMaxRange(r)
                progressed = true
            }
        }
        markers.contentStart = pos
        return markers
    }

    func listKind(of markers: LineMarkers) -> ListKind? {
        guard let item = markers.listItem, case .listItem(_, let ordinal, let task, _) = item.kind else { return nil }
        if task != nil { return .task }
        return ordinal != nil ? .ordered : .bullet
    }

    /// Physical source lines intersecting the selection.
    func selectedLines() -> [NSRange] {
        let sel = sourceSelection()
        var lines: [NSRange] = []
        var pos = sel.location
        let end = NSMaxRange(sel)
        repeat {
            let line = document.lineRange(at: pos)
            lines.append(line.content)
            pos = NSMaxRange(line.content) + line.terminator.length
            if line.terminator.length == 0 { break }
        } while pos < end || (pos == end && sel.length > 0 && end > lines.last!.location && NSMaxRange(lines.last!) < end)
        return lines
    }

    func selectedListItemLines() -> [(line: NSRange, markers: LineMarkers)] {
        selectedLines().compactMap { line in
            let markers = lineMarkers(for: line)
            return markers.listMarker != nil ? (line, markers) : nil
        }
    }

    func leadingWhitespaceLength(of line: NSRange) -> Int {
        let ns = document.text as NSString
        var count = 0
        while line.location + count < NSMaxRange(line), [0x20, 0x09].contains(ns.character(at: line.location + count)) { count += 1 }
        return count
    }

    /// Width of the bullet/number marker plus following whitespace (task marker excluded).
    func indentUnit(for markers: LineMarkers, line: NSRange) -> Int {
        guard let marker = markers.listMarker else { return 2 }
        let ns = document.text as NSString
        var pos = marker.location
        while pos < NSMaxRange(marker), ![0x20, 0x09].contains(ns.character(at: pos)) { pos += 1 }
        while pos < NSMaxRange(marker), [0x20, 0x09].contains(ns.character(at: pos)) { pos += 1 }
        return max(2, pos - marker.location)
    }

    /// Whitespace to remove when outdenting: distance to the parent item's marker column, or the own indent.
    func outdentUnit(for markers: LineMarkers, line: NSRange) -> Int {
        let leading = leadingWhitespaceLength(of: line)
        guard let item = markers.listItem, case .listItem(let marker, _, _, let depth) = item.kind, depth > 0 else { return leading }
        let path = tree.blockPath(at: marker.location)
        let parents = path.filter { if case .listItem = $0.kind { return true } else { return false } }
        guard parents.count >= 2, case .listItem(let parentMarker, _, _, _) = parents[parents.count - 2].kind else { return leading }
        let parentLine = document.lineRange(at: parentMarker.location).content
        let parentColumn = parentMarker.location - parentLine.location
        let ownColumn = marker.location - line.location
        return max(1, min(leading, ownColumn - parentColumn))
    }

    static func incrementOrdinal(in prefix: String, from ordinal: Int) -> String {
        guard let digitsRange = prefix.rangeOfCharacter(from: .decimalDigits) else { return prefix }
        var end = digitsRange.upperBound
        while end < prefix.endIndex, prefix[end].isNumber { end = prefix.index(after: end) }
        return prefix.replacingCharacters(in: digitsRange.lowerBound..<end, with: String(ordinal + 1))
    }

    func inlineNodes(coveringSource offset: Int) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        func visit(_ nodes: [MarkdownInline]) {
            for node in nodes where offset >= node.range.location && offset <= NSMaxRange(node.range) {
                result.append(node)
                visit(node.children)
            }
        }
        for block in tree.blockPath(at: offset) { visit(block.inlines) }
        return result
    }

    func inlineNode(matching format: InlineFormat, coveringSource range: NSRange) -> MarkdownInline? {
        inlineNodes(coveringSource: range.location).last { node in
            guard Self.kind(of: node) == format else { return false }
            let (open, close) = delimiterRanges(of: node)
            let inner = NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
            return NSEqualRanges(node.range, range) || NSEqualRanges(inner, range)
        }
    }

    func inlineNode(matching format: InlineFormat, containingSource offset: Int) -> MarkdownInline? {
        inlineNodes(coveringSource: offset).last { node in
            guard Self.kind(of: node) == format else { return false }
            let (open, close) = delimiterRanges(of: node)
            return offset > open.location && offset < NSMaxRange(close)
        }
    }

    static func kind(of node: MarkdownInline) -> InlineFormat? {
        switch node.kind {
        case .strong: return .strong
        case .emphasis: return .emphasis
        case .code: return .code
        case .strikethrough: return .strikethrough
        default: return nil
        }
    }

    func delimiterRanges(of node: MarkdownInline) -> (NSRange, NSRange) {
        switch node.kind {
        case .strong(let open, let close), .emphasis(let open, let close), .code(let open, let close), .strikethrough(let open, let close):
            return (open, close)
        default:
            return (NSRange(location: node.range.location, length: 0), NSRange(location: NSMaxRange(node.range), length: 0))
        }
    }
}

// MARK: - Quotes and code blocks

public extension EditorSession {
    /// Adds a `> ` quote marker to the selected lines, or removes it when every selected line is already quoted.
    func toggleQuote() {
        let sel = sourceSelection()
        let lines = selectedLines()
        guard !lines.isEmpty else { return }
        let markersPerLine = lines.map { lineMarkers(for: $0) }
        let allQuoted = markersPerLine.allSatisfy { !$0.quoteMarkers.isEmpty }
        var edits: [SourceEdit] = []
        var firstDelta = 0
        var totalDelta = 0
        for (index, line) in lines.enumerated().reversed() {
            let markers = markersPerLine[index]
            let edit: SourceEdit
            if allQuoted, let last = markers.quoteMarkers.max(by: { $0.location < $1.location }) {
                edit = SourceEdit(range: last, replacement: "")
            } else {
                let insertAt = markers.quoteMarkers.map(NSMaxRange).max() ?? (line.location + leadingWhitespaceLength(of: line))
                edit = SourceEdit(range: NSRange(location: insertAt, length: 0), replacement: "> ")
            }
            edits.append(edit)
            totalDelta += edit.lengthDelta
            if index == 0 { firstDelta = edit.lengthDelta }
        }
        let after = NSRange(location: max(lines[0].location, sel.location + firstDelta), length: max(0, sel.length + totalDelta - firstDelta))
        perform(edits, selectionAfterSource: after, actionName: "Quote")
    }

    /// Wraps the selection (or inserts an empty block) in a fenced code block.
    func insertCodeBlock(language: String = "") {
        let sel = sourceSelection()
        let eol = document.lineEnding.rawValue
        let line = document.lineRange(at: sel.location)
        let needsLeadingBreak = sel.location > line.content.location
        let body = sel.length > 0 ? document.substring(sel) : ""
        let prefix = (needsLeadingBreak ? eol : "") + "```" + language + eol
        let suffix = eol + "```" + (NSMaxRange(sel) < NSMaxRange(document.lineRange(at: NSMaxRange(sel)).content) ? eol : "")
        let replacement = prefix + body + suffix
        let caret = sel.location + (prefix as NSString).length
        perform([SourceEdit(range: sel, replacement: replacement)], selectionAfterSource: NSRange(location: caret, length: (body as NSString).length), actionName: "Code Block")
    }
}
