#if canImport(AppKit)
import AppKit
import MarkdownEditorCore
import MarkdownEditorTextKit

/// Supplies the theme a `MarkdownLayoutFragment` should draw with. Implemented by the object that
/// owns the `NSTextLayoutManager` delegate so fragments always read the current theme.
@MainActor
protocol MarkdownThemeProviding: AnyObject {
    var currentTheme: ResolvedTheme { get }
}

/// `NSTextLayoutManagerDelegate` that vends `MarkdownLayoutFragment`s so paragraphs can draw their
/// margin decorations (list markers, checkboxes, quote bars, code backgrounds, thematic breaks).
@MainActor
final class MarkdownTextLayoutManagerDelegate: NSObject, @preconcurrency NSTextLayoutManagerDelegate, MarkdownThemeProviding {
    var currentTheme: ResolvedTheme

    init(theme: ResolvedTheme) {
        self.currentTheme = theme
    }

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = MarkdownLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.themeProvider = self
        return fragment
    }
}

/// A paragraph's layout fragment. Draws the block-level decorations described by `BlockDecoration`
/// (attached to the paragraph's first character as `EditorAttributeKey.blockDecoration`) before the
/// normal text is drawn: code block backgrounds, quote bars, list/task markers, and thematic breaks.
public final class MarkdownLayoutFragment: NSTextLayoutFragment {
    weak var themeProvider: MarkdownThemeProviding?

    public required init?(coder: NSCoder) {
        fatalError("MarkdownLayoutFragment does not support coding")
    }

    override init(textElement: NSTextElement, range: NSTextRange?) {
        super.init(textElement: textElement, range: range)
    }

    /// Extends the drawable area leftwards so margin decorations are never clipped.
    public override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        return MainActor.assumeIsolated {
            guard let theme = themeProvider?.currentTheme, let decoration = blockDecoration(),
                  decoration.marker != nil || !decoration.quoteBarXs.isEmpty || decoration.isCodeBlock else { return bounds }
            let extension_ = max(0, originShift(decoration: decoration, theme: theme)) + theme.codeBlockPadding + 4
            bounds.origin.x -= extension_
            bounds.size.width += extension_ + theme.codeBlockPadding
            return bounds
        }
    }

    public override func draw(at point: CGPoint, in context: CGContext) {
        // `draw(at:in:)` is nonisolated (it overrides an AppKit method that isn't main-actor
        // annotated), but TextKit only ever draws on the main thread, so it's safe to assume
        // isolation here to read the (@MainActor) theme provider.
        MainActor.assumeIsolated {
            if let theme = themeProvider?.currentTheme, let decoration = blockDecoration() {
                drawDecoration(decoration, theme: theme, point: point, context: context)
            }
        }
        super.draw(at: point, in: context)
    }

    /// Fragment-local rect of the checkbox glyph, for hit-testing. `nil` unless this paragraph is a task item.
    public func checkboxRect() -> CGRect? {
        MainActor.assumeIsolated {
            guard let decoration = blockDecoration(),
                  let marker = decoration.marker,
                  case .checkbox = marker,
                  let theme = themeProvider?.currentTheme,
                  let firstLine = textLineFragments.first else { return nil }
            return checkboxFrame(decoration: decoration, theme: theme, firstLine: firstLine)
        }
    }

    // MARK: - Reading the decoration

    private func blockDecoration() -> BlockDecoration? {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else { return nil }
        return paragraph.attributedString.attribute(EditorAttributeKey.blockDecoration, at: 0, effectiveRange: nil) as? BlockDecoration
    }

    /// Best-effort: the width of the container this fragment lays out in. Falls back to the
    /// fragment's own width when the layout manager/container chain can't be resolved.
    private var containerWidth: CGFloat {
        if let contentManager = textElement?.textContentManager as? NSTextContentStorage,
           let manager = contentManager.textLayoutManagers.first,
           let width = manager.textContainer?.size.width, width > 0, width.isFinite {
            return width
        }
        return layoutFragmentFrame.width
    }

    // MARK: - Neighbor detection (best-effort; see note below)

    /// Whether the immediately preceding paragraph is also a code block line, so the shared edge
    /// between the two backgrounds can be drawn square instead of rounded.
    ///
    /// This walks the text content manager by asking for the text element one UTF-16 location
    /// before this fragment's range. It is a best-effort approach: if the content manager chain
    /// can't be resolved (e.g. mid-edit) we simply draw a rounded corner, which only affects the
    /// visual seam between adjacent code lines and never the rest of the drawing.
    private func isPreviousParagraphCodeBlock() -> Bool {
        guard let element = textElement, let range = element.elementRange,
              let contentStorage = element.textContentManager as? NSTextContentStorage,
              let previousLocation = contentStorage.location(range.location, offsetBy: -1) else { return false }
        return isCodeBlockParagraph(at: previousLocation, in: contentStorage)
    }

    private func isNextParagraphCodeBlock() -> Bool {
        guard let element = textElement, let range = element.elementRange,
              let contentStorage = element.textContentManager as? NSTextContentStorage else { return false }
        return isCodeBlockParagraph(at: range.endLocation, in: contentStorage)
    }

    private func isCodeBlockParagraph(at location: NSTextLocation, in contentStorage: NSTextContentStorage) -> Bool {
        let range = NSTextRange(location: location)
        guard let paragraph = contentStorage.textElements(for: range).first as? NSTextParagraph, paragraph.attributedString.length > 0,
              let decoration = paragraph.attributedString.attribute(EditorAttributeKey.blockDecoration, at: 0, effectiveRange: nil) as? BlockDecoration else { return false }
        return decoration.isCodeBlock
    }

    /// Shift between the text-container coordinate space the decoration was computed in and this
    /// fragment's local space (non-zero when the fragment origin already includes the head indent).
    private func originShift(decoration: BlockDecoration, theme: ResolvedTheme) -> CGFloat {
        let expectedIndent = CGFloat(decoration.quoteDepth) * theme.quoteIndentWidth
            + CGFloat(decoration.listDepth) * theme.listIndentWidth
            + (decoration.isCodeBlock ? theme.codeBlockPadding : 0)
        guard let actual = textLineFragments.first?.typographicBounds.minX else { return 0 }
        let shift = expectedIndent - actual
        return abs(shift) < 0.5 ? 0 : shift
    }

    // MARK: - Drawing

    private func drawDecoration(_ decoration: BlockDecoration, theme: ResolvedTheme, point: CGPoint, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let height = layoutFragmentFrame.height

        if decoration.isCodeBlock {
            drawCodeBackground(decoration, theme: theme, point: point, height: height, context: context)
        }
        for x in decoration.quoteBarXs {
            drawQuoteBar(x: x - originShift(decoration: decoration, theme: theme), theme: theme, point: point, height: height, context: context)
        }
        if let marker = decoration.marker, let firstLine = textLineFragments.first {
            drawMarker(marker, decoration: decoration, theme: theme, point: point, firstLine: firstLine, context: context)
        }
        if decoration.isThematicBreak {
            drawThematicBreak(theme: theme, point: point, height: height, context: context)
        }
    }

    private func drawCodeBackground(_ decoration: BlockDecoration, theme: ResolvedTheme, point: CGPoint, height: CGFloat, context: CGContext) {
        let indent = CGFloat(decoration.quoteDepth) * theme.quoteIndentWidth + CGFloat(decoration.listDepth) * theme.listIndentWidth
        let leading = max(0, indent - theme.codeBlockPadding) - originShift(decoration: decoration, theme: theme)
        let x = point.x + leading
        let width = max(0, containerWidth - max(0, leading))
        let rect = CGRect(x: x, y: point.y, width: width, height: height)
        let topRadius: CGFloat = isPreviousParagraphCodeBlock() ? 0 : theme.theme.codeCornerRadius
        let bottomRadius: CGFloat = isNextParagraphCodeBlock() ? 0 : theme.theme.codeCornerRadius
        let path = roundedRectPath(rect, topRadius: topRadius, bottomRadius: bottomRadius)
        context.addPath(path)
        context.setFillColor(theme.palette.color(.codeBackground).cgColor)
        context.fillPath()
    }

    private func drawQuoteBar(x: CGFloat, theme: ResolvedTheme, point: CGPoint, height: CGFloat, context: CGContext) {
        let width = theme.theme.quoteRuleWidth
        let rect = CGRect(x: point.x + x, y: point.y, width: width, height: height)
        let path = CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil)
        context.addPath(path)
        context.setFillColor(theme.palette.color(.quoteRule).cgColor)
        context.fillPath()
    }

    private func drawThematicBreak(theme: ResolvedTheme, point: CGPoint, height: CGFloat, context: CGContext) {
        let y = point.y + height / 2
        context.setStrokeColor(theme.palette.color(.quoteRule).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: point.x, y: y))
        context.addLine(to: CGPoint(x: point.x + containerWidth, y: y))
        context.strokePath()
    }

    /// The marker's bounding box, in fragment-local coordinates, aligned to the first line fragment.
    private func markerBox(decoration: BlockDecoration, firstLine: NSTextLineFragment) -> CGRect {
        let lineRect = firstLine.typographicBounds
        let shift = MainActor.assumeIsolated { themeProvider.map { originShift(decoration: decoration, theme: $0.currentTheme) } ?? 0 }
        return CGRect(x: decoration.markerX - shift, y: lineRect.minY, width: decoration.markerWidth, height: lineRect.height)
    }

    private func checkboxFrame(decoration: BlockDecoration, theme: ResolvedTheme, firstLine: NSTextLineFragment) -> CGRect {
        let box = markerBox(decoration: decoration, firstLine: firstLine)
        let size = theme.checkboxSize
        return CGRect(x: box.maxX - size, y: box.midY - size / 2, width: size, height: size)
    }

    private func drawMarker(_ marker: BlockDecoration.Marker, decoration: BlockDecoration, theme: ResolvedTheme, point: CGPoint, firstLine: NSTextLineFragment, context: CGContext) {
        let box = markerBox(decoration: decoration, firstLine: firstLine).offsetBy(dx: point.x, dy: point.y)
        switch marker {
        case .bullet:
            let diameter = theme.bodySize * 0.3
            let rect = CGRect(x: box.maxX - diameter, y: box.midY - diameter / 2, width: diameter, height: diameter)
            context.setFillColor(theme.palette.color(.listMarker).cgColor)
            context.fillEllipse(in: rect)
        case .number(let n):
            drawText("\(n).", font: theme.bodyFont, color: theme.palette.color(.listMarker), rightAlignedIn: box)
        case .checkbox(let isChecked, _):
            let rect = checkboxFrame(decoration: decoration, theme: theme, firstLine: firstLine).offsetBy(dx: point.x, dy: point.y)
            drawCheckbox(isChecked: isChecked, in: rect, theme: theme, context: context)
        }
    }

    private func drawCheckbox(isChecked: Bool, in rect: CGRect, theme: ResolvedTheme, context: CGContext) {
        let radius = theme.theme.checkboxCornerRadius
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if isChecked {
            context.addPath(path)
            context.setFillColor(theme.palette.color(.checkboxChecked).cgColor)
            context.fillPath()
            let check = CGMutablePath()
            check.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.54))
            check.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.72))
            check.addLine(to: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.30))
            context.addPath(check)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        } else {
            context.addPath(path)
            context.setStrokeColor(theme.palette.color(.checkbox).cgColor)
            context.setLineWidth(1.5)
            context.strokePath()
        }
    }

    /// Draws right-aligned, vertically centered text (used for ordered-list numbers) into `rect`,
    /// which is already in the fragment's drawing coordinate space (i.e. offset by the draw point).
    private func drawText(_ string: String, font: PlatformFont, color: PlatformColor, rightAlignedIn rect: CGRect) {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let size = attributed.size()
        let origin = CGPoint(x: rect.maxX - size.width, y: rect.midY - size.height / 2)
        guard let graphicsContext = NSGraphicsContext.current else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: graphicsContext.cgContext, flipped: true)
        attributed.draw(at: origin)
    }

    /// A rect path with independently square-able top and bottom corners (used to butt adjacent
    /// code-block line backgrounds together into what reads as a single rounded box).
    private func roundedRectPath(_ rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
        guard topRadius > 0 || bottomRadius > 0 else { return CGPath(rect: rect, transform: nil) }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topRadius, y: rect.minY), radius: topRadius)
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRadius), radius: topRadius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY), radius: bottomRadius)
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius), radius: bottomRadius)
        path.closeSubpath()
        return path
    }
}
#endif
