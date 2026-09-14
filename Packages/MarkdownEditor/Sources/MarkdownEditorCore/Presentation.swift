import Foundation

public enum EditorMode: String, Sendable, Equatable {
    /// Markdown syntax hidden, formatting shown.
    case rich
    /// Raw Markdown shown with syntax colored.
    case source
}

/// Inline styling flags resolved by the platform adapters.
public struct InlineStyle: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let strong = InlineStyle(rawValue: 1 << 0)
    public static let emphasis = InlineStyle(rawValue: 1 << 1)
    public static let code = InlineStyle(rawValue: 1 << 2)
    public static let strikethrough = InlineStyle(rawValue: 1 << 3)
    public static let link = InlineStyle(rawValue: 1 << 4)
    public static let wikiLink = InlineStyle(rawValue: 1 << 5)
    public static let tag = InlineStyle(rawValue: 1 << 6)
    /// Visible Markdown syntax (source mode, fences, unrecognized markers). Rendered dimmed.
    public static let syntax = InlineStyle(rawValue: 1 << 7)
    public static let image = InlineStyle(rawValue: 1 << 8)
}

public struct StyleRun: Sendable, Hashable {
    /// Display range, relative to the whole display text.
    public var displayRange: NSRange
    public var style: InlineStyle
    /// Destination for links, images and wiki links.
    public var destination: String?

    public init(displayRange: NSRange, style: InlineStyle, destination: String? = nil) {
        self.displayRange = displayRange
        self.style = style
        self.destination = destination
    }
}

public enum ListMarker: Sendable, Hashable {
    case bullet
    case number(Int)
    case task(isChecked: Bool)
}

public enum BlockPresentationKind: Sendable, Hashable {
    case paragraph
    case heading(level: Int)
    case codeBlock(isFence: Bool)
    case thematicBreak
    case frontMatter
    case html
    case table
    case blank
}

/// Paragraph-level presentation for one display line.
public struct BlockPresentation: Sendable, Hashable {
    public var kind: BlockPresentationKind
    /// Number of enclosing block quotes.
    public var quoteDepth: Int
    /// Number of enclosing list items (0 = not in a list).
    public var listDepth: Int
    /// Marker drawn in the margin when this line starts a list item.
    public var listMarker: ListMarker?
    /// Source range of the task marker `[ ]`/`[x]` when `listMarker` is a task.
    public var taskMarkerSourceRange: NSRange?

    public init(kind: BlockPresentationKind, quoteDepth: Int = 0, listDepth: Int = 0, listMarker: ListMarker? = nil, taskMarkerSourceRange: NSRange? = nil) {
        self.kind = kind
        self.quoteDepth = quoteDepth
        self.listDepth = listDepth
        self.listMarker = listMarker
        self.taskMarkerSourceRange = taskMarkerSourceRange
    }
}

/// One display line (paragraph in TextKit terms).
public struct PresentationLine: Sendable, Hashable {
    /// Display range excluding the terminating "\n".
    public var displayRange: NSRange
    public var block: BlockPresentation
    public var runs: [StyleRun]

    public init(displayRange: NSRange, block: BlockPresentation, runs: [StyleRun]) {
        self.displayRange = displayRange
        self.block = block
        self.runs = runs
    }

    /// Signature independent of position, used to detect lines whose styling changed.
    public var styleSignature: Int {
        var hasher = Hasher()
        hasher.combine(block)
        hasher.combine(displayRange.length)
        for run in runs {
            hasher.combine(run.displayRange.location - displayRange.location)
            hasher.combine(run.displayRange.length)
            hasher.combine(run.style)
            hasher.combine(run.destination)
        }
        return hasher.finalize()
    }
}

/// Derived, read-only description of what the text view shows.
public struct Presentation: Sendable, Equatable {
    public var displayText: String
    public var map: SourceDisplayMap
    public var lines: [PresentationLine]
    public var mode: EditorMode

    public init(displayText: String, map: SourceDisplayMap, lines: [PresentationLine], mode: EditorMode) {
        self.displayText = displayText
        self.map = map
        self.lines = lines
        self.mode = mode
    }

    public static let empty = Presentation(displayText: "", map: .identity(sourceLength: 0), lines: [PresentationLine(displayRange: NSRange(location: 0, length: 0), block: BlockPresentation(kind: .paragraph), runs: [])], mode: .rich)

    public var displayLength: Int { map.displayLength }

    /// Index of the line containing display offset `offset` (a caret at a line end belongs to that line).
    public func lineIndex(atDisplay offset: Int) -> Int {
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].displayRange.location <= offset { low = mid } else { high = mid - 1 }
        }
        return max(0, low)
    }

    public func line(atDisplay offset: Int) -> PresentationLine {
        lines[lineIndex(atDisplay: offset)]
    }
}

/// Builds a `Presentation` from a parsed tree. Pure; may run off the main actor.
public protocol PresentationBuilding: Sendable {
    func build(source: String, tree: MarkdownTree, mode: EditorMode) -> Presentation
}
