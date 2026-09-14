import Foundation

/// Semantic color roles resolved to platform colors by adapters.
public enum ThemeColorRole: Sendable, Hashable {
    case text
    case secondaryText
    case syntax
    case link
    case tag
    case codeText
    case codeBackground
    case quoteRule
    case quoteText
    case checkbox
    case checkboxChecked
    case listMarker
    case selectionHighlight
}

/// Platform-independent typography and spacing. Point values are multiplied by the
/// platform body size where noted, so Dynamic Type scales everything.
public struct EditorTheme: Sendable, Equatable {
    /// Heading font scale factors indexed by level 1…6 (index 0 unused).
    public var headingScales: [Double] = [1, 1.9, 1.55, 1.3, 1.15, 1.05, 1.0]
    public var headingWeightBold: Bool = true
    public var lineHeightMultiple: Double = 1.25
    public var paragraphSpacing: Double = 0.55        // × body size
    public var headingSpacingBefore: Double = 0.9     // × body size
    public var listIndent: Double = 1.6               // × body size per depth
    public var listMarkerGap: Double = 0.45           // × body size between marker and text
    public var quoteIndent: Double = 1.1              // × body size
    public var quoteRuleWidth: Double = 3
    public var codeBlockPadding: Double = 0.6         // × body size
    public var codeCornerRadius: Double = 6
    public var codeFontScale: Double = 0.92
    public var checkboxSize: Double = 1.05            // × body size
    public var checkboxCornerRadius: Double = 4
    public var textInsetHorizontal: Double = 20
    public var textInsetVertical: Double = 24
    public var maxContentWidth: Double? = 720

    public init() {}

    public static let `default` = EditorTheme()
}
