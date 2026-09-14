#if canImport(UIKit)
import UIKit
import MarkdownEditorCore

/// Transparent overlay sitting on top of `MarkdownTextView` that vends one `UIAccessibilityElement`
/// per visible task line, so VoiceOver users can navigate and toggle checkboxes directly.
/// The text view keeps its own native text accessibility; this overlay only adds the extra
/// per-checkbox elements.
@MainActor
final class CheckboxAccessibilityOverlay: UIView {
    var elements: [UIAccessibilityElement] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var accessibilityElements: [Any]? {
        get { elements }
        set { /* read-only from the outside; refreshed via `elements`. */ }
    }
}

/// One task-list line, exposed to VoiceOver as a button whose activation toggles the checkbox.
@MainActor
final class TaskAccessibilityElement: UIAccessibilityElement {
    let markerSourceRange: NSRange
    weak var adapter: UIKitEditorAdapter?

    init(accessibilityContainer container: Any, markerSourceRange: NSRange, adapter: UIKitEditorAdapter?) {
        self.markerSourceRange = markerSourceRange
        self.adapter = adapter
        super.init(accessibilityContainer: container)
    }

    override func accessibilityActivate() -> Bool {
        adapter?.session.toggleTask(markerSourceRange: markerSourceRange) ?? false
    }
}
#endif
