#if canImport(AppKit)
import AppKit
import MarkdownEditorCore
// Re-exported so consumers of `MarkdownEditorAppKit` (including its test target, which per its
// Package.swift manifest only depends on `MarkdownEditorCore` and this target) can name
// `ResolvedTheme`, `AttributeBuilder`, etc. without adding a direct dependency edge.
@_exported import MarkdownEditorTextKit

/// Accessibility element for one visible task list item. Pressing it toggles the checkbox through
/// the session, exactly like a mouse click on the checkbox glyph.
final class TaskAccessibilityElement: NSAccessibilityElement {
    weak var adapter: AppKitEditorAdapter?
    var markerSourceRange: NSRange = NSRange(location: 0, length: 0)

    override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated {
            guard let adapter else { return false }
            return adapter.session.toggleTask(markerSourceRange: markerSourceRange)
        }
    }
}

/// The hidden-syntax Markdown text view. Built on TextKit 2 (`NSTextLayoutManager` /
/// `NSTextContentStorage`) so paragraphs can be given custom `MarkdownLayoutFragment`s that draw
/// list markers, checkboxes, quote bars and code backgrounds in the margin.
///
/// This view never applies edits to its own text storage directly: every key command and text
/// change is routed to the `EditorSession` through `adapter`, which replays the resulting
/// `PresentationUpdate` back into the storage. Native undo is disabled; `adapter` vends the
/// session's `UndoManager` instead.
@MainActor
public final class MarkdownTextView: NSTextView {
    /// Set by `AppKitEditorAdapter.init`. Weak: the adapter owns/outlives the text view from the
    /// host's perspective, not the other way around.
    public weak var adapter: AppKitEditorAdapter?

    /// Retains the `NSTextLayoutManagerDelegate` (the delegate property itself is weak).
    private var layoutManagerDelegate: MarkdownTextLayoutManagerDelegate?

    public var theme: ResolvedTheme = ResolvedTheme(bodyFont: .systemFont(ofSize: NSFont.systemFontSize)) {
        didSet {
            layoutManagerDelegate?.currentTheme = theme
            needsLayout = true
            needsDisplay = true
        }
    }

    // MARK: - Construction

    /// Builds an `NSTextView` wired explicitly for TextKit 2 (never touching the legacy
    /// `NSLayoutManager`, which would silently fall back the view to TextKit 1), embedded in a
    /// vertically scrolling `NSScrollView`.
    public static func makeScrollableEditor(theme: ResolvedTheme) -> (scrollView: NSScrollView, textView: MarkdownTextView) {
        let textLayoutManager = NSTextLayoutManager()
        let textContentStorage = NSTextContentStorage()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        textLayoutManager.textContainer = textContainer

        let textView = MarkdownTextView(frame: .zero, textContainer: textContainer)
        textView.theme = theme
        textView.applySettings(theme: theme)

        let layoutManagerDelegate = MarkdownTextLayoutManagerDelegate(theme: theme)
        textLayoutManager.delegate = layoutManagerDelegate
        textView.layoutManagerDelegate = layoutManagerDelegate

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        return (scrollView, textView)
    }

    private func applySettings(theme: ResolvedTheme) {
        allowsUndo = false
        isRichText = true
        importsGraphics = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        allowsImageEditing = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0
        textContainerInset = NSSize(width: theme.theme.textInsetHorizontal, height: theme.theme.textInsetVertical)
    }

    // MARK: - Centered max-width column

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextContainerInset()
    }

    public override func layout() {
        super.layout()
        updateTextContainerInset()
    }

    private func updateTextContainerInset() {
        let vertical = theme.theme.textInsetVertical
        guard let maxWidth = theme.theme.maxContentWidth, bounds.width > CGFloat(maxWidth) else {
            textContainerInset = NSSize(width: theme.theme.textInsetHorizontal, height: vertical)
            return
        }
        let horizontal = (bounds.width - CGFloat(maxWidth)) / 2
        textContainerInset = NSSize(width: horizontal, height: vertical)
    }

    // MARK: - Key handling

    public override func doCommand(by selector: Selector) {
        guard !hasMarkedText(), let adapter else {
            super.doCommand(by: selector)
            return
        }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            adapter.session.insertNewline()
        case #selector(NSResponder.insertTab(_:)):
            adapter.handleTab()
        case #selector(NSResponder.insertBacktab(_:)):
            adapter.handleShiftTab()
        case #selector(NSResponder.deleteBackward(_:)):
            if !adapter.session.handleBackspace() {
                super.doCommand(by: selector)
            }
        default:
            super.doCommand(by: selector)
        }
    }

    // MARK: - Checkbox toggling

    public override func mouseDown(with event: NSEvent) {
        guard let adapter else {
            super.mouseDown(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(x: viewPoint.x - textContainerOrigin.x, y: viewPoint.y - textContainerOrigin.y)
        if let markerRange = adapter.checkboxHit(at: containerPoint) {
            _ = adapter.session.toggleTask(markerSourceRange: markerRange)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: - Copy / Paste / Cut

    public override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { super.copy(sender); return }
        let text = (string as NSString).substring(with: range)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Copies the underlying Markdown source (with hidden syntax restored) for the current
    /// selection, rather than the plain display text that `copy(_:)` writes.
    @objc public func copyMarkdown(_ sender: Any?) {
        guard let adapter else { return }
        let markdown = adapter.session.markdown(forDisplayRange: selectedRange())
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }

    public override func paste(_ sender: Any?) {
        guard let adapter, let text = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        adapter.insertText(text)
    }

    public override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    public override func cut(_ sender: Any?) {
        guard let adapter else { super.cut(sender); return }
        copy(sender)
        _ = adapter.session.replaceDisplay(range: selectedRange(), with: "")
    }

    // MARK: - Context menu

    public override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        if let copyItem = menu.items.first(where: { $0.action == #selector(NSText.copy(_:)) }) {
            let item = NSMenuItem(title: "Copy Markdown", action: #selector(copyMarkdown(_:)), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: menu.index(of: copyItem) + 1)
        }
        return menu
    }

    // MARK: - Validation

    public override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copyMarkdown(_:)) {
            return selectedRange().length > 0
        }
        return super.validateMenuItem(menuItem)
    }

    public override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copyMarkdown(_:)) {
            return selectedRange().length > 0
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Accessibility

    public override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        guard let adapter else { return children }
        let ns = string as NSString
        for line in adapter.session.presentation.lines {
            guard case .task(let isChecked) = line.block.listMarker ?? .bullet, line.block.listMarker != nil,
                  let markerRange = line.block.taskMarkerSourceRange,
                  NSMaxRange(line.displayRange) <= ns.length else { continue }
            guard let screenRect = boundingScreenRect(forDisplayRange: line.displayRange), isRectVisible(screenRect) else { continue }
            let element = TaskAccessibilityElement()
            element.adapter = adapter
            element.markerSourceRange = markerRange
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.checkBox)
            element.setAccessibilityLabel(ns.substring(with: line.displayRange))
            element.setAccessibilityValue(isChecked ? 1 : 0)
            element.setAccessibilityFrame(screenRect)
            children.append(element)
        }
        return children
    }

    private func boundingScreenRect(forDisplayRange range: NSRange) -> CGRect? {
        var actual = NSRange(location: 0, length: 0)
        let rect = firstRect(forCharacterRange: range, actualRange: &actual)
        guard rect != .zero else { return nil }
        return rect
    }

    private func isRectVisible(_ screenRect: CGRect) -> Bool {
        guard let window else { return true }
        let windowRect = window.convertFromScreen(screenRect)
        let localRect = convert(windowRect, from: nil)
        return visibleRect.intersects(localRect)
    }
}
#endif
