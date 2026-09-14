import XCTest
@testable import MarkdownEditorCore

final class MarkdownFileCodecTests: XCTestCase {
    private func fixtureData(_ name: String) -> Data {
        try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures")!)
    }

    func testRoundTripPreservesBytesForAllFixtures() {
        let codec = MarkdownFileCodec()
        for name in ["mixed", "crlf", "bom", "unicode", "frontmatter"] {
            let data = fixtureData(name)
            let decoded = codec.decode(data)
            XCTAssertFalse(decoded.isLossy, name)
            XCTAssertEqual(codec.encode(decoded.text, hasBOM: decoded.hasBOM), data, "\(name) must round-trip byte for byte")
        }
    }

    func testBOMAndLineEndingsDetected() {
        let codec = MarkdownFileCodec()
        let bom = codec.decode(fixtureData("bom"))
        XCTAssertTrue(bom.hasBOM)
        XCTAssertTrue(bom.text.hasPrefix("# BOM"))
        let crlf = codec.decode(fixtureData("crlf"))
        XCTAssertFalse(crlf.hasBOM)
        XCTAssertEqual(crlf.lineEnding, .crlf)
        XCTAssertEqual(codec.decode(fixtureData("mixed")).lineEnding, .lf)
    }

    @MainActor
    func testEditingCRLFDocumentLeavesOtherLinesIntact() {
        let codec = MarkdownFileCodec()
        let decoded = codec.decode(fixtureData("crlf"))
        let session = EditorSession(source: decoded.text, parser: CommonMarkLineParser(), builder: PresentationBuilder())
        // Append to "Line one" (display line index 2).
        let line = session.presentation.lines[2]
        session.selection = NSRange(location: NSMaxRange(line.displayRange), length: 0)
        session.replaceDisplay(range: session.selection, with: "!")
        session.insertNewline()
        let saved = codec.encode(session.source, hasBOM: decoded.hasBOM)
        let expected = "# Title\r\n\r\nLine one!\r\n\r\nLine two with **bold**\r\n\r\n- [ ] task\r\n"
        XCTAssertEqual(String(data: saved, encoding: .utf8), expected)
    }

    func testInvalidUTF8IsFlaggedLossy() {
        let codec = MarkdownFileCodec()
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9]) // "café" in ISO-8859-1
        let decoded = codec.decode(latin1)
        XCTAssertTrue(decoded.isLossy)
        XCTAssertEqual(decoded.text.count, 4)
    }
}
