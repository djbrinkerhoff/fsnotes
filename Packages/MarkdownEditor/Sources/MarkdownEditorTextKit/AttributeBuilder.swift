import Foundation
import MarkdownEditorCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Turns `PresentationLine`s into TextKit attributes. Shared by the UIKit and AppKit adapters.
public struct AttributeBuilder {
    public var theme: ResolvedTheme

    public init(theme: ResolvedTheme) {
        self.theme = theme
    }

    /// Default typing attributes for plain paragraphs.
    public var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: theme.bodyFont, .foregroundColor: theme.palette.color(.text), .paragraphStyle: paragraphStyle(for: BlockPresentation(kind: .paragraph)).style]
    }

    /// Attributes for the whole line, indexed relative to `line.displayRange.location`: returns
    /// paragraph-wide attributes plus per-run overrides.
    public func attributes(for line: PresentationLine) -> (paragraph: [NSAttributedString.Key: Any], runs: [(NSRange, [NSAttributedString.Key: Any])]) {
        let block = line.block
        let (style, decoration) = paragraphStyle(for: block)
        var paragraph: [NSAttributedString.Key: Any] = [
            .font: theme.font(for: [], block: block.kind),
            .foregroundColor: theme.color(for: [], block: block.kind, quoteDepth: block.quoteDepth),
            .paragraphStyle: style,
            EditorAttributeKey.blockDecoration: decoration,
        ]
        if case .task(let isChecked) = block.listMarker ?? .bullet, isChecked, block.listMarker != nil {
            paragraph[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            paragraph[.foregroundColor] = theme.palette.color(.secondaryText)
        }
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        for run in line.runs {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: theme.font(for: run.style, block: block.kind),
                .foregroundColor: theme.color(for: run.style, block: block.kind, quoteDepth: block.quoteDepth),
            ]
            if run.style.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.style.contains(.link) || run.style.contains(.wikiLink) || run.style.contains(.image), let destination = run.destination {
                attrs[EditorAttributeKey.destination] = destination
                if run.style.contains(.link), let url = URL(string: destination) { attrs[.link] = url }
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if run.style.contains(.code), !block.kind.isCodeBlock {
                attrs[EditorAttributeKey.inlineCode] = true
                attrs[.backgroundColor] = theme.palette.color(.codeBackground)
            }
            if run.style.contains(.tag) { attrs[EditorAttributeKey.tag] = true }
            let local = NSRange(location: run.displayRange.location - line.displayRange.location, length: run.displayRange.length)
            runs.append((local, attrs))
        }
        return (paragraph, runs)
    }

    /// Applies attributes for `line` to `storage`, where the line's text is at `line.displayRange`
    /// in the storage (the terminating newline, if any, receives the paragraph attributes too).
    public func apply(_ line: PresentationLine, to storage: NSMutableAttributedString, includeNewline: Bool) {
        let (paragraph, runs) = attributes(for: line)
        var range = line.displayRange
        if includeNewline, NSMaxRange(range) < storage.length { range.length += 1 }
        guard NSMaxRange(range) <= storage.length else { return }
        storage.setAttributes(paragraph, range: range)
        for (local, attrs) in runs {
            let absolute = NSRange(location: line.displayRange.location + local.location, length: local.length)
            guard NSMaxRange(absolute) <= storage.length else { continue }
            storage.addAttributes(attrs, range: absolute)
        }
    }

    /// Builds a fully attributed string for a presentation (initial load / full replacement).
    public func attributedString(for presentation: Presentation) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: presentation.displayText, attributes: baseAttributes)
        result.beginEditing()
        for line in presentation.lines { apply(line, to: result, includeNewline: true) }
        result.endEditing()
        return result
    }

    // MARK: Paragraph styles

    public func paragraphStyle(for block: BlockPresentation) -> (style: NSParagraphStyle, decoration: BlockDecoration) {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.theme.lineHeightMultiple
        style.paragraphSpacing = theme.paragraphSpacing
        style.lineBreakMode = .byWordWrapping

        var indent: CGFloat = 0
        var quoteBarXs: [CGFloat] = []
        for q in 0..<block.quoteDepth {
            quoteBarXs.append(indent + CGFloat(q) * 0)
            indent += theme.quoteIndentWidth
        }
        var markerX: CGFloat = 0
        var markerWidth: CGFloat = 0
        if block.listDepth > 0 {
            let depthIndent = CGFloat(block.listDepth) * theme.listIndentWidth
            markerWidth = theme.listIndentWidth - theme.listMarkerGap
            markerX = indent + depthIndent - theme.listIndentWidth
            indent += depthIndent
        }
        style.firstLineHeadIndent = indent
        style.headIndent = indent

        var marker: BlockDecoration.Marker? = nil
        switch block.listMarker {
        case .bullet: marker = .bullet
        case .number(let n): marker = .number(n)
        case .task(let isChecked): marker = .checkbox(isChecked: isChecked, markerSourceRange: block.taskMarkerSourceRange ?? NSRange(location: 0, length: 0))
        case nil: break
        }

        switch block.kind {
        case .heading:
            style.paragraphSpacingBefore = theme.headingSpacingBefore
            style.paragraphSpacing = theme.paragraphSpacing * 0.6
        case .codeBlock:
            style.firstLineHeadIndent = indent + theme.codeBlockPadding
            style.headIndent = indent + theme.codeBlockPadding
            style.tailIndent = -theme.codeBlockPadding
            style.paragraphSpacing = 0
            style.lineHeightMultiple = 1.15
        case .blank:
            style.paragraphSpacing = 0
        default:
            break
        }
        if block.listDepth > 0 || block.quoteDepth > 0 { style.paragraphSpacing = theme.paragraphSpacing * 0.35 }

        let decoration = BlockDecoration(marker: marker, listDepth: block.listDepth, quoteDepth: block.quoteDepth, isCodeBlock: block.kind.isCodeBlock, isThematicBreak: block.kind == .thematicBreak, markerX: markerX, markerWidth: markerWidth, quoteBarXs: quoteBarXs)
        return (style, decoration)
    }
}
