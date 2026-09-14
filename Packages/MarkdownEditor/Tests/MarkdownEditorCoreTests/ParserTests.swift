import XCTest
@testable import MarkdownEditorCore

final class ParserTests: XCTestCase {

    // MARK: - Helpers

    func sub(_ source: String, _ range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }

    func parse(_ source: String, options: MarkdownParserOptions = MarkdownParserOptions()) -> MarkdownTree {
        CommonMarkLineParser(options: options).parse(source)
    }

    /// For wrapping inline kinds, children tile the span strictly between the open and close
    /// delimiters (not the node's full range, which includes those delimiters). Kinds without
    /// this property (plain text, tags, autolinks, wiki links whose child is a partial excerpt,
    /// etc.) return nil and are not recursed into.
    func innerTilingRange(_ kind: MarkdownInlineKind) -> NSRange? {
        switch kind {
        case .emphasis(let open, let close), .strong(let open, let close),
             .strikethrough(let open, let close), .code(let open, let close):
            return NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
        case .link(_, let open, let close), .image(_, let open, let close):
            return NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open))
        default:
            return nil
        }
    }

    /// Recursively asserts that `children` are contiguous and tile `parentRange`, skipping any
    /// `excluded` boundary ranges (e.g. blockquote markers on continuation lines).
    func assertInlinesTile(_ children: [MarkdownInline], parentRange: NSRange, excluded: [NSRange] = [], file: StaticString = #filePath, line: UInt = #line) {
        var cursor = parentRange.location
        let end = NSMaxRange(parentRange)
        func skipExcluded() {
            while let ex = excluded.first(where: { $0.location == cursor }) { cursor = NSMaxRange(ex) }
        }
        skipExcluded()
        for child in children {
            XCTAssertEqual(child.range.location, cursor, "gap or overlap before child \(child.kind)", file: file, line: line)
            cursor = NSMaxRange(child.range)
            skipExcluded()
            if let inner = innerTilingRange(child.kind) {
                assertInlinesTile(child.children, parentRange: inner, excluded: excluded, file: file, line: line)
            }
        }
        XCTAssertEqual(cursor, end, "children do not tile through end of parent range", file: file, line: line)
    }

    /// Runs the tiling invariant over every block in the tree that carries inlines.
    func assertTreeTiles(_ tree: MarkdownTree, file: StaticString = #filePath, line: UInt = #line) {
        tree.forEachBlock { block, parents in
            // Inlines only tile the *content* sub-range of the block: for a heading that
            // excludes the leading `#` marker (and any trailing closing hashes), and for a
            // setext heading it excludes the underline line entirely. Only `.paragraph`'s
            // `range` is exactly its inline content range.
            var contentRange: NSRange
            switch block.kind {
            case .paragraph:
                contentRange = block.range
            case .heading(_, let markerRange, let closingRange):
                let lo = NSMaxRange(markerRange)
                let hi = closingRange?.location ?? NSMaxRange(block.range)
                contentRange = NSRange(location: lo, length: hi - lo)
            case .setextHeading(_, let underlineRange):
                // The text spans from the block start up through the end of the line
                // immediately preceding the underline (found by terminator adjacency).
                guard let textEndLine = tree.lines.first(where: { NSMaxRange($0.terminator) == underlineRange.location }) else {
                    return
                }
                contentRange = NSRange(location: block.range.location, length: NSMaxRange(textEndLine.range) - block.range.location)
            default:
                return
            }
            var excluded: [NSRange] = []
            for parent in parents {
                if case .blockquote(let markerRanges) = parent.kind {
                    excluded.append(contentsOf: markerRanges)
                }
            }
            excluded = excluded.filter { $0.location >= contentRange.location && NSMaxRange($0) <= NSMaxRange(contentRange) }
            assertInlinesTile(block.inlines, parentRange: contentRange, excluded: excluded, file: file, line: line)
        }
    }

    func firstBlock(_ tree: MarkdownTree) -> MarkdownBlock { tree.blocks[0] }

    // MARK: - Empty document / line splitting

    func testEmptyDocument() {
        let tree = parse("")
        XCTAssertEqual(tree.lines.count, 1)
        XCTAssertEqual(tree.lines[0].range, NSRange(location: 0, length: 0))
        XCTAssertEqual(tree.lines[0].terminator, NSRange(location: 0, length: 0))
        XCTAssertEqual(tree.blocks.count, 1)
        if case .blank = tree.blocks[0].kind {} else { XCTFail("expected blank block") }
    }

    func testLineSplittingLF() {
        let src = "a\nb\nc"
        let lines = CommonMarkLineParser.splitLines(Array(src.utf16))
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(sub(src, lines[0].range), "a")
        XCTAssertEqual(sub(src, lines[0].terminator), "\n")
        XCTAssertEqual(sub(src, lines[2].range), "c")
        XCTAssertEqual(lines[2].terminator.length, 0)
    }

    func testLineSplittingCRLF() {
        let src = "a\r\nb\r\n"
        let lines = CommonMarkLineParser.splitLines(Array(src.utf16))
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(sub(src, lines[0].terminator), "\r\n")
        XCTAssertEqual(sub(src, lines[1].terminator), "\r\n")
        XCTAssertEqual(lines[2].range, NSRange(location: 6, length: 0))
    }

    func testLineSplittingCR() {
        let src = "a\rb\rc"
        let lines = CommonMarkLineParser.splitLines(Array(src.utf16))
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(sub(src, lines[0].terminator), "\r")
    }

    func testLineSplittingMixed() {
        let src = "a\nb\r\nc\rd"
        let lines = CommonMarkLineParser.splitLines(Array(src.utf16))
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(sub(src, lines[0].range), "a")
        XCTAssertEqual(sub(src, lines[1].range), "b")
        XCTAssertEqual(sub(src, lines[2].range), "c")
        XCTAssertEqual(sub(src, lines[3].range), "d")
    }

    func testTrailingTerminatorYieldsFinalEmptyLine() {
        let src = "abc\n"
        let lines = CommonMarkLineParser.splitLines(Array(src.utf16))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1].range, NSRange(location: 4, length: 0))
    }

    // MARK: - Headings

    func testATXHeadingsAllLevels() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let src = "\(hashes) Title"
            let tree = parse(src)
            guard case .heading(let l, let markerRange, let closingRange) = firstBlock(tree).kind else {
                return XCTFail("expected heading at level \(level)")
            }
            XCTAssertEqual(l, level)
            XCTAssertEqual(sub(src, markerRange), "\(hashes) ")
            XCTAssertNil(closingRange)
            XCTAssertEqual(sub(src, firstBlock(tree).range), src)
        }
    }

    func testEmptyHeadingIsValid() {
        let src = "# "
        let tree = parse(src)
        guard case .heading(let level, let markerRange, _) = firstBlock(tree).kind else {
            return XCTFail("expected heading")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(markerRange, NSRange(location: 0, length: 2))
        XCTAssertEqual(firstBlock(tree).inlines.count, 0)
    }

    func testHashWithNoSpaceIsParagraph() {
        let tree = parse("#nospace")
        guard case .paragraph = firstBlock(tree).kind else { return XCTFail("expected paragraph") }
    }

    func testHeadingClosingHashes() {
        let src = "## Title ##"
        let tree = parse(src)
        guard case .heading(let level, let markerRange, let closingRange) = firstBlock(tree).kind else {
            return XCTFail("expected heading")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(sub(src, markerRange), "## ")
        XCTAssertNotNil(closingRange)
        XCTAssertEqual(sub(src, closingRange!), " ##")
    }

    // MARK: - Setext / thematic break

    func testSetextHeadings() {
        let src1 = "Title\n====="
        let t1 = parse(src1)
        guard case .setextHeading(let level1, let underline1) = firstBlock(t1).kind else { return XCTFail() }
        XCTAssertEqual(level1, 1)
        XCTAssertEqual(sub(src1, underline1), "=====")

        let src2 = "Title\n-----"
        let t2 = parse(src2)
        guard case .setextHeading(let level2, _) = firstBlock(t2).kind else { return XCTFail() }
        XCTAssertEqual(level2, 2)
    }

    func testThematicBreakPrecedesSetextWhenNoParagraph() {
        let tree = parse("---")
        guard case .thematicBreak = firstBlock(tree).kind else { return XCTFail("expected thematic break") }
    }

    func testThematicBreakOverListBullet() {
        let tree = parse("- - -")
        guard case .thematicBreak = firstBlock(tree).kind else { return XCTFail("expected thematic break, not a list") }
    }

    func testVariousThematicBreaks() {
        for src in ["***", "___", "- - -", "* * *", "_ _ _", "----------"] {
            let tree = parse(src)
            guard case .thematicBreak = firstBlock(tree).kind else { return XCTFail("expected thematic break for \(src)") }
        }
    }

    // MARK: - Fenced code

    func testFencedCodeClosed() {
        let src = "```swift\nlet x = 1\n```"
        let tree = parse(src)
        guard case .fencedCode(let info, let opening, let closing, let content) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertEqual(info, "swift")
        XCTAssertEqual(sub(src, opening), "```")
        XCTAssertNotNil(closing)
        XCTAssertEqual(sub(src, closing!), "```")
        XCTAssertEqual(sub(src, content), "let x = 1")
        XCTAssertTrue(firstBlock(tree).inlines.isEmpty, "fenced code content must not be parsed as inline")
    }

    func testFencedCodeUnterminated() {
        let src = "```\nabc\ndef"
        let tree = parse(src)
        guard case .fencedCode(_, _, let closing, let content) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertNil(closing)
        XCTAssertEqual(sub(src, content), "abc\ndef")
    }

    func testFencedCodeTildes() {
        let src = "~~~\ncode\n~~~"
        let tree = parse(src)
        guard case .fencedCode(_, let opening, let closing, _) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertEqual(sub(src, opening), "~~~")
        XCTAssertNotNil(closing)
    }

    func testFencedCodeLongerClosingFence() {
        let src = "```\ncode\n`````"
        let tree = parse(src)
        guard case .fencedCode(_, _, let closing, let content) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertNotNil(closing)
        XCTAssertEqual(sub(src, content), "code")
    }

    func testFencedCodeContentNotParsedAsInline() {
        let src = "```\n*not emphasis*\n```"
        let tree = parse(src)
        XCTAssertTrue(firstBlock(tree).inlines.isEmpty)
    }

    // MARK: - Indented code

    func testIndentedCode() {
        let src = "    code line one\n    code line two"
        let tree = parse(src)
        guard case .indentedCode = firstBlock(tree).kind else { return XCTFail("expected indented code") }
        XCTAssertEqual(sub(src, firstBlock(tree).range), src)
    }

    func testIndentedCodeWithTab() {
        let src = "\tcode"
        let tree = parse(src)
        guard case .indentedCode = firstBlock(tree).kind else { return XCTFail("expected indented code from tab") }
    }

    // MARK: - Block quotes

    func testBlockquoteMarkerRanges() {
        let src = "> line one\n> line two"
        let tree = parse(src)
        guard case .blockquote(let markerRanges) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertEqual(markerRanges.count, 2)
        XCTAssertEqual(sub(src, markerRanges[0]), "> ")
        XCTAssertEqual(sub(src, markerRanges[1]), "> ")
        XCTAssertEqual(firstBlock(tree).children.count, 1)
        guard case .paragraph = firstBlock(tree).children[0].kind else { return XCTFail("expected paragraph inside quote") }
    }

    func testNestedBlockquotes() {
        let src = "> > nested"
        let tree = parse(src)
        guard case .blockquote(let outerMarkers) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertEqual(sub(src, outerMarkers[0]), "> ")
        let inner = firstBlock(tree).children[0]
        guard case .blockquote(let innerMarkers) = inner.kind else { return XCTFail("expected nested blockquote") }
        XCTAssertEqual(sub(src, innerMarkers[0]), "> ")
    }

    func testBlockquoteLazyContinuation() {
        let src = "> paragraph text\nlazy continuation"
        let tree = parse(src)
        guard case .blockquote(let markerRanges) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertEqual(markerRanges.count, 1, "lazy continuation line must not add a marker range")
        XCTAssertEqual(firstBlock(tree).children.count, 1)
        let para = firstBlock(tree).children[0]
        guard case .paragraph = para.kind else { return XCTFail() }
        XCTAssertEqual(sub(src, para.range), "paragraph text\nlazy continuation")
    }

    // MARK: - Lists

    func testBulletList() {
        let src = "- a\n- b\n- c"
        let tree = parse(src)
        guard case .list(let ordered, _, let tight) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertFalse(ordered)
        XCTAssertTrue(tight)
        XCTAssertEqual(firstBlock(tree).children.count, 3)
        for item in firstBlock(tree).children {
            guard case .listItem(let markerRange, let ordinal, let task, let depth) = item.kind else { return XCTFail() }
            XCTAssertEqual(sub(src, markerRange), "- ")
            XCTAssertNil(ordinal)
            XCTAssertNil(task)
            XCTAssertEqual(depth, 0)
        }
    }

    func testOrderedListStart() {
        let src = "3. first\n4. second"
        let tree = parse(src)
        guard case .list(let ordered, let start, _) = firstBlock(tree).kind else { return XCTFail() }
        XCTAssertTrue(ordered)
        XCTAssertEqual(start, 3)
        guard case .listItem(_, let ordinal0, _, _) = firstBlock(tree).children[0].kind else { return XCTFail() }
        XCTAssertEqual(ordinal0, 3)
    }

    func testNestedListDepth() {
        let src = "- top\n  - nested\n    - deeper"
        let tree = parse(src)
        guard case .listItem(_, _, _, let depth0) = firstBlock(tree).children[0].kind else { return XCTFail() }
        XCTAssertEqual(depth0, 0)
        let topItem = firstBlock(tree).children[0]
        // top item's children: paragraph "top", then a nested list
        guard let nestedList = topItem.children.first(where: { if case .list = $0.kind { return true }; return false }) else {
            return XCTFail("expected nested list inside top item")
        }
        guard case .listItem(_, _, _, let depth1) = nestedList.children[0].kind else { return XCTFail() }
        XCTAssertEqual(depth1, 1)
        let nestedItem = nestedList.children[0]
        guard let deeperList = nestedItem.children.first(where: { if case .list = $0.kind { return true }; return false }) else {
            return XCTFail("expected doubly-nested list")
        }
        guard case .listItem(_, _, _, let depth2) = deeperList.children[0].kind else { return XCTFail() }
        XCTAssertEqual(depth2, 2)
    }

    func testTaskListItemMarkerRanges() {
        let src = "- [ ] todo\n- [x] done"
        let tree = parse(src)
        let item0 = firstBlock(tree).children[0]
        guard case .listItem(let markerRange0, _, let task0, _) = item0.kind else { return XCTFail() }
        XCTAssertEqual(sub(src, markerRange0), "- [ ] ")
        XCTAssertNotNil(task0)
        XCTAssertFalse(task0!.isChecked)
        XCTAssertEqual(sub(src, task0!.markerRange), "[ ]")

        let item1 = firstBlock(tree).children[1]
        guard case .listItem(_, _, let task1, _) = item1.kind else { return XCTFail() }
        XCTAssertNotNil(task1)
        XCTAssertTrue(task1!.isChecked)
        XCTAssertEqual(sub(src, task1!.markerRange), "[x]")
    }

    func testEmptyListItem() {
        let src = "-"
        let tree = parse(src)
        guard case .listItem(_, _, _, _) = firstBlock(tree).children[0].kind else { return XCTFail() }
        XCTAssertEqual(firstBlock(tree).children[0].children.count, 0)
    }

    func testEmptyListItemWithSpace() {
        let src = "- \n- b"
        let tree = parse(src)
        XCTAssertEqual(firstBlock(tree).children.count, 2)
        XCTAssertEqual(firstBlock(tree).children[0].children.count, 0)
    }

    // MARK: - Front matter

    func testFrontMatter() {
        let src = "---\ntitle: Hi\n---\nBody"
        let tree = parse(src)
        guard case .frontMatter = firstBlock(tree).kind else { return XCTFail("expected front matter") }
        XCTAssertEqual(sub(src, firstBlock(tree).range), "---\ntitle: Hi\n---")
        guard case .paragraph = tree.blocks[1].kind else { return XCTFail("expected paragraph after front matter") }
    }

    func testFrontMatterNotFirstLineIsNotRecognized() {
        let src = "text\n---\nmore"
        let tree = parse(src)
        // "text" paragraph is interrupted by setext '---' (level 2 heading) since a paragraph precedes it.
        guard case .setextHeading = firstBlock(tree).kind else { return XCTFail() }
    }

    // MARK: - Reference links / definitions

    func testLinkReferenceDefinitionAndReferenceLink() {
        let src = "[foo]: /url \"title\"\n\nSee [foo]."
        let tree = parse(src)
        XCTAssertEqual(tree.linkReferences["foo"], "/url")
        guard case .linkReferenceDefinition(let label, let dest) = tree.blocks[0].kind else { return XCTFail() }
        XCTAssertEqual(label, "foo")
        XCTAssertEqual(dest, "/url")
        let para = tree.blocks[2]
        guard case .paragraph = para.kind else { return XCTFail() }
        guard let link = para.inlines.first(where: { if case .link = $0.kind { return true }; return false }) else {
            return XCTFail("expected shortcut reference link")
        }
        guard case .link(let dest2, _, _) = link.kind else { return XCTFail() }
        XCTAssertEqual(dest2, "/url")
    }

    func testCollapsedReferenceLink() {
        let src = "[foo]: /url\n\n[foo][]"
        let tree = parse(src)
        let para = tree.blocks[2]
        guard let link = para.inlines.first(where: { if case .link = $0.kind { return true }; return false }) else {
            return XCTFail("expected collapsed reference link")
        }
        guard case .link(let dest, _, _) = link.kind else { return XCTFail() }
        XCTAssertEqual(dest, "/url")
    }

    func testFullReferenceLink() {
        let src = "[bar]: /other\n\n[text][bar]"
        let tree = parse(src)
        let para = tree.blocks[2]
        guard let link = para.inlines.first(where: { if case .link = $0.kind { return true }; return false }) else {
            return XCTFail("expected reference link")
        }
        guard case .link(let dest, _, _) = link.kind else { return XCTFail() }
        XCTAssertEqual(dest, "/other")
    }

    // MARK: - Tables

    func testTable() {
        let src = "| a | b |\n| --- | :---: |\n| 1 | 2 |"
        let tree = parse(src)
        guard case .table = firstBlock(tree).kind else { return XCTFail("expected table") }
        XCTAssertEqual(sub(src, firstBlock(tree).range), src)
    }

    // MARK: - HTML block

    func testHTMLBlock() {
        let src = "<div>\n<p>hi</p>\n</div>\n\nAfter"
        let tree = parse(src)
        guard case .htmlBlock = firstBlock(tree).kind else { return XCTFail("expected html block") }
        XCTAssertEqual(sub(src, firstBlock(tree).range), "<div>\n<p>hi</p>\n</div>")
        guard case .blank = tree.blocks[1].kind else { return XCTFail() }
        guard case .paragraph = tree.blocks[2].kind else { return XCTFail() }
    }

    // MARK: - Emphasis matrix

    func inlineKinds(_ tree: MarkdownTree) -> [MarkdownInline] { firstBlock(tree).inlines }

    func testSimpleEmphasis() {
        let tree = parse("*a*")
        guard case .emphasis(let open, let close) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(open, NSRange(location: 0, length: 1))
        XCTAssertEqual(close, NSRange(location: 2, length: 1))
    }

    func testSimpleStrong() {
        let tree = parse("**a**")
        guard case .strong = inlineKinds(tree)[0].kind else { return XCTFail("expected strong") }
    }

    func testStrongEmphasis() {
        // Per CommonMark, "***a***" nests as <em><strong>a</strong></em>: the single leftover
        // delimiter (after two are consumed for strong) wraps last, becoming the outer node.
        let tree = parse("***a***")
        guard case .emphasis(_, _) = inlineKinds(tree)[0].kind else { return XCTFail("expected outer emphasis") }
        let outerChildren = inlineKinds(tree)[0].children
        XCTAssertTrue(outerChildren.contains { if case .strong = $0.kind { return true }; return false })
    }

    func testUnderscoreEmphasis() {
        let tree = parse("_a_")
        guard case .emphasis = inlineKinds(tree)[0].kind else { return XCTFail() }
    }

    func testSnakeCaseWordIsNotEmphasis() {
        let tree = parse("snake_case_word")
        XCTAssertFalse(inlineKinds(tree).contains { if case .emphasis = $0.kind { return true }; return false })
        XCTAssertEqual(inlineKinds(tree).count, 1)
        guard case .text = inlineKinds(tree)[0].kind else { return XCTFail() }
    }

    func testNestedEmphasisInStrong() {
        let src = "**a *b* c**"
        let tree = parse(src)
        guard case .strong = inlineKinds(tree)[0].kind else { return XCTFail("expected outer strong") }
        let strongChildren = inlineKinds(tree)[0].children
        XCTAssertTrue(strongChildren.contains { if case .emphasis = $0.kind { return true }; return false })
    }

    func testUnmatchedEmphasisIsText() {
        let tree = parse("*a")
        for node in inlineKinds(tree) {
            if case .emphasis = node.kind { XCTFail("should not form emphasis") }
        }
    }

    func testAsteriskSpaceIsListNotEmphasis() {
        let tree = parse("* a")
        guard case .list = firstBlock(tree).kind else { return XCTFail("expected list") }
    }

    // MARK: - Code spans / strikethrough

    func testCodeSpanWithPadding() {
        let src = "` foo `"
        let tree = parse(src)
        guard case .code(let open, let close) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(sub(src, open), "` ")
        XCTAssertEqual(sub(src, close), " `")
        XCTAssertEqual(sub(src, inlineKinds(tree)[0].children[0].range), "foo")
    }

    func testCodeSpanWithoutPadding() {
        let src = "`foo`"
        let tree = parse(src)
        guard case .code(let open, let close) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(sub(src, open), "`")
        XCTAssertEqual(sub(src, close), "`")
    }

    func testStrikethrough() {
        let tree = parse("~~gone~~")
        guard case .strikethrough = inlineKinds(tree)[0].kind else { return XCTFail() }
    }

    // MARK: - Links / images / autolinks

    func testInlineLink() {
        let src = "[text](http://example.com \"title\")"
        let tree = parse(src)
        guard case .link(let dest, let open, let close) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(dest, "http://example.com")
        XCTAssertEqual(sub(src, open), "[")
        XCTAssertEqual(sub(src, close), "](http://example.com \"title\")")
    }

    func testInlineLinkWithAngleDestination() {
        let src = "[text](<http://example.com>)"
        let tree = parse(src)
        guard case .link(let dest, _, _) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(dest, "http://example.com")
    }

    func testImage() {
        let src = "![alt](http://example.com/x.png)"
        let tree = parse(src)
        guard case .image(let dest, let open, _) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(dest, "http://example.com/x.png")
        XCTAssertEqual(sub(src, open), "![")
    }

    func testAutolinkURI() {
        let src = "<https://example.com>"
        let tree = parse(src)
        guard case .autolink(let dest, let open, let close) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(dest, "https://example.com")
        XCTAssertEqual(sub(src, open), "<")
        XCTAssertEqual(sub(src, close), ">")
    }

    func testAutolinkEmail() {
        let tree = parse("<foo@example.com>")
        guard case .autolink(let dest, _, _) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(dest, "mailto:foo@example.com")
    }

    func testBareURLWithTrailingPunctuation() {
        let src = "Visit https://example.com/path, now."
        let tree = parse(src)
        guard let bare = inlineKinds(tree).first(where: { if case .bareURL = $0.kind { return true }; return false }) else {
            return XCTFail("expected bare URL")
        }
        guard case .bareURL(let dest) = bare.kind else { return XCTFail() }
        XCTAssertEqual(dest, "https://example.com/path")
    }

    // MARK: - Wiki links / tags / escapes / breaks

    func testWikiLinkWithAlias() {
        let src = "[[Target Page|Alias]]"
        let tree = parse(src)
        guard case .wikiLink(let target, let open, let close) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(target, "Target Page")
        XCTAssertEqual(sub(src, open), "[[")
        XCTAssertEqual(sub(src, close), "]]")
        XCTAssertEqual(sub(src, inlineKinds(tree)[0].children[0].range), "Alias")
    }

    func testTag() {
        let tree = parse("#tag here")
        guard case .tag(let name) = inlineKinds(tree)[0].kind else { return XCTFail() }
        XCTAssertEqual(name, "tag")
    }

    func testMidWordHashIsNotTag() {
        let tree = parse("a#b")
        XCTAssertFalse(inlineKinds(tree).contains { if case .tag = $0.kind { return true }; return false })
    }

    func testHashDigitIsNotTag() {
        let tree = parse("#1 not a tag")
        XCTAssertFalse(inlineKinds(tree).contains { if case .tag = $0.kind { return true }; return false })
    }

    func testBackslashEscape() {
        let src = "\\*not emphasis\\*"
        let tree = parse(src)
        guard let esc = inlineKinds(tree).first(where: { if case .escape = $0.kind { return true }; return false }) else {
            return XCTFail("expected an escape node")
        }
        XCTAssertEqual(sub(src, esc.range), "\\*")
    }

    func testHardBreakViaSpaces() {
        let src = "line one  \nline two"
        let tree = parse(src)
        guard let hb = inlineKinds(tree).first(where: { if case .hardBreak = $0.kind { return true }; return false }) else {
            return XCTFail("expected hard break")
        }
        guard case .hardBreak(let markerRange) = hb.kind else { return XCTFail() }
        XCTAssertEqual(sub(src, markerRange), "  ")
    }

    func testHardBreakViaBackslash() {
        let src = "line one\\\nline two"
        let tree = parse(src)
        guard let hb = inlineKinds(tree).first(where: { if case .hardBreak = $0.kind { return true }; return false }) else {
            return XCTFail("expected hard break")
        }
        guard case .hardBreak(let markerRange) = hb.kind else { return XCTFail() }
        XCTAssertEqual(sub(src, markerRange), "\\")
    }

    func testSoftBreak() {
        let tree = parse("line one\nline two")
        XCTAssertTrue(inlineKinds(tree).contains { if case .softBreak = $0.kind { return true }; return false })
    }

    // MARK: - Tiling invariant fixtures

    func testTilingInvariantAcrossFixtures() {
        let fixtures = [
            "simple paragraph",
            "# Heading with *em* and **strong**",
            "> quoted *text*\n> continues here",
            "> quoted\nlazy continuation with *em*",
            "- item one\n- item two with `code`",
            "line **bold *and em* end**",
            "[link](dest) and plain text after",
            "prefix #tag and https://example.com suffix",
            "",
            "a\\*b `c` ~~d~~ _e_ [[f]]",
        ]
        for fixture in fixtures {
            let tree = parse(fixture)
            assertTreeTiles(tree)
        }
    }

    func testTilingInvariantInsideBlockquote() {
        let tree = parse("> **bold *em* text**\n> more *text* here")
        assertTreeTiles(tree)
    }

    // MARK: - UTF-16 offset correctness

    func testUTF16OffsetsWithEmoji() {
        let src = "👍🏽 *em*"
        let tree = parse(src)
        // 👍🏽 is a base emoji (2 UTF-16 units) + skin tone modifier (2 UTF-16 units) = 4 units, then a space.
        let emphasisNode = inlineKinds(tree).first { if case .emphasis = $0.kind { return true }; return false }
        XCTAssertNotNil(emphasisNode)
        XCTAssertEqual(emphasisNode!.range.location, 5)
        assertTreeTiles(tree)
    }

    func testUTF16OffsetsWithCombiningMark() {
        let base = "e"
        let combining = "\u{0301}" // combining acute accent
        let src = "\(base)\(combining) *em*"
        let tree = parse(src)
        let emphasisNode = inlineKinds(tree).first { if case .emphasis = $0.kind { return true }; return false }
        XCTAssertNotNil(emphasisNode)
        XCTAssertEqual(emphasisNode!.range.location, 3) // "e" + combining mark + space = 3 UTF-16 units
        assertTreeTiles(tree)
    }

    func testUTF16OffsetsWithCJK() {
        let src = "你好 *强调*"
        let tree = parse(src)
        let emphasisNode = inlineKinds(tree).first { if case .emphasis = $0.kind { return true }; return false }
        XCTAssertNotNil(emphasisNode)
        XCTAssertEqual(emphasisNode!.range.location, 3) // 2 CJK chars + space
        assertTreeTiles(tree)
    }

    func testTabIndentation() {
        let src = "\tindented code"
        let tree = parse(src)
        guard case .indentedCode = firstBlock(tree).kind else { return XCTFail("tab should count as indented code") }
    }

    // MARK: - Performance

    func testPerformanceOneMegabyteMixedDocument() {
        var lines: [String] = []
        var approxSize = 0
        var i = 0
        while approxSize < 1_000_000 {
            switch i % 7 {
            case 0: lines.append("# Heading \(i)")
            case 1: lines.append("This is a paragraph with *emphasis*, **strong**, `code`, and a [link](https://example.com/\(i)).")
            case 2: lines.append("- list item \(i)")
            case 3: lines.append("> quoted line \(i) with *em*")
            case 4: lines.append("")
            case 5: lines.append("    indented code line \(i)")
            default: lines.append("Plain text line number \(i) with some words to pad it out a bit further.")
            }
            approxSize += lines.last!.utf8.count + 1
            i += 1
        }
        let source = lines.joined(separator: "\n")
        let clock = ContinuousClock()
        let start = clock.now
        let tree = parse(source)
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("BENCH ParserTests 1MB mixed document parse: \(ms) ms, lines=\(tree.lines.count), blocks=\(tree.blocks.count)")
        XCTAssertLessThan(ms, 500, "1MB parse should stay well under 500ms even in debug")
    }
}
