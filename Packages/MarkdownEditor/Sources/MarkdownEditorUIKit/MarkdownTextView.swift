#if canImport(UIKit)
import UIKit
import MarkdownEditorCore
import MarkdownEditorTextKit

/// TextKit 2-backed text view for the hidden-syntax Markdown editor. Displays presentation text
/// built by `AttributeBuilder`; all edits are routed through `UIKitEditorAdapter` to the
/// `EditorSession`, which owns the real Markdown source and undo stack.
@MainActor
public final class MarkdownTextView: UITextView {
    /// Current theme. Set by `UIKitEditorAdapter`; changing it re-centers the max-width column
    /// and causes new layout fragments to pick up the new metrics.
    public var theme: ResolvedTheme {
        didSet {
            layoutManagerDelegate.theme = theme
            setNeedsLayout()
        }
    }

    weak var adapter: UIKitEditorAdapter?
    let checkboxAccessibilityOverlay = CheckboxAccessibilityOverlay(frame: .zero)

    private let layoutManagerDelegate: MarkdownTextLayoutManagerDelegate
    private var tapRecognizer: UITapGestureRecognizer!

    /// System undo/redo (menu, ⌘Z, three-finger swipe/shake) drives the session's own undo
    /// manager instead of the responder chain's default one, since typing must never register
    /// native `NSTextStorage`-level undo.
    public override var undoManager: UndoManager? {
        adapter?.session.undoManager
    }

    public init(frame: CGRect, theme: ResolvedTheme) {
        self.theme = theme
        self.layoutManagerDelegate = MarkdownTextLayoutManagerDelegate(theme: theme)
        // Build the TextKit 2 stack explicitly; `init(usingTextLayoutManager:)` is a convenience
        // initializer that cannot be chained from a subclass.
        let contentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(textLayoutManager)
        let container = NSTextContainer(size: CGSize(width: max(frame.width, 1), height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        textLayoutManager.textContainer = container
        super.init(frame: frame, textContainer: container)
        precondition(self.textLayoutManager != nil, "MarkdownTextView requires TextKit 2")
        self.textLayoutManager?.delegate = layoutManagerDelegate
        configureAppearance()
        setupTapRecognizer()
        addSubview(checkboxAccessibilityOverlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configureAppearance() {
        smartQuotesType = .no
        smartDashesType = .no
        keyboardDismissMode = .interactive
        alwaysBounceVertical = true
        adjustsFontForContentSizeCategory = false
        isEditable = true
        isSelectable = true
        dataDetectorTypes = []
        linkTextAttributes = [.foregroundColor: theme.palette.color(.link)]
        textContainerInset = UIEdgeInsets(
            top: CGFloat(theme.theme.textInsetVertical), left: CGFloat(theme.theme.textInsetHorizontal),
            bottom: CGFloat(theme.theme.textInsetVertical), right: CGFloat(theme.theme.textInsetHorizontal))
        textContainer.lineFragmentPadding = 0
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        checkboxAccessibilityOverlay.frame = bounds
        centerContentColumnIfNeeded()
    }

    /// Centers the text column at `theme.theme.maxContentWidth` when the view is wider than that,
    /// by padding the container inset symmetrically instead of leaving text edge-to-edge.
    private func centerContentColumnIfNeeded() {
        let baseInset = CGFloat(theme.theme.textInsetHorizontal)
        guard let maxWidth = theme.theme.maxContentWidth, bounds.width > CGFloat(maxWidth) else {
            if textContainerInset.left != baseInset || textContainerInset.right != baseInset {
                textContainerInset.left = baseInset
                textContainerInset.right = baseInset
            }
            return
        }
        let sideInset = ((bounds.width - CGFloat(maxWidth)) / 2).rounded()
        if textContainerInset.left != sideInset || textContainerInset.right != sideInset {
            textContainerInset.left = sideInset
            textContainerInset.right = sideInset
        }
    }

    // MARK: - Copy / paste

    /// Copies the selected display text as plain text — never leak our custom attributes
    /// (block decorations, destinations, …) onto the pasteboard.
    public override func copy(_ sender: Any?) {
        let ns = text as NSString
        let range = selectedRange
        guard range.length > 0, NSMaxRange(range) <= ns.length else { return }
        UIPasteboard.general.string = ns.substring(with: range)
    }

    @objc public func copyMarkdown(_ sender: Any?) {
        guard let adapter, selectedRange.length > 0 else { return }
        UIPasteboard.general.string = adapter.session.markdown(forDisplayRange: selectedRange)
    }

    public override func paste(_ sender: Any?) {
        guard let adapter else {
            super.paste(sender)
            return
        }
        if let string = UIPasteboard.general.string {
            adapter.insertText(string)
        } else {
            super.paste(sender)
        }
    }

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copyMarkdown(_:)) {
            return selectedRange.length > 0
        }
        return super.canPerformAction(action, withSender: sender)
    }

    public override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.menu(for: .standardEdit) != nil else { return }
        let command = UICommand(title: "Copy Markdown", action: #selector(copyMarkdown(_:)))
        let menu = UIMenu(title: "", options: .displayInline, children: [command])
        builder.insertSibling(menu, afterMenu: .standardEdit)
    }

    // MARK: - Key commands

    public override var keyCommands: [UIKeyCommand]? {
        let tab = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTabKeyCommand))
        tab.wantsPriorityOverSystemBehavior = true
        let shiftTab = UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleShiftTabKeyCommand))
        shiftTab.wantsPriorityOverSystemBehavior = true
        let bold = UIKeyCommand(input: "b", modifierFlags: [.command], action: #selector(handleBoldKeyCommand))
        let italic = UIKeyCommand(input: "i", modifierFlags: [.command], action: #selector(handleItalicKeyCommand))
        let code = UIKeyCommand(input: "e", modifierFlags: [.command], action: #selector(handleCodeKeyCommand))
        return [tab, shiftTab, bold, italic, code] + (super.keyCommands ?? [])
    }

    @objc private func handleTabKeyCommand() { adapter?.handleTab() }
    @objc private func handleShiftTabKeyCommand() { adapter?.handleShiftTab() }
    @objc private func handleBoldKeyCommand() { adapter?.performFormat(.strong) }
    @objc private func handleItalicKeyCommand() { adapter?.performFormat(.emphasis) }
    @objc private func handleCodeKeyCommand() { adapter?.performFormat(.code) }

    // MARK: - Checkbox (and wiki-link) tap handling

    private func setupTapRecognizer() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        addGestureRecognizer(recognizer)
        tapRecognizer = recognizer
    }

    @objc private func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        _ = adapter?.handleTap(at: recognizer.location(in: self))
    }
}

extension MarkdownTextView: UIGestureRecognizerDelegate {
    /// Only let the recognizer see (and thus consume) touches that land on a checkbox or wiki
    /// link; everything else must fall through to the text view's own gesture recognizers so the
    /// caret still moves normally.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === tapRecognizer, let adapter else { return true }
        let point = touch.location(in: self)
        return adapter.checkboxHit(at: point) != nil || adapter.wikiLinkDestination(at: point) != nil
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
