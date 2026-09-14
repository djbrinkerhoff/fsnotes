import Foundation

/// Custom attributes the adapters attach to display text so layout fragments and hit-testing
/// can find semantic information without consulting the session.
public enum EditorAttributeKey {
    /// `BlockDecoration` describing margin decorations (list marker, checkbox, quote bars, code background) for the paragraph.
    public static let blockDecoration = NSAttributedString.Key("MarkdownEditor.blockDecoration")
    /// `String` destination for links / wiki links / images.
    public static let destination = NSAttributedString.Key("MarkdownEditor.destination")
    /// `NSNumber` (Bool) marking inline code so backgrounds can be drawn.
    public static let inlineCode = NSAttributedString.Key("MarkdownEditor.inlineCode")
    /// `NSNumber` (Bool) marking a tag run so pills can be drawn.
    public static let tag = NSAttributedString.Key("MarkdownEditor.tag")
}

/// Margin decoration for one paragraph. Stored as an attribute value (must be a class for NSAttributedString).
public final class BlockDecoration: NSObject {
    public enum Marker: Equatable {
        case bullet
        case number(Int)
        case checkbox(isChecked: Bool, markerSourceRange: NSRange)
    }

    public let marker: Marker?
    public let listDepth: Int
    public let quoteDepth: Int
    public let isCodeBlock: Bool
    public let isThematicBreak: Bool
    /// X offset (points, from the text container's leading edge) where the marker is drawn.
    public let markerX: CGFloat
    /// Width reserved for the marker.
    public let markerWidth: CGFloat
    /// X offsets of quote bars.
    public let quoteBarXs: [CGFloat]

    public init(marker: Marker?, listDepth: Int, quoteDepth: Int, isCodeBlock: Bool, isThematicBreak: Bool, markerX: CGFloat, markerWidth: CGFloat, quoteBarXs: [CGFloat]) {
        self.marker = marker
        self.listDepth = listDepth
        self.quoteDepth = quoteDepth
        self.isCodeBlock = isCodeBlock
        self.isThematicBreak = isThematicBreak
        self.markerX = markerX
        self.markerWidth = markerWidth
        self.quoteBarXs = quoteBarXs
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BlockDecoration else { return false }
        return marker == other.marker && listDepth == other.listDepth && quoteDepth == other.quoteDepth
            && isCodeBlock == other.isCodeBlock && isThematicBreak == other.isThematicBreak
            && markerX == other.markerX && markerWidth == other.markerWidth && quoteBarXs == other.quoteBarXs
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(listDepth); hasher.combine(quoteDepth); hasher.combine(isCodeBlock); hasher.combine(markerX)
        return hasher.finalize()
    }
}
