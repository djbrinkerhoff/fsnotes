import Foundation

/// Semantic Markdown parser. Implementations must be pure and safe to call off the main actor.
public protocol MarkdownParser: Sendable {
    /// Parses the whole source. Ranges in the result are UTF-16 offsets into `source`.
    func parse(_ source: String) -> MarkdownTree
}

/// Options shared by parser implementations.
public struct MarkdownParserOptions: Sendable, Equatable {
    public var recognizesWikiLinks = true
    public var recognizesTags = true
    public var recognizesStrikethrough = true
    public var recognizesBareURLs = true
    public var recognizesFrontMatter = true

    public init() {}
}
