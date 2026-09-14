import Foundation

// All ranges are UTF-16 offsets into the source string the tree was parsed from.

public struct MarkdownTree: Sendable, Equatable {
    public var blocks: [MarkdownBlock]
    /// Lowercased reference label -> destination, from link reference definitions.
    public var linkReferences: [String: String]
    /// Every line of the source, in order, including blank lines. Convenience index for presentation.
    public var lines: [MarkdownLine]

    public init(blocks: [MarkdownBlock], linkReferences: [String: String] = [:], lines: [MarkdownLine] = []) {
        self.blocks = blocks
        self.linkReferences = linkReferences
        self.lines = lines
    }

    public static let empty = MarkdownTree(blocks: [])
}

/// One physical source line.
public struct MarkdownLine: Sendable, Equatable {
    /// Content range excluding the line terminator.
    public var range: NSRange
    /// Terminator range ("\n", "\r\n", "\r" or empty for the last line).
    public var terminator: NSRange

    public init(range: NSRange, terminator: NSRange) {
        self.range = range
        self.terminator = terminator
    }
}

public struct MarkdownTaskState: Sendable, Equatable {
    public var isChecked: Bool
    /// Range of the three characters `[ ]` / `[x]` / `[X]`.
    public var markerRange: NSRange

    public init(isChecked: Bool, markerRange: NSRange) {
        self.isChecked = isChecked
        self.markerRange = markerRange
    }
}

public enum MarkdownBlockKind: Sendable, Equatable {
    case paragraph
    /// ATX heading. `markerRange` covers the leading `#`s plus the following whitespace
    /// (or just the `#`s when the heading is empty). `closingRange` covers optional trailing `#`s and preceding space.
    case heading(level: Int, markerRange: NSRange, closingRange: NSRange?)
    /// Setext heading; `underlineRange` is the whole underline line.
    case setextHeading(level: Int, underlineRange: NSRange)
    case thematicBreak
    /// Fenced code. `contentRange` covers the lines between the fences (may be empty). `closingFence` is nil when unterminated.
    case fencedCode(info: String, openingFence: NSRange, closingFence: NSRange?, contentRange: NSRange)
    case indentedCode
    /// Block quote. `markerRanges` has one entry per line: the `>` plus one optional following space.
    case blockquote(markerRanges: [NSRange])
    case list(ordered: Bool, start: Int, tight: Bool)
    /// List item. `markerRange` covers the bullet or number plus the following whitespace
    /// (and, for tasks, also the task marker plus one following space when present).
    /// `depth` is 0 for a top-level list.
    case listItem(markerRange: NSRange, ordinal: Int?, task: MarkdownTaskState?, depth: Int)
    case htmlBlock
    case table
    /// YAML front matter delimited by `---` lines at the very start of the document.
    case frontMatter
    case linkReferenceDefinition(label: String, destination: String)
    case blank
}

public struct MarkdownBlock: Sendable, Equatable {
    public var kind: MarkdownBlockKind
    /// Source range covering all of the block's lines, excluding the final line terminator.
    public var range: NSRange
    /// Children for container blocks (list, listItem, blockquote).
    public var children: [MarkdownBlock]
    /// Inline content for leaf text blocks (paragraph, heading, setextHeading, table cells are not parsed).
    public var inlines: [MarkdownInline]

    public init(kind: MarkdownBlockKind, range: NSRange, children: [MarkdownBlock] = [], inlines: [MarkdownInline] = []) {
        self.kind = kind
        self.range = range
        self.children = children
        self.inlines = inlines
    }

    public var isContainer: Bool {
        switch kind {
        case .list, .listItem, .blockquote: return true
        default: return false
        }
    }
}

public enum MarkdownInlineKind: Sendable, Equatable {
    case text
    case softBreak
    /// Hard break: `markerRange` covers the trailing backslash or the two-plus trailing spaces.
    case hardBreak(markerRange: NSRange)
    case emphasis(open: NSRange, close: NSRange)
    case strong(open: NSRange, close: NSRange)
    case strikethrough(open: NSRange, close: NSRange)
    /// Code span. `open`/`close` cover the backtick runs plus one optional padding space each.
    case code(open: NSRange, close: NSRange)
    /// Inline or reference link. `open` is `[`, `close` is `](destination "title")` or `][label]` / `]`.
    case link(destination: String, open: NSRange, close: NSRange)
    /// Image. `open` is `![`, `close` as for links. Children hold the alt text.
    case image(destination: String, open: NSRange, close: NSRange)
    /// `<https://…>` autolink: `open`/`close` cover the angle brackets.
    case autolink(destination: String, open: NSRange, close: NSRange)
    /// Bare `https://…` URL detected as a link (GFM autolink extension).
    case bareURL(destination: String)
    /// `[[Target]]` wiki link: `open`/`close` cover the double brackets.
    case wikiLink(target: String, open: NSRange, close: NSRange)
    /// `#tag` inline tag (FSNotes convention). Range covers `#` plus name.
    case tag(name: String)
    /// Backslash escape. `backslashRange` covers the `\`; the node range covers backslash plus the escaped character.
    case escape(backslashRange: NSRange)
    case htmlInline
}

public struct MarkdownInline: Sendable, Equatable {
    public var kind: MarkdownInlineKind
    /// Full source range including delimiters.
    public var range: NSRange
    public var children: [MarkdownInline]

    public init(kind: MarkdownInlineKind, range: NSRange, children: [MarkdownInline] = []) {
        self.kind = kind
        self.range = range
        self.children = children
    }
}

public extension MarkdownTree {
    /// Depth-first visit of every block, containers before their children.
    func forEachBlock(_ body: (MarkdownBlock, _ parents: [MarkdownBlock]) -> Void) {
        func visit(_ block: MarkdownBlock, _ parents: [MarkdownBlock]) {
            body(block, parents)
            for child in block.children { visit(child, parents + [block]) }
        }
        for block in blocks { visit(block, []) }
    }

    /// Innermost block chain (outermost first) containing `offset`.
    func blockPath(at offset: Int) -> [MarkdownBlock] {
        var path: [MarkdownBlock] = []
        var candidates = blocks
        while let block = candidates.first(where: { offset >= $0.range.location && offset <= NSMaxRange($0.range) }) {
            path.append(block)
            candidates = block.children
        }
        return path
    }
}
