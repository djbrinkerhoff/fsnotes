import Foundation
import MarkdownEditorCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Platform colors for the semantic roles. Adapters can supply their own palette.
public struct EditorPalette: Sendable {
    public var colors: @Sendable (ThemeColorRole) -> PlatformColor

    public init(colors: @escaping @Sendable (ThemeColorRole) -> PlatformColor) {
        self.colors = colors
    }

    public func color(_ role: ThemeColorRole) -> PlatformColor { colors(role) }

    /// System colors that adapt to light/dark appearance automatically.
    public static let system = EditorPalette { role in
        #if canImport(UIKit)
        switch role {
        case .text: return .label
        case .secondaryText: return .secondaryLabel
        case .syntax: return .tertiaryLabel
        case .link: return .link
        case .tag: return .systemBlue
        case .codeText: return .label
        case .codeBackground: return UIColor.secondarySystemBackground
        case .quoteRule: return UIColor.systemGray3
        case .quoteText: return .secondaryLabel
        case .checkbox: return UIColor.systemGray2
        case .checkboxChecked: return .tintColor
        case .listMarker: return .secondaryLabel
        case .selectionHighlight: return UIColor.systemYellow.withAlphaComponent(0.35)
        }
        #else
        switch role {
        case .text: return .labelColor
        case .secondaryText: return .secondaryLabelColor
        case .syntax: return .tertiaryLabelColor
        case .link: return .linkColor
        case .tag: return .systemBlue
        case .codeText: return .labelColor
        case .codeBackground: return NSColor.textBackgroundColor.blended(withFraction: 0.06, of: .labelColor) ?? .windowBackgroundColor
        case .quoteRule: return .separatorColor
        case .quoteText: return .secondaryLabelColor
        case .checkbox: return .tertiaryLabelColor
        case .checkboxChecked: return .controlAccentColor
        case .listMarker: return .secondaryLabelColor
        case .selectionHighlight: return NSColor.systemYellow.withAlphaComponent(0.35)
        }
        #endif
    }
}

/// `EditorTheme` resolved against a concrete body font and palette.
public struct ResolvedTheme {
    public var theme: EditorTheme
    public var palette: EditorPalette
    public var bodyFont: PlatformFont
    public var codeFont: PlatformFont
    public var bodySize: CGFloat { bodyFont.pointSize }

    public init(theme: EditorTheme = .default, palette: EditorPalette = .system, bodyFont: PlatformFont, codeFont: PlatformFont? = nil) {
        self.theme = theme
        self.palette = palette
        self.bodyFont = bodyFont
        let codeSize = (bodyFont.pointSize * theme.codeFontScale).rounded()
        self.codeFont = codeFont ?? .monospacedSystemFont(ofSize: codeSize, weight: .regular)
    }

    public func headingFont(level: Int) -> PlatformFont {
        let scale = theme.headingScales[max(1, min(6, level))]
        let size = (bodySize * scale).rounded()
        return Self.font(bodyFont, size: size, bold: theme.headingWeightBold)
    }

    public func font(for style: InlineStyle, block: BlockPresentationKind) -> PlatformFont {
        var base: PlatformFont
        switch block {
        case .heading(let level): base = headingFont(level: level)
        case .codeBlock: base = codeFont
        default: base = bodyFont
        }
        if style.contains(.code) { base = Self.font(codeFont, size: block.isHeading ? base.pointSize * theme.codeFontScale : codeFont.pointSize, bold: style.contains(.strong) || block.isHeading, italic: style.contains(.emphasis)) ; return base }
        let bold = style.contains(.strong) || (block.isHeading && theme.headingWeightBold)
        let italic = style.contains(.emphasis)
        if bold || italic { base = Self.font(base, size: base.pointSize, bold: bold, italic: italic) }
        return base
    }

    public func color(for style: InlineStyle, block: BlockPresentationKind, quoteDepth: Int) -> PlatformColor {
        if style.contains(.syntax) { return palette.color(.syntax) }
        if style.contains(.link) || style.contains(.wikiLink) || style.contains(.image) { return palette.color(.link) }
        if style.contains(.tag) { return palette.color(.tag) }
        if style.contains(.code) { return palette.color(.codeText) }
        switch block {
        case .codeBlock: return palette.color(.codeText)
        case .frontMatter, .thematicBreak, .html, .table: return palette.color(.syntax)
        default: return quoteDepth > 0 ? palette.color(.quoteText) : palette.color(.text)
        }
    }

    // MARK: Metrics

    public var listIndentWidth: CGFloat { (bodySize * theme.listIndent).rounded() }
    public var listMarkerGap: CGFloat { (bodySize * theme.listMarkerGap).rounded() }
    public var quoteIndentWidth: CGFloat { (bodySize * theme.quoteIndent).rounded() }
    public var codeBlockPadding: CGFloat { (bodySize * theme.codeBlockPadding).rounded() }
    public var checkboxSize: CGFloat { (bodySize * theme.checkboxSize).rounded() }
    public var paragraphSpacing: CGFloat { (bodySize * theme.paragraphSpacing).rounded() }
    public var headingSpacingBefore: CGFloat { (bodySize * theme.headingSpacingBefore).rounded() }

    // MARK: Font helpers

    static func font(_ base: PlatformFont, size: CGFloat, bold: Bool, italic: Bool = false) -> PlatformFont {
        #if canImport(UIKit)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
        #else
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        #endif
    }
}

public extension BlockPresentationKind {
    var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
    var isCodeBlock: Bool {
        if case .codeBlock = self { return true }
        return false
    }
}
