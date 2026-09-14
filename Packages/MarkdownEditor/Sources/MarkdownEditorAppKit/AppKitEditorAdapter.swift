#if canImport(AppKit)
import AppKit
import MarkdownEditorCore
import MarkdownEditorTextKit

/// Bridges a `MarkdownTextView` to an `EditorSession`.
///
/// The session owns the Markdown source and is the only thing allowed to mutate it. Every text
/// change the user makes in the view is intercepted in `textView(_:shouldChangeTextIn:replacementString:)`
/// and forwarded to the session, which reparses and calls back `session(_:didApply:)`; this adapter
/// applies that `PresentationUpdate` to the text storage. The view's own native undo is disabled;
/// `undoManager(for:)` vends the session's `UndoManager` instead.
@MainActor
public final class AppKitEditorAdapter: NSObject, NSTextViewDelegate, EditorSessionDelegate, MarkdownThemeProviding {
    public let textView: MarkdownTextView
    public private(set) var session: EditorSession

    public var theme: ResolvedTheme {
        didSet {
            builder = AttributeBuilder(theme: theme)
            textView.theme = theme
            reloadFullPresentation()
        }
    }

    public var onOpenLink: ((URL) -> Void)?
    public var onOpenWikiLink: ((String) -> Void)?
    public var onEditorDidChange: (() -> Void)?

    /// `MarkdownThemeProviding` conformance, read by `MarkdownLayoutFragment`s via the layout
    /// manager delegate.
    var currentTheme: ResolvedTheme { theme }

    private var builder: AttributeBuilder
    /// True while `session(_:didApply:)` is applying a session-originated change to the storage, so
    /// the `NSTextViewDelegate` callbacks that fire as a side effect don't loop back into the session.
    private var isApplyingUpdate = false
    /// Set when the storage changed under IME composition (marked text); reconciled on `textDidChange`.
    private var needsReconcile = false
    private var lastKnownSelection: NSRange

    public init(textView: MarkdownTextView, session: EditorSession, theme: ResolvedTheme) {
        self.textView = textView
        self.session = session
        self.theme = theme
        self.builder = AttributeBuilder(theme: theme)
        self.lastKnownSelection = session.selection
        super.init()

        textView.adapter = self
        textView.delegate = self
        textView.theme = theme
        textView.allowsUndo = false
        session.delegate = self

        reloadFullPresentation()
    }

    // MARK: - Session / document

    /// Swaps in a new document: full replacement of the storage, selection reset to the start, and
    /// the view scrolled back to the top.
    public func setSession(_ newSession: EditorSession) {
        session.delegate = nil
        session = newSession
        session.delegate = self
        session.selection = NSRange(location: 0, length: 0)
        lastKnownSelection = session.selection
        reloadFullPresentation()
        textView.scrollToBeginningOfDocument(nil)
    }

    public var isSourceMode: Bool { session.mode == .source }

    public func toggleSourceMode() {
        session.toggleMode()
    }

    private func reloadFullPresentation() {
        guard let storage = textView.textStorage else { return }
        isApplyingUpdate = true
        let attributed = builder.attributedString(for: session.presentation)
        storage.setAttributedString(attributed)
        isApplyingUpdate = false
        textView.typingAttributes = builder.baseAttributes
        let clamped = clampedSelection(session.selection, length: (textView.string as NSString).length)
        textView.setSelectedRange(clamped)
        lastKnownSelection = clamped
        refreshAccessibility()
    }

    // MARK: - NSTextViewDelegate: routing edits through the session

    public func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard !isApplyingUpdate else { return true }
        if textView.hasMarkedText() {
            needsReconcile = true
            return true
        }
        guard let replacementString else { return true }
        reconcileIfNeeded(textView)
        _ = session.replaceDisplay(range: affectedCharRange, with: replacementString)
        return false
    }

    public func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        guard !isApplyingUpdate else { return true }
        if textView.hasMarkedText() {
            needsReconcile = true
            return true
        }
        guard let replacementStrings, replacementStrings.count == affectedRanges.count, !affectedRanges.isEmpty else { return true }
        reconcileIfNeeded(textView)

        // Build edits against a single snapshot of the display map, ordered from the end of the
        // document towards the start, so each range's coordinates stay valid regardless of what
        // earlier (lower-offset) edits will do once applied.
        let map = session.presentation.map
        let pairs = zip(affectedRanges.map { $0.rangeValue }, replacementStrings)
            .sorted { $0.0.location > $1.0.location }
        let edits = pairs.map { range, replacement in
            SourceEdit(range: map.sourceRange(forDisplay: range), replacement: session.normalizeLineEndings(replacement))
        }
        _ = session.perform(edits)
        return false
    }

    private func reconcileIfNeeded(_ textView: NSTextView) {
        guard textView.string != session.presentation.displayText else { return }
        session.reconcile(displayText: textView.string, selection: textView.selectedRange())
    }

    public func textDidChange(_ notification: Notification) {
        guard needsReconcile, !textView.hasMarkedText() else { return }
        needsReconcile = false
        session.reconcile(displayText: textView.string, selection: textView.selectedRange())
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingUpdate else { return }
        let newSelection = textView.selectedRange()
        let isAdjacent = newSelection.location == NSMaxRange(lastKnownSelection)
            || NSMaxRange(newSelection) == lastKnownSelection.location
            || newSelection == lastKnownSelection
        if !isAdjacent {
            session.breakUndoCoalescing()
        }
        lastKnownSelection = newSelection
        session.selection = newSelection
    }

    public func undoManager(for view: NSTextView) -> UndoManager? {
        session.undoManager
    }

    public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL {
            onOpenLink?(url)
            return true
        }
        if let destination = link as? String {
            if let url = URL(string: destination), let scheme = url.scheme, !scheme.isEmpty {
                onOpenLink?(url)
            } else {
                onOpenWikiLink?(destination)
            }
            return true
        }
        return false
    }

    // MARK: - EditorSessionDelegate

    public func session(_ session: EditorSession, didApply update: PresentationUpdate) {
        guard session === self.session, let storage = textView.textStorage else { return }
        isApplyingUpdate = true
        defer { isApplyingUpdate = false }

        storage.beginEditing()
        if update.isFullReplacement {
            storage.setAttributedString(builder.attributedString(for: session.presentation))
        } else {
            applyIncrementalUpdate(update, to: storage)
        }
        storage.endEditing()

        let clamped = clampedSelection(update.selection, length: (textView.string as NSString).length)
        textView.setSelectedRange(clamped)
        lastKnownSelection = clamped
        updateTypingAttributes(atDisplay: clamped.location)
        refreshAccessibility()
        scrollToSelectionIfNeeded()
    }

    public func sessionDidEditDocument(_ session: EditorSession) {
        onEditorDidChange?()
    }

    private func applyIncrementalUpdate(_ update: PresentationUpdate, to storage: NSTextStorage) {
        let hasTextChange = update.replacedDisplayRange.length > 0 || !update.replacementText.isEmpty
        if hasTextChange, NSMaxRange(update.replacedDisplayRange) <= storage.length {
            let replacement = NSAttributedString(string: update.replacementText, attributes: builder.baseAttributes)
            storage.replaceCharacters(in: update.replacedDisplayRange, with: replacement)
        }
        let insertedLength = (update.replacementText as NSString).length
        let insertedRange = NSRange(location: update.replacedDisplayRange.location, length: insertedLength)
        var restyled = Set<Int>()
        for (index, line) in session.presentation.lines.enumerated() {
            let intersectsRestyle = NSMaxRange(line.displayRange) >= update.restyleDisplayRange.location && line.displayRange.location <= NSMaxRange(update.restyleDisplayRange)
            let intersectsInserted = NSMaxRange(line.displayRange) >= insertedRange.location && line.displayRange.location <= NSMaxRange(insertedRange)
            guard intersectsRestyle || intersectsInserted, !restyled.contains(index) else { continue }
            restyled.insert(index)
            builder.apply(line, to: storage, includeNewline: true)
        }
    }

    private func updateTypingAttributes(atDisplay location: Int) {
        guard !session.presentation.lines.isEmpty else { return }
        let index = session.presentation.lineIndex(atDisplay: location)
        let line = session.presentation.lines[index]
        textView.typingAttributes = builder.attributes(for: line).paragraph
    }

    private func refreshAccessibility() {
        NSAccessibility.post(element: textView, notification: .layoutChanged)
    }

    private func scrollToSelectionIfNeeded() {
        let caret = NSRange(location: textView.selectedRange().location, length: 0)
        var actual = NSRange(location: 0, length: 0)
        let screenRect = textView.firstRect(forCharacterRange: caret, actualRange: &actual)
        guard screenRect != .zero, let window = textView.window else { return }
        let windowRect = window.convertFromScreen(screenRect)
        let localRect = textView.convert(windowRect, from: nil)
        guard !textView.visibleRect.contains(localRect) else { return }
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    private func clampedSelection(_ range: NSRange, length: Int) -> NSRange {
        let loc = max(0, min(range.location, length))
        let len = max(0, min(range.length, length - loc))
        return NSRange(location: loc, length: len)
    }

    // MARK: - Key handling helpers (used by `MarkdownTextView.doCommand(by:)`)

    public func handleTab() {
        if !session.indent() {
            session.insertTab()
        }
    }

    public func handleShiftTab() {
        _ = session.outdent()
    }

    // MARK: - Checkbox hit-testing

    /// `point` is expressed in text container coordinates (see `MarkdownTextView.mouseDown`).
    /// Returns the source range of the task's `[ ]`/`[x]` marker when `point` lands on a checkbox glyph.
    public func checkboxHit(at point: CGPoint) -> NSRange? {
        guard let textLayoutManager = textView.textLayoutManager else { return nil }
        let containerWidth = textLayoutManager.textContainer?.size.width ?? textView.bounds.width
        let candidate = (textLayoutManager.textLayoutFragment(for: point) as? MarkdownLayoutFragment).flatMap { $0.layoutFragmentFrame.minY <= point.y && $0.layoutFragmentFrame.maxY >= point.y ? $0 : nil }
            ?? textLayoutManager.textLayoutFragment(for: CGPoint(x: max(1, containerWidth - 1), y: point.y)) as? MarkdownLayoutFragment
        guard let fragment = candidate, let rect = fragment.checkboxRect() else { return nil }
        let origin = fragment.layoutFragmentFrame.origin
        let localPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard rect.insetBy(dx: -4, dy: -4).contains(localPoint) else { return nil }
        guard let paragraph = fragment.textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
              let decoration = paragraph.attributedString.attribute(EditorAttributeKey.blockDecoration, at: 0, effectiveRange: nil) as? BlockDecoration,
              let marker = decoration.marker, case .checkbox(_, let markerSourceRange) = marker else { return nil }
        return markerSourceRange
    }

    // MARK: - Paste / formatting commands

    /// Inserts text (e.g. from a paste) at the current selection through the session.
    public func insertText(_ text: String) {
        _ = session.replaceDisplay(range: textView.selectedRange(), with: text)
    }

    public func performFormat(_ format: InlineFormat) {
        session.toggleInline(format)
    }

    public func setHeading(_ level: Int?) {
        session.setHeadingLevel(level)
    }

    public func toggleList(_ kind: ListKind) {
        session.toggleList(kind)
    }
}
#endif
