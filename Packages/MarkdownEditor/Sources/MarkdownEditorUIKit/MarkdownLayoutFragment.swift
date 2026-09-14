#if canImport(UIKit)
import UIKit
import MarkdownEditorCore
import MarkdownEditorTextKit

/// `NSTextLayoutFragment` subclass that draws margin decorations (list markers, checkboxes,
/// quote bars, code-block backgrounds, thematic breaks) described by `BlockDecoration`.
///
/// The decoration is read from the fragment's paragraph (`NSTextParagraph.attributedString`)
/// first-character attributes, so it stays in sync automatically whenever the presentation is
/// rebuilt (the attribute is written by `AttributeBuilder`).
@MainActor
public final class MarkdownLayoutFragment: NSTextLayoutFragment {
    /// Set by `MarkdownTextLayoutManagerDelegate` right after creation.
    public var theme: ResolvedTheme?

    /// The paragraph's margin-decoration description, read from its first character's attributes.
    public var blockDecoration: BlockDecoration? {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else { return nil }
        return paragraph.attributedString.attribute(EditorAttributeKey.blockDecoration, at: 0, effectiveRange: nil) as? BlockDecoration
    }

    private var decoration: BlockDecoration? { blockDecoration }

    public override func draw(at point: CGPoint, in context: CGContext) {
        guard let theme, let decoration else {
            super.draw(at: point, in: context)
            return
        }
        let bounds = CGRect(origin: .zero, size: layoutFragmentFrame.size)

        // Background decorations (code block fill, quote bars) go behind the glyphs.
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        if decoration.isCodeBlock {
            drawCodeBackground(decoration: decoration, theme: theme, bounds: bounds, in: context)
        }
        if !decoration.quoteBarXs.isEmpty {
            drawQuoteBars(decoration: decoration, theme: theme, bounds: bounds, in: context)
        }
        context.restoreGState()

        super.draw(at: point, in: context)

        // Foreground decorations (markers, checkboxes, thematic break) go on top of the glyphs.
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        if let marker = decoration.marker {
            drawMarker(marker, decoration: decoration, theme: theme, bounds: bounds, in: context)
        }
        if decoration.isThematicBreak {
            drawThematicBreak(theme: theme, bounds: bounds, in: context)
        }
        context.restoreGState()
    }

    // MARK: Code block background

    private func drawCodeBackground(decoration: BlockDecoration, theme: ResolvedTheme, bounds: CGRect, in context: CGContext) {
        let x0 = (decoration.quoteBarXs.last ?? 0) + theme.quoteIndentWidth
        let x1 = bounds.width - theme.codeBlockPadding
        guard x1 > x0 else { return }
        let rect = CGRect(x: x0, y: 0, width: x1 - x0, height: bounds.height)
        // NOTE (spec deviation): detecting whether the previous/next paragraph is also a code
        // block (to square the shared edge and visually join consecutive lines) would require
        // reaching back into the text layout manager to inspect neighboring fragments, which
        // isn't exposed from a fragment itself in a straightforward way. Per the spec's own
        // fallback ("if too complex, draw a plain rect"), every code-block line draws its own
        // fully rounded rect; adjacent code lines will show a small double-rounded seam rather
        // than a single joined block.
        let path = UIBezierPath(roundedRect: rect, cornerRadius: theme.theme.codeCornerRadius)
        context.addPath(path.cgPath)
        context.setFillColor(theme.palette.color(.codeBackground).cgColor)
        context.fillPath()
    }

    // MARK: Quote bars

    private func drawQuoteBars(decoration: BlockDecoration, theme: ResolvedTheme, bounds: CGRect, in context: CGContext) {
        let width = theme.theme.quoteRuleWidth
        context.setFillColor(theme.palette.color(.quoteRule).cgColor)
        for x in decoration.quoteBarXs {
            let rect = CGRect(x: x, y: 0, width: width, height: bounds.height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: width / 2)
            context.addPath(path.cgPath)
            context.fillPath()
        }
    }

    // MARK: List / task markers

    private func firstLineRect() -> CGRect? {
        textLineFragments.first?.typographicBounds
    }

    /// Checkbox hit rect in the fragment's own (local) coordinate system, i.e. the same space
    /// used inside `draw(at:in:)` after translating by `point`.
    public func checkboxRect() -> CGRect? {
        guard let theme, let decoration, case .checkbox = decoration.marker, let line = firstLineRect() else { return nil }
        let size = theme.checkboxSize
        let y = line.midY - size / 2
        let x = decoration.markerX + max(0, decoration.markerWidth - size)
        return CGRect(x: x, y: y, width: size, height: size)
    }

    private func drawMarker(_ marker: BlockDecoration.Marker, decoration: BlockDecoration, theme: ResolvedTheme, bounds: CGRect, in context: CGContext) {
        guard let line = firstLineRect() else { return }
        switch marker {
        case .bullet:
            let diameter = theme.bodySize * 0.3
            let rect = CGRect(x: decoration.markerX + max(0, decoration.markerWidth - diameter), y: line.midY - diameter / 2, width: diameter, height: diameter)
            context.setFillColor(theme.palette.color(.listMarker).cgColor)
            context.fillEllipse(in: rect)

        case .number(let n):
            let text = "\(n)." as NSString
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .right
            let attrs: [NSAttributedString.Key: Any] = [
                .font: theme.bodyFont,
                .foregroundColor: theme.palette.color(.listMarker),
                .paragraphStyle: paragraphStyle,
            ]
            let size = text.size(withAttributes: attrs)
            let rect = CGRect(x: decoration.markerX, y: line.midY - size.height / 2, width: decoration.markerWidth, height: size.height)
            UIGraphicsPushContext(context)
            text.draw(in: rect, withAttributes: attrs)
            UIGraphicsPopContext()

        case .checkbox(let isChecked, _):
            guard let rect = checkboxRect() else { return }
            let path = UIBezierPath(roundedRect: rect, cornerRadius: theme.theme.checkboxCornerRadius)
            if isChecked {
                context.addPath(path.cgPath)
                context.setFillColor(theme.palette.color(.checkboxChecked).cgColor)
                context.fillPath()
                drawCheckmark(in: rect, context: context)
            } else {
                context.addPath(path.cgPath)
                context.setStrokeColor(theme.palette.color(.checkbox).cgColor)
                context.setLineWidth(1.5)
                context.strokePath()
            }
        }
    }

    private func drawCheckmark(in rect: CGRect, context: CGContext) {
        let path = UIBezierPath()
        let start = CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.55)
        let mid = CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.76)
        let end = CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.26)
        path.move(to: start)
        path.addLine(to: mid)
        path.addLine(to: end)
        context.addPath(path.cgPath)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(max(1.2, rect.width * 0.12))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    // MARK: Thematic break

    private func drawThematicBreak(theme: ResolvedTheme, bounds: CGRect, in context: CGContext) {
        let y = bounds.midY
        context.setStrokeColor(theme.palette.color(.quoteRule).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: bounds.width, y: y))
        context.strokePath()
    }
}
#endif
