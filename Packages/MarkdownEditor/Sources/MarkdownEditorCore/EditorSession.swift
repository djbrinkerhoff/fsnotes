import Foundation

/// Describes how the text view must change to reflect a new presentation.
public struct PresentationUpdate: Sendable, Equatable {
    /// Range in the previous display text to replace. Empty with `replacementText == ""` when text is unchanged.
    public var replacedDisplayRange: NSRange
    public var replacementText: String
    /// Range in the new display text whose paragraph styling must be reapplied (may be empty).
    public var restyleDisplayRange: NSRange
    /// New display selection.
    public var selection: NSRange
    /// True when the adapter should replace the whole text (mode toggle, external reload).
    public var isFullReplacement: Bool
    /// Source revision the update corresponds to.
    public var revision: Int
}

@MainActor
public protocol EditorSessionDelegate: AnyObject {
    /// Called after every presentation change. The adapter must apply the update synchronously.
    func session(_ session: EditorSession, didApply update: PresentationUpdate)
    /// Called after the source changed because of a user edit or command (not on external reload).
    func sessionDidEditDocument(_ session: EditorSession)
}

/// Timing of the last transaction, in seconds, for benchmarking.
public struct TransactionMetrics: Sendable, Equatable {
    public var parse: Double = 0
    public var present: Double = 0
    public var diff: Double = 0
    public var total: Double = 0
}

/// Owns the canonical Markdown source of one open note, its parse tree, presentation, selection and undo.
/// Every edit, whether typed in the display buffer or issued as a command, is a source transaction.
@MainActor
public final class EditorSession {
    public let id = UUID()
    public private(set) var document: SourceDocument
    public private(set) var tree: MarkdownTree
    public private(set) var presentation: Presentation
    public private(set) var mode: EditorMode
    /// Current display selection. Adapters keep this in sync.
    public var selection: NSRange
    public let undoManager: UndoManager
    public weak var delegate: EditorSessionDelegate?
    public private(set) var lastMetrics = TransactionMetrics()
    /// Revision of the last transaction that was a user edit (vs. external reload).
    public private(set) var lastUserEditRevision: Int = 0

    private let parser: MarkdownParser
    private let builder: PresentationBuilding
    private var openTypingRecord: UndoRecord?

    public init(source: String, parser: MarkdownParser, builder: PresentationBuilding, mode: EditorMode = .rich, undoManager: UndoManager? = nil) {
        self.document = SourceDocument(text: source)
        self.parser = parser
        self.builder = builder
        self.mode = mode
        let ownsUndoManager = undoManager == nil
        self.undoManager = undoManager ?? UndoManager()
        self.tree = parser.parse(source)
        self.presentation = builder.build(source: source, tree: tree, mode: mode)
        self.selection = NSRange(location: 0, length: 0)
        // Each transaction is registered inside its own explicit group so one command is one undo step
        // even when several transactions happen within a single run-loop event.
        if ownsUndoManager { self.undoManager.groupsByEvent = false }
    }

    public var source: String { document.text }
    public var revision: Int { document.revision }

    // MARK: - Undo records

    private final class UndoRecord {
        var forward: [SourceEdit]
        var inverse: [SourceEdit]
        var selectionBefore: NSRange   // source coordinates
        var selectionAfter: NSRange    // source coordinates
        var actionName: String?
        var isTyping: Bool

        init(forward: [SourceEdit], inverse: [SourceEdit], selectionBefore: NSRange, selectionAfter: NSRange, actionName: String?, isTyping: Bool) {
            self.forward = forward
            self.inverse = inverse
            self.selectionBefore = selectionBefore
            self.selectionAfter = selectionAfter
            self.actionName = actionName
            self.isTyping = isTyping
        }
    }

    /// Ends typing coalescing so the next keystroke starts a new undo step.
    public func breakUndoCoalescing() {
        openTypingRecord = nil
    }

    // MARK: - Transactions

    /// Applies `edits` in order (each expressed in coordinates after the previous one),
    /// registers a single undo step and publishes the presentation update.
    @discardableResult
    public func perform(_ edits: [SourceEdit], selectionAfterSource: NSRange? = nil, actionName: String? = nil, coalesceTyping: Bool = false) -> Bool {
        guard !edits.isEmpty else { return false }
        let selectionBeforeSource = sourceSelection()
        var inverses: [SourceEdit] = []
        for edit in edits {
            guard edit.range.location >= 0, NSMaxRange(edit.range) <= document.utf16Count else { return false }
            inverses.append(document.apply(edit))
        }
        let after = selectionAfterSource ?? NSRange(location: NSMaxRange(edits.last!.range) + edits.last!.lengthDelta - 0, length: 0)
        let normalizedAfter = clampSource(after)

        if coalesceTyping, edits.count == 1, let open = openTypingRecord, open.isTyping, canCoalesce(open, with: edits[0]) {
            coalesce(open, with: edits[0], inverse: inverses[0], selectionAfter: normalizedAfter)
        } else {
            let record = UndoRecord(forward: edits, inverse: inverses.reversed(), selectionBefore: selectionBeforeSource, selectionAfter: normalizedAfter, actionName: actionName, isTyping: coalesceTyping)
            registerUndo(for: record)
            openTypingRecord = coalesceTyping ? record : nil
        }
        lastUserEditRevision = document.revision
        refresh(selectionSource: normalizedAfter, fullReplacement: false)
        delegate?.sessionDidEditDocument(self)
        return true
    }

    private func canCoalesce(_ record: UndoRecord, with edit: SourceEdit) -> Bool {
        guard record.forward.count == 1 else { return false }
        let last = record.forward[0]
        let lastEnd = last.range.location + last.replacementLength
        // Contiguous insertion after the previous insertion.
        if edit.range.length == 0, last.range.length == 0, edit.range.location == lastEnd, !edit.replacement.contains("\n"), !edit.replacement.contains("\r") { return true }
        // Contiguous backward deletion.
        if edit.replacementLength == 0, last.replacementLength == 0, NSMaxRange(edit.range) == last.range.location, edit.range.length == 1, last.range.length >= 1 { return true }
        return false
    }

    private func coalesce(_ record: UndoRecord, with edit: SourceEdit, inverse: SourceEdit, selectionAfter: NSRange) {
        var last = record.forward[0]
        if edit.range.length == 0 {
            last.replacement += edit.replacement
            record.forward = [last]
            record.inverse = [SourceEdit(range: NSRange(location: last.range.location, length: last.replacementLength), replacement: record.inverse[0].replacement)]
        } else {
            // Backward deletion: extend the deleted range to the left.
            let combinedRange = NSRange(location: edit.range.location, length: last.range.length + edit.range.length)
            record.forward = [SourceEdit(range: combinedRange, replacement: "")]
            record.inverse = [SourceEdit(range: NSRange(location: edit.range.location, length: 0), replacement: inverse.replacement + record.inverse[0].replacement)]
        }
        record.selectionAfter = selectionAfter
    }

    private func registerUndo(for record: UndoRecord) {
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { session in
            session.undo(record)
        }
        if let name = record.actionName { undoManager.setActionName(name) }
        undoManager.endUndoGrouping()
    }

    private func undo(_ record: UndoRecord) {
        openTypingRecord = nil
        for edit in record.inverse { document.apply(edit) }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { session in
            session.redo(record)
        }
        if let name = record.actionName { undoManager.setActionName(name) }
        undoManager.endUndoGrouping()
        lastUserEditRevision = document.revision
        refresh(selectionSource: clampSource(record.selectionBefore), fullReplacement: false)
        delegate?.sessionDidEditDocument(self)
    }

    private func redo(_ record: UndoRecord) {
        openTypingRecord = nil
        for edit in record.forward { document.apply(edit) }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { session in
            session.undo(record)
        }
        if let name = record.actionName { undoManager.setActionName(name) }
        undoManager.endUndoGrouping()
        lastUserEditRevision = document.revision
        refresh(selectionSource: clampSource(record.selectionAfter), fullReplacement: false)
        delegate?.sessionDidEditDocument(self)
    }

    // MARK: - Display-driven edits

    /// Replaces a display range with text typed or pasted by the user. Returns false when out of bounds.
    @discardableResult
    public func replaceDisplay(range: NSRange, with text: String, selectionAfterDisplay: NSRange? = nil) -> Bool {
        guard range.location >= 0, NSMaxRange(range) <= presentation.displayLength else { return false }
        let sourceRange = presentation.map.sourceRange(forDisplay: range)
        let replacement = normalizeLineEndings(text)
        let edit = SourceEdit(range: sourceRange, replacement: replacement)
        var after: NSRange? = nil
        if let sel = selectionAfterDisplay {
            // Selection expressed in the post-edit display; approximate via source offsets of the edit.
            let delta = sel.location - (range.location + (replacement as NSString).length)
            after = NSRange(location: sourceRange.location + edit.replacementLength + delta, length: sel.length)
        }
        let isTyping = range.length == 0 && !replacement.isEmpty && (replacement as NSString).length <= 2 && !replacement.contains("\n")
        let isBackspace = replacement.isEmpty && range.length == 1
        return perform([edit], selectionAfterSource: after, coalesceTyping: isTyping || isBackspace)
    }

    /// Reconciles a display text that the native view changed on its own (IME commit, dictation, autocorrect).
    public func reconcile(displayText: String, selection: NSRange) {
        guard let diff = TextDiff.between(presentation.displayText, displayText) else {
            self.selection = clampDisplay(selection)
            return
        }
        replaceDisplay(range: diff.range, with: diff.replacement, selectionAfterDisplay: selection)
    }

    /// Replaces the whole source, e.g. after an external file change. Clears undo history.
    public func replaceSource(with text: String, preserveSelection: Bool = true) {
        let selSource = sourceSelection()
        document.replaceAll(with: text)
        undoManager.removeAllActions()
        openTypingRecord = nil
        refresh(selectionSource: preserveSelection ? clampSource(selSource) : NSRange(location: 0, length: 0), fullReplacement: true)
    }

    // MARK: - Mode

    public func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        let selSource = sourceSelection()
        mode = newMode
        openTypingRecord = nil
        refresh(selectionSource: selSource, fullReplacement: true)
    }

    public func toggleMode() {
        setMode(mode == .rich ? .source : .rich)
    }

    // MARK: - Mapping helpers

    /// Current selection in source coordinates.
    public func sourceSelection() -> NSRange {
        presentation.map.sourceRange(forDisplay: clampDisplay(selection))
    }

    /// Markdown source corresponding to a display range (for Copy Markdown).
    public func markdown(forDisplayRange range: NSRange) -> String {
        document.substring(presentation.map.sourceRange(forDisplay: clampDisplay(range)))
    }

    public func displayRange(forSource range: NSRange) -> NSRange {
        presentation.map.displayRange(forSource: range)
    }

    /// Converts "\n" in typed/pasted text to the document's line ending.
    public func normalizeLineEndings(_ text: String) -> String {
        guard document.lineEnding != .lf, text.contains("\n") else { return text }
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(of: "\n", with: document.lineEnding.rawValue)
        return out
    }

    func clampSource(_ range: NSRange) -> NSRange {
        let count = document.utf16Count
        let loc = max(0, min(range.location, count))
        let len = max(0, min(range.length, count - loc))
        return NSRange(location: loc, length: len)
    }

    func clampDisplay(_ range: NSRange) -> NSRange {
        let count = presentation.displayLength
        let loc = max(0, min(range.location, count))
        let len = max(0, min(range.length, count - loc))
        return NSRange(location: loc, length: len)
    }

    // MARK: - Refresh

    private func refresh(selectionSource: NSRange, fullReplacement: Bool) {
        let start = ContinuousClock.now
        let oldPresentation = presentation
        tree = parser.parse(document.text)
        let parsed = ContinuousClock.now
        presentation = builder.build(source: document.text, tree: tree, mode: mode)
        let presented = ContinuousClock.now

        let newSelection = clampDisplay(presentation.map.displayRange(forSource: selectionSource))
        selection = newSelection

        var update: PresentationUpdate
        if fullReplacement {
            update = PresentationUpdate(replacedDisplayRange: NSRange(location: 0, length: oldPresentation.displayLength), replacementText: presentation.displayText, restyleDisplayRange: NSRange(location: 0, length: presentation.displayLength), selection: newSelection, isFullReplacement: true, revision: document.revision)
        } else {
            let diff = TextDiff.between(oldPresentation.displayText, presentation.displayText)
            let restyle = restyleRange(old: oldPresentation, new: presentation, diff: diff)
            update = PresentationUpdate(replacedDisplayRange: diff?.range ?? NSRange(location: 0, length: 0), replacementText: diff?.replacement ?? "", restyleDisplayRange: restyle, selection: newSelection, isFullReplacement: false, revision: document.revision)
        }
        let done = ContinuousClock.now
        lastMetrics = TransactionMetrics(
            parse: seconds(start, parsed),
            present: seconds(parsed, presented),
            diff: seconds(presented, done),
            total: seconds(start, done))
        delegate?.session(self, didApply: update)
    }

    private func seconds(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> Double {
        let d = b - a
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    /// Lines whose style signature changed, expressed as a display range in the new presentation.
    private func restyleRange(old: Presentation, new: Presentation, diff: TextDiff?) -> NSRange {
        let oldLines = old.lines, newLines = new.lines
        var prefix = 0
        let minCount = min(oldLines.count, newLines.count)
        let diffStart = diff?.range.location ?? Int.max
        while prefix < minCount,
              NSMaxRange(oldLines[prefix].displayRange) < diffStart,
              oldLines[prefix].styleSignature == newLines[prefix].styleSignature {
            prefix += 1
        }
        var suffix = 0
        let oldDiffEnd = diff.map { NSMaxRange($0.range) } ?? -1
        let newDiffEnd = diff.map { $0.range.location + ($0.replacement as NSString).length } ?? -1
        while suffix < minCount - prefix {
            let o = oldLines[oldLines.count - 1 - suffix], n = newLines[newLines.count - 1 - suffix]
            guard o.displayRange.location > oldDiffEnd, n.displayRange.location > newDiffEnd, o.styleSignature == n.styleSignature else { break }
            suffix += 1
        }
        let firstIndex = prefix
        let lastIndex = newLines.count - 1 - suffix
        guard firstIndex <= lastIndex, firstIndex < newLines.count else {
            return NSRange(location: 0, length: 0)
        }
        let startLoc = newLines[firstIndex].displayRange.location
        let endLoc = NSMaxRange(newLines[lastIndex].displayRange)
        return NSRange(location: startLoc, length: max(0, endLoc - startLoc))
    }
}
