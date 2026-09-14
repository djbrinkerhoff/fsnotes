import XCTest
@testable import MarkdownEditorCore

final class SourceDisplayMapTests: XCTestCase {

    // MARK: - Identity

    func testIdentityMap() {
        let map = SourceDisplayMap.identity(sourceLength: 10)
        XCTAssertEqual(map.displayLength, 10)
        XCTAssertTrue(map.runs.isEmpty)
        for i in 0...10 {
            XCTAssertEqual(map.displayOffset(forSource: i), i)
            XCTAssertEqual(map.sourceOffset(forDisplay: i), i)
        }
        XCTAssertEqual(map.sourceRange(forDisplay: NSRange(location: 2, length: 3)), NSRange(location: 2, length: 3))
        XCTAssertEqual(map.displayRange(forSource: NSRange(location: 2, length: 3)), NSRange(location: 2, length: 3))
    }

    // MARK: - Single leading run at position 0

    /// "**a**" — open "**" [0,2) leading, close "**" [3,5) trailing, visible text "a" at [2,3).
    func testSingleLeadingRunAtPositionZero() {
        let map = SourceDisplayMap(sourceLength: 5, runs: [
            .init(sourceRange: NSRange(location: 0, length: 2), attachment: .leading),
            .init(sourceRange: NSRange(location: 3, length: 2), attachment: .trailing),
        ])
        XCTAssertEqual(map.displayLength, 1)
        // The whole leading run collapses to display 0.
        XCTAssertEqual(map.displayOffset(forSource: 0), 0)
        XCTAssertEqual(map.displayOffset(forSource: 1), 0)
        XCTAssertEqual(map.displayOffset(forSource: 2), 0)
        // 'a' itself maps to display 0 too (it's the character right after the run).
        XCTAssertEqual(map.displayOffset(forSource: 3), 1)
    }

    // MARK: - Trailing run at the end

    /// "ab**" — trailing run [2,4) at the very end, visible text "ab" at [0,2).
    func testTrailingRunAtEnd() {
        let map = SourceDisplayMap(sourceLength: 4, runs: [
            .init(sourceRange: NSRange(location: 2, length: 2), attachment: .trailing),
        ])
        XCTAssertEqual(map.displayLength, 2)
        // A collapsed caret at the end stops before the trailing run.
        XCTAssertEqual(map.sourceOffset(forDisplay: 2), 2)
        XCTAssertEqual(map.displayOffset(forSource: 2), 2)
        XCTAssertEqual(map.displayOffset(forSource: 3), 2)
        XCTAssertEqual(map.displayOffset(forSource: 4), 2)
    }

    // MARK: - Adjacent trailing+leading runs at the same display position

    /// "**a**_b_" — strong close [3,5) trailing and emphasis open [5,6) leading collapse to the
    /// same display position (1), between visible "a" (display 0) and "b" (display 1).
    private func adjacentRunsMap() -> SourceDisplayMap {
        SourceDisplayMap(sourceLength: 8, runs: [
            .init(sourceRange: NSRange(location: 0, length: 2), attachment: .leading),  // "**"
            .init(sourceRange: NSRange(location: 3, length: 2), attachment: .trailing), // "**"
            .init(sourceRange: NSRange(location: 5, length: 1), attachment: .leading),  // "_"
            .init(sourceRange: NSRange(location: 7, length: 1), attachment: .trailing), // "_"
        ])
    }

    func testAdjacentRunsShareDisplayPosition() {
        let map = adjacentRunsMap()
        XCTAssertEqual(map.displayLength, 2) // "a" and "b"
        XCTAssertEqual(map.displayOffset(forSource: 2), 0)  // end of "a"
        XCTAssertEqual(map.displayOffset(forSource: 3), 1)  // start of close-run == same display pos as open-run
        XCTAssertEqual(map.displayOffset(forSource: 5), 1)
        XCTAssertEqual(map.displayOffset(forSource: 6), 1)  // "b"
    }

    /// `sourceOffset(forDisplay:)` stops before the trailing run when a collapsed caret sits at a
    /// display position shared by a trailing run followed by a leading run.
    func testSourceOffsetStopsBeforeTrailingRun() {
        let map = adjacentRunsMap()
        XCTAssertEqual(map.sourceOffset(forDisplay: 1), 3) // right after "a", before the closing "**"
    }

    /// A full-word selection of the bold word (display [0,1)) must include both delimiters.
    func testSourceRangeFullWordSelectionIncludesBothDelimiters() {
        let map = adjacentRunsMap()
        XCTAssertEqual(map.sourceRange(forDisplay: NSRange(location: 0, length: 1)), NSRange(location: 0, length: 5)) // "**a**"
    }

    /// A selection ending right before a bold word excludes the opening delimiter.
    /// "x**a**" — leading run [1,3), trailing run [4,6), visible "x" then "a".
    func testSourceRangeEndingBeforeBoldWordExcludesOpeningDelimiter() {
        let map = SourceDisplayMap(sourceLength: 6, runs: [
            .init(sourceRange: NSRange(location: 1, length: 2), attachment: .leading),
            .init(sourceRange: NSRange(location: 4, length: 2), attachment: .trailing),
        ])
        XCTAssertEqual(map.displayLength, 2) // "x" + "a"
        // Selecting display [0,1) ("x") must not swallow the opening "**".
        XCTAssertEqual(map.sourceRange(forDisplay: NSRange(location: 0, length: 1)), NSRange(location: 0, length: 1))
    }

    // MARK: - displayOffset inside a hidden run

    func testDisplayOffsetInsideHiddenRunReturnsRunPosition() {
        let map = SourceDisplayMap(sourceLength: 6, runs: [
            .init(sourceRange: NSRange(location: 1, length: 2), attachment: .leading),
            .init(sourceRange: NSRange(location: 4, length: 2), attachment: .trailing),
        ])
        // Any source offset strictly inside the leading run collapses to the run's display position.
        XCTAssertEqual(map.displayOffset(forSource: 1), 1)
        XCTAssertEqual(map.displayOffset(forSource: 2), 1)
    }

    // MARK: - Round trips

    func testRoundTrip() {
        let map = SourceDisplayMap(sourceLength: 6, runs: [
            .init(sourceRange: NSRange(location: 1, length: 2), attachment: .leading),
            .init(sourceRange: NSRange(location: 4, length: 2), attachment: .trailing),
        ])
        for displayOffset in 0...map.displayLength {
            let source = map.sourceOffset(forDisplay: displayOffset)
            XCTAssertEqual(map.displayOffset(forSource: source), displayOffset, "round trip failed at display \(displayOffset)")
        }
    }

    // MARK: - runs(touchingDisplay:)

    func testRunsTouchingDisplay() {
        let map = adjacentRunsMap()
        let touching = map.runs(touchingDisplay: NSRange(location: 1, length: 0))
        XCTAssertEqual(touching.count, 2)
        XCTAssertEqual(touching[0].sourceRange, NSRange(location: 3, length: 2))
        XCTAssertEqual(touching[1].sourceRange, NSRange(location: 5, length: 1))

        // A range far from any collapsed run touches nothing.
        let gapMap = SourceDisplayMap(sourceLength: 10, runs: [
            .init(sourceRange: NSRange(location: 0, length: 2), attachment: .leading),
        ])
        let none = gapMap.runs(touchingDisplay: NSRange(location: 5, length: 0))
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: - Out-of-range clamping

    func testOutOfRangeClamping() {
        let map = SourceDisplayMap(sourceLength: 6, runs: [
            .init(sourceRange: NSRange(location: 1, length: 2), attachment: .leading),
            .init(sourceRange: NSRange(location: 4, length: 2), attachment: .trailing),
        ])
        XCTAssertEqual(map.sourceOffset(forDisplay: -5), map.sourceOffset(forDisplay: 0))
        XCTAssertEqual(map.sourceOffset(forDisplay: 999), map.sourceOffset(forDisplay: map.displayLength))
        XCTAssertEqual(map.displayOffset(forSource: -3), map.displayOffset(forSource: 0))
        XCTAssertEqual(map.displayOffset(forSource: 999), map.displayOffset(forSource: map.sourceLength))
    }
}
