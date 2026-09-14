import XCTest
@testable import MarkdownEditorCore

/// Exercises `PresentationBuilder` against hand-built `MarkdownTree` values (no parser
/// dependency). Every source string's UTF-16 offsets are computed and commented explicitly.
final class PresentationBuilderTests: XCTestCase {
    let builder = PresentationBuilder()

    // MARK: - Fixture 1: "# Title\n\nBody **bold** and *it* `code`"

    /// Indices: "# Title\n\nBody **bold** and *it* `code`"
    /// 0'#' 1' ' 2'T' 3'i' 4't' 5'l' 6'e' 7'\n' 8'\n' 9'B' 10'o' 11'd' 12'y' 13' '
    /// 14'*' 15'*' 16'b' 17'o' 18'l' 19'd' 20'*' 21'*' 22' ' 23'a' 24'n' 25'd' 26' '
    /// 27'*' 28'i' 29't' 30'*' 31' ' 32'`' 33'c' 34'o' 35'd' 36'e' 37'`'   (length 38)
    private func fixture1() -> (source: String, tree: MarkdownTree) {
        let source = "# Title\n\nBody **bold** and *it* `code`"
        let lines = [
            MarkdownLine(range: NSRange(location: 0, length: 7), terminator: NSRange(location: 7, length: 1)),
            MarkdownLine(range: NSRange(location: 8, length: 0), terminator: NSRange(location: 8, length: 1)),
            MarkdownLine(range: NSRange(location: 9, length: 29), terminator: NSRange(location: 38, length: 0)),
        ]
        let heading = MarkdownBlock(
            kind: .heading(level: 1, markerRange: NSRange(location: 0, length: 2), closingRange: nil),
            range: NSRange(location: 0, length: 7),
            inlines: [MarkdownInline(kind: .text, range: NSRange(location: 2, length: 5))])
        let blank = MarkdownBlock(kind: .blank, range: NSRange(location: 8, length: 0))
        let strong = MarkdownInline(
            kind: .strong(open: NSRange(location: 14, length: 2), close: NSRange(location: 20, length: 2)),
            range: NSRange(location: 14, length: 8),
            children: [MarkdownInline(kind: .text, range: NSRange(location: 16, length: 4))])
        let emphasis = MarkdownInline(
            kind: .emphasis(open: NSRange(location: 27, length: 1), close: NSRange(location: 30, length: 1)),
            range: NSRange(location: 27, length: 4),
            children: [MarkdownInline(kind: .text, range: NSRange(location: 28, length: 2))])
        let code = MarkdownInline(
            kind: .code(open: NSRange(location: 32, length: 1), close: NSRange(location: 37, length: 1)),
            range: NSRange(location: 32, length: 6),
            children: [])
        let paragraph = MarkdownBlock(
            kind: .paragraph,
            range: NSRange(location: 9, length: 29),
            inlines: [
                MarkdownInline(kind: .text, range: NSRange(location: 9, length: 5)),
                strong,
                MarkdownInline(kind: .text, range: NSRange(location: 22, length: 5)),
                emphasis,
                MarkdownInline(kind: .text, range: NSRange(location: 31, length: 1)),
                code,
            ])
        let tree = MarkdownTree(blocks: [heading, blank, paragraph], lines: lines)
        return (source, tree)
    }

    func testFixture1_RichMode() {
        let (source, tree) = fixture1()
        let presentation = builder.build(source: source, tree: tree, mode: .rich)

        XCTAssertEqual(presentation.displayText, "Title\n\nBody bold and it code")
        XCTAssertEqual(presentation.lines.count, 3)

        let heading = presentation.lines[0]
        XCTAssertEqual(heading.displayRange, NSRange(location: 0, length: 5))
        XCTAssertEqual(heading.block.kind, .heading(level: 1))
        XCTAssertTrue(heading.runs.isEmpty)

        let blank = presentation.lines[1]
        XCTAssertEqual(blank.displayRange, NSRange(location: 6, length: 0))
        XCTAssertEqual(blank.block.kind, .blank)

        let body = presentation.lines[2]
        XCTAssertEqual(body.displayRange, NSRange(location: 7, length: 21))
        XCTAssertEqual(body.block.kind, .paragraph)
        XCTAssertEqual(body.runs, [
            StyleRun(displayRange: NSRange(location: 12, length: 4), style: .strong),
            StyleRun(displayRange: NSRange(location: 21, length: 2), style: .emphasis),
            StyleRun(displayRange: NSRange(location: 24, length: 4), style: .code),
        ])

        // Map round-trips: caret right after the (hidden) heading marker maps back to display 0.
        let afterMarker = presentation.map.sourceOffset(forDisplay: 0)
        XCTAssertEqual(afterMarker, 2)
        XCTAssertEqual(presentation.map.displayOffset(forSource: afterMarker), 0)
    }

    func testFixture1_SourceMode() {
        let (source, tree) = fixture1()
        let presentation = builder.build(source: source, tree: tree, mode: .source)

        XCTAssertEqual(presentation.displayText, source)
        XCTAssertEqual(presentation.lines.count, 3)

        let heading = presentation.lines[0]
        XCTAssertEqual(heading.block.kind, .heading(level: 1)) // still large in source mode
        XCTAssertEqual(heading.runs, [StyleRun(displayRange: NSRange(location: 0, length: 2), style: .syntax)])

        let body = presentation.lines[2]
        XCTAssertEqual(body.runs, [
            StyleRun(displayRange: NSRange(location: 14, length: 2), style: .syntax),
            StyleRun(displayRange: NSRange(location: 16, length: 4), style: .strong),
            StyleRun(displayRange: NSRange(location: 20, length: 2), style: .syntax),
            StyleRun(displayRange: NSRange(location: 27, length: 1), style: .syntax),
            StyleRun(displayRange: NSRange(location: 28, length: 2), style: .emphasis),
            StyleRun(displayRange: NSRange(location: 30, length: 1), style: .syntax),
            StyleRun(displayRange: NSRange(location: 32, length: 1), style: .syntax),
            StyleRun(displayRange: NSRange(location: 33, length: 4), style: .code),
            StyleRun(displayRange: NSRange(location: 37, length: 1), style: .syntax),
        ])
    }

    // MARK: - Fixture 2: task items "- [x] Done\n- [ ] Todo"

    /// Indices: 0'-' 1' ' 2'[' 3'x' 4']' 5' ' 6'D' 7'o' 8'n' 9'e' 10'\n'
    /// 11'-' 12' ' 13'[' 14' ' 15']' 16' ' 17'T' 18'o' 19'd' 20'o'   (length 21)
    func testTaskItems() {
        let source = "- [x] Done\n- [ ] Todo"
        let lines = [
            MarkdownLine(range: NSRange(location: 0, length: 10), terminator: NSRange(location: 10, length: 1)),
            MarkdownLine(range: NSRange(location: 11, length: 10), terminator: NSRange(location: 21, length: 0)),
        ]
        let item1 = MarkdownBlock(
            kind: .listItem(markerRange: NSRange(location: 0, length: 6), ordinal: nil,
                             task: MarkdownTaskState(isChecked: true, markerRange: NSRange(location: 2, length: 3)), depth: 0),
            range: NSRange(location: 0, length: 10),
            children: [MarkdownBlock(kind: .paragraph, range: NSRange(location: 6, length: 4),
                                      inlines: [MarkdownInline(kind: .text, range: NSRange(location: 6, length: 4))])])
        let item2 = MarkdownBlock(
            kind: .listItem(markerRange: NSRange(location: 11, length: 6), ordinal: nil,
                             task: MarkdownTaskState(isChecked: false, markerRange: NSRange(location: 13, length: 3)), depth: 0),
            range: NSRange(location: 11, length: 10),
            children: [MarkdownBlock(kind: .paragraph, range: NSRange(location: 17, length: 4),
                                      inlines: [MarkdownInline(kind: .text, range: NSRange(location: 17, length: 4))])])
        let list = MarkdownBlock(kind: .list(ordered: false, start: 1, tight: true), range: NSRange(location: 0, length: 21), children: [item1, item2])
        let tree = MarkdownTree(blocks: [list], lines: lines)

        let presentation = builder.build(source: source, tree: tree, mode: .rich)
        XCTAssertEqual(presentation.displayText, "Done\nTodo")
        XCTAssertEqual(presentation.lines.count, 2)

        let line0 = presentation.lines[0]
        XCTAssertEqual(line0.displayRange, NSRange(location: 0, length: 4))
        XCTAssertEqual(line0.block.listDepth, 1)
        XCTAssertEqual(line0.block.listMarker, .task(isChecked: true))
        XCTAssertEqual(line0.block.taskMarkerSourceRange, NSRange(location: 2, length: 3))

        let line1 = presentation.lines[1]
        XCTAssertEqual(line1.displayRange, NSRange(location: 5, length: 4))
        XCTAssertEqual(line1.block.listDepth, 1)
        XCTAssertEqual(line1.block.listMarker, .task(isChecked: false))
        XCTAssertEqual(line1.block.taskMarkerSourceRange, NSRange(location: 13, length: 3))
    }

    // MARK: - Fixture 3: nested list with a continuation paragraph line

    /// "- Item\n  - Child\nMore"
    /// 0'-' 1' ' 2'I' 3't' 4'e' 5'm' 6'\n'
    /// 7' ' 8' ' 9'-' 10' ' 11'C' 12'h' 13'i' 14'l' 15'd' 16'\n'
    /// 17'M' 18'o' 19'r' 20'e'   (length 21)
    func testNestedListWithContinuationParagraph() {
        let source = "- Item\n  - Child\nMore"
        let lines = [
            MarkdownLine(range: NSRange(location: 0, length: 6), terminator: NSRange(location: 6, length: 1)),
            MarkdownLine(range: NSRange(location: 7, length: 9), terminator: NSRange(location: 16, length: 1)),
            MarkdownLine(range: NSRange(location: 17, length: 4), terminator: NSRange(location: 21, length: 0)),
        ]
        let innerParagraph = MarkdownBlock(
            kind: .paragraph, range: NSRange(location: 11, length: 10),
            inlines: [
                MarkdownInline(kind: .text, range: NSRange(location: 11, length: 5)),
                MarkdownInline(kind: .softBreak, range: NSRange(location: 16, length: 1)),
                MarkdownInline(kind: .text, range: NSRange(location: 17, length: 4)),
            ])
        let innerItem = MarkdownBlock(
            kind: .listItem(markerRange: NSRange(location: 9, length: 2), ordinal: nil, task: nil, depth: 1),
            range: NSRange(location: 7, length: 14),
            children: [innerParagraph])
        let innerList = MarkdownBlock(kind: .list(ordered: false, start: 1, tight: true), range: NSRange(location: 7, length: 14), children: [innerItem])
        let outerParagraph = MarkdownBlock(kind: .paragraph, range: NSRange(location: 2, length: 4),
                                            inlines: [MarkdownInline(kind: .text, range: NSRange(location: 2, length: 4))])
        let outerItem = MarkdownBlock(
            kind: .listItem(markerRange: NSRange(location: 0, length: 2), ordinal: nil, task: nil, depth: 0),
            range: NSRange(location: 0, length: 21),
            children: [outerParagraph, innerList])
        let outerList = MarkdownBlock(kind: .list(ordered: false, start: 1, tight: true), range: NSRange(location: 0, length: 21), children: [outerItem])
        let tree = MarkdownTree(blocks: [outerList], lines: lines)

        let presentation = builder.build(source: source, tree: tree, mode: .rich)
        XCTAssertEqual(presentation.displayText, "Item\nChild\nMore")

        let item = presentation.lines[0]
        XCTAssertEqual(item.displayRange, NSRange(location: 0, length: 4))
        XCTAssertEqual(item.block.listDepth, 1)
        XCTAssertEqual(item.block.listMarker, .bullet)

        let child = presentation.lines[1]
        XCTAssertEqual(child.displayRange, NSRange(location: 5, length: 5))
        XCTAssertEqual(child.block.listDepth, 2) // depth 1 listItem -> listDepth 2
        XCTAssertEqual(child.block.listMarker, .bullet)

        let more = presentation.lines[2]
        XCTAssertEqual(more.displayRange, NSRange(location: 11, length: 4))
        XCTAssertEqual(more.block.listDepth, 2) // continuation shares the item's listDepth
        XCTAssertNil(more.block.listMarker)      // ...but is not itself a marked item line
        XCTAssertEqual(more.block.kind, .paragraph)

        // The nested item's marker run was extended left over the 2-space indentation.
        let touching = presentation.map.runs(touchingDisplay: NSRange(location: 5, length: 0))
        XCTAssertEqual(touching.first?.sourceRange, NSRange(location: 7, length: 4)) // "  - "
    }

    // MARK: - Fixture 4: block quote with two lines

    /// "> Line one\n> Line two"
    /// 0'>' 1' ' 2'L' 3'i' 4'n' 5'e' 6' ' 7'o' 8'n' 9'e' 10'\n'
    /// 11'>' 12' ' 13'L' 14'i' 15'n' 16'e' 17' ' 18't' 19'w' 20'o'   (length 21)
    func testBlockQuoteTwoLines() {
        let source = "> Line one\n> Line two"
        let lines = [
            MarkdownLine(range: NSRange(location: 0, length: 10), terminator: NSRange(location: 10, length: 1)),
            MarkdownLine(range: NSRange(location: 11, length: 10), terminator: NSRange(location: 21, length: 0)),
        ]
        let paragraph = MarkdownBlock(
            kind: .paragraph, range: NSRange(location: 2, length: 19),
            inlines: [
                MarkdownInline(kind: .text, range: NSRange(location: 2, length: 8)),
                MarkdownInline(kind: .softBreak, range: NSRange(location: 10, length: 3)),
                MarkdownInline(kind: .text, range: NSRange(location: 13, length: 8)),
            ])
        let quote = MarkdownBlock(
            kind: .blockquote(markerRanges: [NSRange(location: 0, length: 2), NSRange(location: 11, length: 2)]),
            range: NSRange(location: 0, length: 21),
            children: [paragraph])
        let tree = MarkdownTree(blocks: [quote], lines: lines)

        let presentation = builder.build(source: source, tree: tree, mode: .rich)
        XCTAssertEqual(presentation.displayText, "Line one\nLine two")
        XCTAssertEqual(presentation.lines[0].displayRange, NSRange(location: 0, length: 8))
        XCTAssertEqual(presentation.lines[0].block.quoteDepth, 1)
        XCTAssertEqual(presentation.lines[1].displayRange, NSRange(location: 9, length: 8))
        XCTAssertEqual(presentation.lines[1].block.quoteDepth, 1)
    }

    // MARK: - Fixture 5: fenced code

    /// "```swift\nlet x = 1\n```"
    /// opening fence [0,8), content line [9,18), closing fence [19,22)   (length 22)
    func testFencedCode() {
        let source = "```swift\nlet x = 1\n```"
        let lines = [
            MarkdownLine(range: NSRange(location: 0, length: 8), terminator: NSRange(location: 8, length: 1)),
            MarkdownLine(range: NSRange(location: 9, length: 9), terminator: NSRange(location: 18, length: 1)),
            MarkdownLine(range: NSRange(location: 19, length: 3), terminator: NSRange(location: 22, length: 0)),
        ]
        let fenced = MarkdownBlock(
            kind: .fencedCode(info: "swift", openingFence: NSRange(location: 0, length: 8),
                               closingFence: NSRange(location: 19, length: 3), contentRange: NSRange(location: 9, length: 9)),
            range: NSRange(location: 0, length: 22))
        let tree = MarkdownTree(blocks: [fenced], lines: lines)

        let presentation = builder.build(source: source, tree: tree, mode: .rich)
        XCTAssertEqual(presentation.displayText, source) // fences are never hidden
        XCTAssertEqual(presentation.lines.count, 3)
        for line in presentation.lines {
            XCTAssertEqual(line.block.kind, .codeBlock(isFence: true))
        }
        XCTAssertEqual(presentation.lines[0].runs, [StyleRun(displayRange: NSRange(location: 0, length: 8), style: .syntax)])
        XCTAssertTrue(presentation.lines[1].runs.isEmpty) // no inline styling inside code blocks
        XCTAssertEqual(presentation.lines[2].runs, [StyleRun(displayRange: NSRange(location: 19, length: 3), style: .syntax)])
    }

    // MARK: - Fixture 6: link

    /// "[a](http://x)" — open "[" [0,1), close "](http://x)" [2,13), text "a" [1,2).
    func testLink() {
        let source = "[a](http://x)"
        let lines = [MarkdownLine(range: NSRange(location: 0, length: 13), terminator: NSRange(location: 13, length: 0))]
        let link = MarkdownInline(
            kind: .link(destination: "http://x", open: NSRange(location: 0, length: 1), close: NSRange(location: 2, length: 11)),
            range: NSRange(location: 0, length: 13),
            children: [MarkdownInline(kind: .text, range: NSRange(location: 1, length: 1))])
        let paragraph = MarkdownBlock(kind: .paragraph, range: NSRange(location: 0, length: 13), inlines: [link])
        let tree = MarkdownTree(blocks: [paragraph], lines: lines)

        let presentation = builder.build(source: source, tree: tree, mode: .rich)
        XCTAssertEqual(presentation.displayText, "a")
        XCTAssertEqual(presentation.lines[0].runs, [StyleRun(displayRange: NSRange(location: 0, length: 1), style: .link, destination: "http://x")])
    }

    // MARK: - CRLF document

    /// "Line1\r\nLine2" — CR at index 5 is hidden (part of \r\n), display uses \n.
    func testCRLFDocument() {
        let source = "Line1\r\nLine2"
        let lines = [
            MarkdownLine(range: NSRange(location: 0, length: 5), terminator: NSRange(location: 5, length: 2)),
            MarkdownLine(range: NSRange(location: 7, length: 5), terminator: NSRange(location: 12, length: 0)),
        ]
        let paragraph = MarkdownBlock(
            kind: .paragraph, range: NSRange(location: 0, length: 12),
            inlines: [
                MarkdownInline(kind: .text, range: NSRange(location: 0, length: 5)),
                MarkdownInline(kind: .softBreak, range: NSRange(location: 5, length: 2)),
                MarkdownInline(kind: .text, range: NSRange(location: 7, length: 5)),
            ])
        let tree = MarkdownTree(blocks: [paragraph], lines: lines)

        let presentation = builder.build(source: source, tree: tree, mode: .rich)
        XCTAssertEqual(presentation.displayText, "Line1\nLine2")
        XCTAssertEqual(presentation.lines.count, 2)
        XCTAssertEqual(presentation.lines[0].displayRange, NSRange(location: 0, length: 5))
        XCTAssertEqual(presentation.lines[1].displayRange, NSRange(location: 6, length: 5))

        // Map round trip for an offset on the second line.
        let displayOffset = presentation.map.displayOffset(forSource: 9) // 'n' in "Line2"
        XCTAssertEqual(displayOffset, 8)
        XCTAssertEqual(presentation.map.sourceOffset(forDisplay: displayOffset), 9)
    }

    // MARK: - Emoji before a bold span

    /// "😀**bold**" — emoji is a surrogate pair (2 UTF-16 units) at [0,2).
    func testEmojiBeforeBoldSpan() {
        let source = "\u{1F600}**bold**"
        let lines = [MarkdownLine(range: NSRange(location: 0, length: 10), terminator: NSRange(location: 10, length: 0))]
        let strong = MarkdownInline(
            kind: .strong(open: NSRange(location: 2, length: 2), close: NSRange(location: 8, length: 2)),
            range: NSRange(location: 2, length: 8),
            children: [MarkdownInline(kind: .text, range: NSRange(location: 4, length: 4))])
        let paragraph = MarkdownBlock(
            kind: .paragraph, range: NSRange(location: 0, length: 10),
            inlines: [MarkdownInline(kind: .text, range: NSRange(location: 0, length: 2)), strong])
        let tree = MarkdownTree(blocks: [paragraph], lines: lines)

        let presentation = builder.build(source: source, tree: tree, mode: .rich)
        XCTAssertEqual(presentation.displayText, "\u{1F600}bold")
        XCTAssertEqual(presentation.lines[0].displayRange, NSRange(location: 0, length: 6))
        XCTAssertEqual(presentation.lines[0].runs, [StyleRun(displayRange: NSRange(location: 2, length: 4), style: .strong)])
    }

    // MARK: - styleSignature

    func testStyleSignatureEqualForIdenticalRelativeStyling() {
        let lineA = PresentationLine(
            displayRange: NSRange(location: 0, length: 10),
            block: BlockPresentation(kind: .paragraph),
            runs: [StyleRun(displayRange: NSRange(location: 2, length: 4), style: .strong)])
        let lineB = PresentationLine(
            displayRange: NSRange(location: 20, length: 10),
            block: BlockPresentation(kind: .paragraph),
            runs: [StyleRun(displayRange: NSRange(location: 22, length: 4), style: .strong)])
        XCTAssertEqual(lineA.styleSignature, lineB.styleSignature)

        let lineC = PresentationLine(
            displayRange: NSRange(location: 20, length: 10),
            block: BlockPresentation(kind: .paragraph),
            runs: [StyleRun(displayRange: NSRange(location: 22, length: 4), style: .emphasis)])
        XCTAssertNotEqual(lineA.styleSignature, lineC.styleSignature)
    }
}
