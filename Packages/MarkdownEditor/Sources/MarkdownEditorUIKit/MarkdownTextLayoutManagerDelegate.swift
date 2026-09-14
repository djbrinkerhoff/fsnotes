#if canImport(UIKit)
import UIKit
import MarkdownEditorTextKit

/// Vends `MarkdownLayoutFragment` instances so paragraphs can draw their own margin decorations.
@MainActor
public final class MarkdownTextLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    /// Updated by `UIKitEditorAdapter` whenever the theme changes; picked up by fragments created afterwards.
    public var theme: ResolvedTheme

    public init(theme: ResolvedTheme) {
        self.theme = theme
    }

    public func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = MarkdownLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.theme = theme
        return fragment
    }
}
#endif
