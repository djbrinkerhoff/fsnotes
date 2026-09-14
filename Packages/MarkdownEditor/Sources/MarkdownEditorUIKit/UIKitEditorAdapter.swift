#if canImport(UIKit)
import UIKit
import MarkdownEditorCore
import MarkdownEditorTextKit

/// Bridges a `MarkdownTextView` to an `EditorSession`: routes every text-view edit to the
/// session, and applies every `PresentationUpdate` the session publishes back to the text
/// storage. Also owns copy/paste-as-Markdown, checkbox/wiki-link tap routing, formatting/menu
/// commands and Dynamic Type re-theming.
@MainActor
public final class UIKitEditorAdapter: NSObject, UITextViewDelegate, EditorSessionDelegate {
    public let textView: MarkdownTextView
    public private(set) var session: EditorSession
    private var builder: AttributeBuilder

    /// Changing the theme rebuilds every attribute in the text storage (and re-themes newly
    /// created layout fragments) without touching the underlying Markdown source or selection.
    public var theme: ResolvedTheme {
        didSet { rebuildAttributesFully() }
    }

    public var onOpenLink: ((URL) -> Void)?
    public var onOpenWikiLink: ((String) -> Void)?
    public var onEditorDidChange: (() -> Void)?

    /// True while `session(_:didApply:)` is mutating the text storage itself, so the resulting
    /// `UITextViewDelegate` callbacks it triggers don't get fed back into the session.
    private var isApplyingUpdate = false
    /// Set when the native view changed the display text on its own (marked/IME text) and must
    /// be reconciled with the session once composition ends.
    private var needsReconcile = false
    /// Caret location as of the last selection-changed callback, used to detect "jumps" (taps,
    /// arrow-key-across-lines, programmatic moves) that should break typing-undo coalescing.
    private var lastCaretLocation = NSNotFound
    private var contentSizeObserver: NSObjectProtocol?

    public init(textView: MarkdownTextView, session: EditorSession, theme: ResolvedTheme) {
        self.textView = textView
        self.session = session
        self.theme = theme
        self.builder = AttributeBuilder(theme: theme)
        super.init()

        textView.adapter = self
        textView.theme = theme
        textView.delegate = self
        session.delegate = self

        textView.attributedText = builder.attributedString(for: session.presentation)
        textView.typingAttributes = builder.baseAttributes

        observeContentSizeChanges()
        refreshCheckboxAccessibility()
    }

    deinit {
        if let contentSizeObserver {
            NotificationCenter.default.removeObserver(contentSizeObserver)
        }
    }

    /// Swaps in a new document entirely: replaces the text storage, resets selection and scroll,
    /// and clears any pending reconciliation.
    public func setSession(_ newSession: EditorSession) {
        session.delegate = nil
        session = newSession
        session.delegate = self

        isApplyingUpdate = true
        let attributed = builder.attributedString(for: session.presentation)
        textView.attributedText = attributed
        textView.typingAttributes = builder.baseAttributes
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.setContentOffset(.zero, animated: false)
        isApplyingUpdate = false

        needsReconcile = false
        lastCaretLocation = NSNotFound
        refreshCheckboxAccessibility()
    }

    private func rebuildAttributesFully() {
        builder = AttributeBuilder(theme: theme)
        textView.theme = theme

        isApplyingUpdate = true
        let selection = textView.selectedRange
        let attributed = builder.attributedString(for: session.presentation)
        textView.attributedText = attributed
        textView.typingAttributes = builder.baseAttributes
        textView.selectedRange = clamp(selection, to: attributed.length)
        isApplyingUpdate = false

        refreshCheckboxAccessibility()
    }

    // MARK: - EditorSessionDelegate

    public func session(_ session: EditorSession, didApply update: PresentationUpdate) {
        isApplyingUpdate = true
        defer { isApplyingUpdate = false }

        let storage = textView.textStorage
        storage.beginEditing()
        if update.isFullReplacement {
            storage.setAttributedString(builder.attributedString(for: session.presentation))
        } else {
            if update.replacedDisplayRange.length > 0 || !update.replacementText.isEmpty {
                let replacement = NSAttributedString(string: update.replacementText, attributes: builder.baseAttributes)
                guard NSMaxRange(update.replacedDisplayRange) <= storage.length else {
                    storage.endEditing()
                    return
                }
                storage.replaceCharacters(in: update.replacedDisplayRange, with: replacement)
            }
            let replacedEnd = update.replacedDisplayRange.location + (update.replacementText as NSString).length
            let editedRange = NSRange(location: update.replacedDisplayRange.location, length: max(0, replacedEnd - update.replacedDisplayRange.location))
            for line in session.presentation.lines where rangesIntersect(line.displayRange, update.restyleDisplayRange) || rangesIntersect(line.displayRange, editedRange) {
                builder.apply(line, to: storage, includeNewline: true)
            }
        }
        storage.endEditing()

        let clampedSelection = clamp(update.selection, to: storage.length)
        textView.selectedRange = clampedSelection
        textView.typingAttributes = typingAttributes(atDisplay: clampedSelection.location)
        ensureCaretVisibleIfNeeded()
        refreshCheckboxAccessibility()
    }

    public func sessionDidEditDocument(_ session: EditorSession) {
        onEditorDidChange?()
    }

    // MARK: - UITextViewDelegate

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if textView.markedTextRange != nil {
            needsReconcile = true
            return true
        }
        if (textView.text as NSString) != (session.presentation.displayText as NSString) {
            // Native view changed the display text on its own (dictation, autocorrect commit, …).
            session.reconcile(displayText: textView.text, selection: textView.selectedRange)
        }

        textView.inputDelegate?.selectionWillChange(textView)
        textView.inputDelegate?.textWillChange(textView)
        defer {
            textView.inputDelegate?.textDidChange(textView)
            textView.inputDelegate?.selectionDidChange(textView)
        }

        if text == "\n" {
            session.insertNewline()
            return false
        }
        if text == "\t" {
            handleTab()
            return false
        }
        if text.isEmpty, range.length == 1, NSMaxRange(range) == textView.selectedRange.location {
            if !session.handleBackspace() {
                session.replaceDisplay(range: range, with: text)
            }
            return false
        }
        session.replaceDisplay(range: range, with: text)
        return false
    }

    public func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingUpdate, needsReconcile, textView.markedTextRange == nil else { return }
        session.reconcile(displayText: textView.text, selection: textView.selectedRange)
        needsReconcile = false
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isApplyingUpdate else { return }
        let newSelection = textView.selectedRange
        if lastCaretLocation != NSNotFound, abs(newSelection.location - lastCaretLocation) > 1 {
            session.breakUndoCoalescing()
        }
        lastCaretLocation = newSelection.length == 0 ? newSelection.location : NSNotFound
        session.selection = newSelection
    }

    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        onOpenLink?(URL)
        return false
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refreshCheckboxAccessibility()
    }

    // MARK: - Tab / outdent

    public func handleTab() {
        if !session.indent() {
            session.insertTab()
        }
    }

    public func handleShiftTab() {
        _ = session.outdent()
    }

    // MARK: - Paste helper

    /// Inserts plain text at the current selection through the session (used by `paste(_:)`).
    public func insertText(_ text: String) {
        session.replaceDisplay(range: textView.selectedRange, with: text)
    }

    // MARK: - Checkbox / wiki-link hit testing

    /// Converts `point` (text-view coordinates) to a `markerSourceRange` when it lands on a
    /// rendered checkbox glyph, expanding the drawn box by 8pt on every side for an easier target.
    public func checkboxHit(at point: CGPoint) -> NSRange? {
        guard let tlm = textView.textLayoutManager else { return nil }
        let containerPoint = CGPoint(x: point.x - textView.textContainerInset.left, y: point.y - textView.textContainerInset.top)
        guard let fragment = tlm.textLayoutFragment(for: containerPoint) as? MarkdownLayoutFragment else { return nil }
        guard let rect = fragment.checkboxRect() else { return nil }
        let local = CGPoint(x: containerPoint.x - fragment.layoutFragmentFrame.origin.x, y: containerPoint.y - fragment.layoutFragmentFrame.origin.y)
        guard rect.insetBy(dx: -8, dy: -8).contains(local) else { return nil }
        guard case .checkbox(_, let markerSourceRange) = fragment.blockDecoration?.marker else { return nil }
        return markerSourceRange
    }

    public func handleTap(at point: CGPoint) -> Bool {
        if let markerRange = checkboxHit(at: point) {
            return session.toggleTask(markerSourceRange: markerRange)
        }
        if let destination = wikiLinkDestination(at: point) {
            onOpenWikiLink?(destination)
            return true
        }
        return false
    }

    @discardableResult
    public func toggleTask(atDisplayLine index: Int) -> Bool {
        session.toggleTask(atDisplayLine: index)
    }

    /// Best-effort wiki-link tap detection. `AttributeBuilder` never sets `.link` for wiki links
    /// (only real Markdown links/autolinks get it), so `textView(_:shouldInteractWith:in:interaction:)`
    /// is never invoked for them by UIKit; this is the fallback path, reached through the same
    /// tap recognizer used for checkboxes.
    func wikiLinkDestination(at point: CGPoint) -> String? {
        guard let position = textView.closestPosition(to: point) else { return nil }
        let offset = textView.offset(from: textView.beginningOfDocument, to: position)
        let storage = textView.textStorage
        guard offset >= 0, offset < storage.length else { return nil }
        guard storage.attribute(.link, at: offset, effectiveRange: nil) == nil else { return nil }
        return storage.attribute(EditorAttributeKey.destination, at: offset, effectiveRange: nil) as? String
    }

    // MARK: - Menu / toolbar hooks

    public func performFormat(_ format: InlineFormat) {
        session.toggleInline(format)
    }

    public func setHeading(_ level: Int?) {
        session.setHeadingLevel(level)
    }

    public func toggleList(_ kind: ListKind) {
        session.toggleList(kind)
    }

    public var isSourceMode: Bool { session.mode == .source }

    public func toggleSourceMode() {
        session.toggleMode()
    }

    // MARK: - Dynamic Type

    /// Builds a `ResolvedTheme` whose body/code fonts scale with `.body` Dynamic Type metrics.
    public static func makeTheme(bodyFont: UIFont = .preferredFont(forTextStyle: .body), codeFont: UIFont? = nil, palette: EditorPalette = .system) -> ResolvedTheme {
        let metrics = UIFontMetrics(forTextStyle: .body)
        let scaledBody = metrics.scaledFont(for: bodyFont)
        let scaledCode = codeFont.map { metrics.scaledFont(for: $0) }
        return ResolvedTheme(palette: palette, bodyFont: scaledBody, codeFont: scaledCode)
    }

    private func observeContentSizeChanges() {
        contentSizeObserver = NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.theme = Self.makeTheme(bodyFont: self.theme.bodyFont, palette: self.theme.palette)
        }
    }

    // MARK: - Accessibility

    private func refreshCheckboxAccessibility() {
        guard let tlm = textView.textLayoutManager, let contentManager = tlm.textContentManager else {
            textView.checkboxAccessibilityOverlay.elements = []
            return
        }
        let displayText = textView.textStorage.string as NSString
        var elements: [TaskAccessibilityElement] = []
        for line in session.presentation.lines {
            guard let markerRange = line.block.taskMarkerSourceRange, case .task(let isChecked) = line.block.listMarker else { continue }
            guard let start = contentManager.location(contentManager.documentRange.location, offsetBy: line.displayRange.location) else { continue }
            var frame: CGRect?
            tlm.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
                frame = fragment.layoutFragmentFrame
                return false
            }
            guard var rect = frame else { continue }
            rect.origin.x += textView.textContainerInset.left
            rect.origin.y += textView.textContainerInset.top

            let element = TaskAccessibilityElement(accessibilityContainer: textView, markerSourceRange: markerRange, adapter: self)
            if NSMaxRange(line.displayRange) <= displayText.length {
                element.accessibilityLabel = displayText.substring(with: line.displayRange)
            }
            element.accessibilityTraits = .button
            element.accessibilityValue = isChecked ? "checked" : "unchecked"
            element.accessibilityFrameInContainerSpace = rect
            elements.append(element)
        }
        textView.checkboxAccessibilityOverlay.elements = elements
    }

    // MARK: - Helpers

    private func typingAttributes(atDisplay offset: Int) -> [NSAttributedString.Key: Any] {
        let clamped = max(0, min(offset, session.presentation.displayLength))
        let line = session.presentation.line(atDisplay: clamped)
        return builder.attributes(for: line).paragraph
    }

    private func ensureCaretVisibleIfNeeded() {
        guard let selectedTextRange = textView.selectedTextRange else { return }
        let caretRect = textView.caretRect(for: selectedTextRange.end)
        guard caretRect.origin.x.isFinite, caretRect.origin.y.isFinite else { return }
        let visible = textView.bounds.inset(by: textView.contentInset)
        if !visible.contains(CGPoint(x: caretRect.midX, y: caretRect.midY)) {
            textView.scrollRangeToVisible(textView.selectedRange)
        }
    }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let loc = max(0, min(range.location, length))
        let len = max(0, min(range.length, length - loc))
        return NSRange(location: loc, length: len)
    }

    private func rangesIntersect(_ a: NSRange, _ b: NSRange) -> Bool {
        if a.length == 0 { return b.location <= a.location && a.location <= NSMaxRange(b) }
        if b.length == 0 { return a.location <= b.location && b.location <= NSMaxRange(a) }
        return a.location < NSMaxRange(b) && b.location < NSMaxRange(a)
    }
}
#endif
