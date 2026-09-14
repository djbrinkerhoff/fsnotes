import XCTest
@testable import MarkdownEditorCore

@MainActor
final class EditorSessionTests: XCTestCase {

    private final class Recorder: EditorSessionDelegate {
        var updates: [PresentationUpdate] = []
        var edits = 0
        func session(_ session: EditorSession, didApply update: PresentationUpdate) { updates.append(update) }
        func sessionDidEditDocument(_ session: EditorSession) { edits += 1 }
    }

    private func makeSession(_ source: String, mode: EditorMode = .rich) -> (EditorSession, Recorder) {
        let session = EditorSession(source: source, parser: CommonMarkLineParser(), builder: PresentationBuilder(), mode: mode)
        let recorder = Recorder()
        session.delegate = recorder
        return (session, recorder)
    }

    /// Applies the update to a shadow display string exactly like an adapter would, and checks the invariant.
    private func applyAndCheck(_ shadow: inout String, _ update: PresentationUpdate, _ session: EditorSession, file: StaticString = #filePath, line: UInt = #line) {
        let ns = NSMutableString(string: shadow)
        if update.isFullReplacement {
            shadow = update.replacementText
        } else if update.replacedDisplayRange.length > 0 || !update.replacementText.isEmpty {
            ns.replaceCharacters(in: update.replacedDisplayRange, with: update.replacementText)
            shadow = ns as String
        }
        XCTAssertEqual(shadow, session.presentation.displayText, "adapter shadow must match presentation", file: file, line: line)
        XCTAssertLessThanOrEqual(NSMaxRange(update.restyleDisplayRange), session.presentation.displayLength, file: file, line: line)
    }

    private func type(_ text: String, into session: EditorSession, shadow: inout String, recorder: Recorder) {
        for scalar in text.unicodeScalars {
            let s = String(scalar)
            if s == "\n" { session.insertNewline() } else { session.replaceDisplay(range: session.selection, with: s) }
            applyAndCheck(&shadow, recorder.updates.last!, session)
        }
    }

    // MARK: Headings

    func testTypingHashSpaceMakesHeadingWithHiddenMarker() {
        let (session, recorder) = makeSession("")
        var shadow = ""
        type("# ", into: session, shadow: &shadow, recorder: recorder)
        XCTAssertEqual(session.source, "# ")
        XCTAssertEqual(session.presentation.displayText, "")
        XCTAssertEqual(session.presentation.lines[0].block.kind, .heading(level: 1))
        type("Title", into: session, shadow: &shadow, recorder: recorder)
        XCTAssertEqual(session.source, "# Title")
        XCTAssertEqual(session.presentation.displayText, "Title")
        XCTAssertEqual(session.selection, NSRange(location: 5, length: 0))
        type("\nBody", into: session, shadow: &shadow, recorder: recorder)
        XCTAssertEqual(session.source, "# Title\nBody")
        XCTAssertEqual(session.presentation.displayText, "Title\nBody")
        XCTAssertEqual(session.presentation.lines[1].block.kind, .paragraph)

        // Undo all the way back, then redo.
        var undos = 0
        while session.undoManager.canUndo { session.undoManager.undo(); undos += 1; applyAndCheck(&shadow, recorder.updates.last!, session) }
        XCTAssertEqual(session.source, "")
        XCTAssertLessThanOrEqual(undos, 4, "typing must coalesce")
        while session.undoManager.canRedo { session.undoManager.redo(); applyAndCheck(&shadow, recorder.updates.last!, session) }
        XCTAssertEqual(session.source, "# Title\nBody")
    }

    func testCaretAtHeadingStartInsertsAfterMarker() {
        let (session, recorder) = makeSession("# Title")
        session.selection = NSRange(location: 0, length: 0)
        session.replaceDisplay(range: session.selection, with: "X")
        XCTAssertEqual(session.source, "# XTitle")
        XCTAssertEqual(recorder.updates.last?.selection, NSRange(location: 1, length: 0))
    }

    func testBackspaceAtHeadingStartRemovesMarker() {
        let (session, _) = makeSession("# Title")
        session.selection = NSRange(location: 0, length: 0)
        XCTAssertTrue(session.handleBackspace())
        XCTAssertEqual(session.source, "Title")
        session.selection = NSRange(location: 0, length: 0)
        XCTAssertFalse(session.handleBackspace())
    }

    func testSetHeadingLevel() {
        let (session, _) = makeSession("Hello")
        session.selection = NSRange(location: 2, length: 0)
        session.setHeadingLevel(2)
        XCTAssertEqual(session.source, "## Hello")
        XCTAssertEqual(session.selection, NSRange(location: 2, length: 0))
        session.setHeadingLevel(nil)
        XCTAssertEqual(session.source, "Hello")
    }

    // MARK: Inline formatting boundaries

    func testHiddenDelimitersAndInsertionAtBoundaries() {
        let (session, _) = makeSession("a **b** c")
        XCTAssertEqual(session.presentation.displayText, "a b c")
        // Insert at the end of the bold word: continues bold.
        session.selection = NSRange(location: 3, length: 0)
        session.replaceDisplay(range: session.selection, with: "x")
        XCTAssertEqual(session.source, "a **bx** c")
        // Insert at start of bold word: joins bold too.
        session.selection = NSRange(location: 2, length: 0)
        session.replaceDisplay(range: session.selection, with: "y")
        XCTAssertEqual(session.source, "a **ybx** c")
    }

    func testDeletingWholeBoldWordRemovesDelimiters() {
        let (session, _) = makeSession("a **b** c")
        session.replaceDisplay(range: NSRange(location: 2, length: 1), with: "")
        XCTAssertEqual(session.source, "a  c")
    }

    func testIncompleteSyntaxStaysVisible() {
        let (session, _) = makeSession("")
        session.replaceDisplay(range: session.selection, with: "_")
        XCTAssertEqual(session.presentation.displayText, "_")
        session.replaceDisplay(range: session.selection, with: "a")
        XCTAssertEqual(session.presentation.displayText, "_a")
        session.replaceDisplay(range: session.selection, with: "_")
        XCTAssertEqual(session.presentation.displayText, "a")
        XCTAssertEqual(session.presentation.lines[0].runs.first?.style, .emphasis)
    }

    func testToggleInlineWrapsAndUnwraps() {
        let (session, _) = makeSession("hello world")
        session.selection = NSRange(location: 0, length: 5)
        session.toggleInline(.strong)
        XCTAssertEqual(session.source, "**hello** world")
        XCTAssertEqual(session.selection, NSRange(location: 0, length: 5))
        session.toggleInline(.strong)
        XCTAssertEqual(session.source, "hello world")
    }

    // MARK: Tasks

    func testToggleTaskIsOneUndoStepAndKeepsSelection() {
        let (session, recorder) = makeSession("- [ ] Buy milk\n- [x] Done")
        XCTAssertEqual(session.presentation.displayText, "Buy milk\nDone")
        session.selection = NSRange(location: 3, length: 2)
        let marker = session.presentation.lines[0].block.taskMarkerSourceRange!
        XCTAssertTrue(session.toggleTask(markerSourceRange: marker))
        XCTAssertEqual(session.source, "- [x] Buy milk\n- [x] Done")
        XCTAssertEqual(session.selection, NSRange(location: 3, length: 2))
        XCTAssertEqual(recorder.updates.last?.replacementText, "")
        session.undoManager.undo()
        XCTAssertEqual(session.source, "- [ ] Buy milk\n- [x] Done")
        XCTAssertFalse(session.undoManager.canUndo)
        XCTAssertTrue(session.toggleTask(atDisplayLine: 1))
        XCTAssertEqual(session.source, "- [ ] Buy milk\n- [ ] Done")
    }

    // MARK: Lists

    func testReturnContinuesAndExitsLists() {
        let (session, recorder) = makeSession("- one")
        var shadow = session.presentation.displayText
        session.selection = NSRange(location: 3, length: 0)
        type("\n", into: session, shadow: &shadow, recorder: recorder)
        XCTAssertEqual(session.source, "- one\n- ")
        type("two", into: session, shadow: &shadow, recorder: recorder)
        XCTAssertEqual(session.source, "- one\n- two")
        type("\n", into: session, shadow: &shadow, recorder: recorder)
        XCTAssertEqual(session.source, "- one\n- two\n- ")
        type("\n", into: session, shadow: &shadow, recorder: recorder)
        XCTAssertEqual(session.source, "- one\n- two\n", "Return on an empty item exits the list")
        XCTAssertEqual(session.presentation.lines.last?.block.listDepth, 0)
    }

    func testOrderedAndTaskContinuation() {
        let (session, _) = makeSession("1. a\n2. b")
        session.selection = NSRange(location: 3, length: 0)
        session.insertNewline()
        XCTAssertEqual(session.source, "1. a\n2. b\n3. ")
        let (s2, _) = makeSession("- [x] done")
        s2.selection = NSRange(location: 4, length: 0)
        s2.insertNewline()
        XCTAssertEqual(s2.source, "- [x] done\n- [ ] ")
    }

    func testIndentOutdent() {
        let (session, _) = makeSession("- one\n- two")
        session.selection = NSRange(location: 5, length: 0) // in "two"
        XCTAssertTrue(session.indent())
        XCTAssertEqual(session.source, "- one\n  - two")
        XCTAssertEqual(session.presentation.lines[1].block.listDepth, 2)
        XCTAssertTrue(session.outdent())
        XCTAssertEqual(session.source, "- one\n- two")
        XCTAssertFalse(session.outdent())
    }

    func testBackspaceAtListItemStartRemovesMarker() {
        let (session, _) = makeSession("- one\n- two")
        session.selection = NSRange(location: 4, length: 0)
        XCTAssertTrue(session.handleBackspace())
        XCTAssertEqual(session.source, "- one\ntwo")
    }

    func testToggleList() {
        let (session, _) = makeSession("a\nb")
        session.selection = NSRange(location: 0, length: 3)
        session.toggleList(.task)
        XCTAssertEqual(session.source, "- [ ] a\n- [ ] b")
        session.toggleList(.task)
        XCTAssertEqual(session.source, "a\nb")
    }

    // MARK: Quotes

    func testQuoteContinuation() {
        let (session, _) = makeSession("> q")
        session.selection = NSRange(location: 1, length: 0)
        session.insertNewline()
        XCTAssertEqual(session.source, "> q\n> ")
        session.insertNewline()
        XCTAssertEqual(session.source, "> q\n")
    }

    // MARK: Source mode

    func testSourceModeToggleKeepsSelectionAndUndo() {
        let (session, recorder) = makeSession("# Title\n\n**bold** text")
        session.selection = NSRange(location: 0, length: 0)
        session.replaceDisplay(range: session.selection, with: "A")
        XCTAssertEqual(session.source, "# ATitle\n\n**bold** text")
        session.selection = NSRange(location: 11, length: 4) // "text" in display "ATitle\n\nbold text"
        let sourceSel = session.sourceSelection()
        session.toggleMode()
        XCTAssertEqual(session.mode, .source)
        XCTAssertEqual(session.presentation.displayText, session.source)
        XCTAssertTrue(recorder.updates.last!.isFullReplacement)
        XCTAssertEqual(session.sourceSelection(), sourceSel)
        XCTAssertTrue(session.undoManager.canUndo)
        session.undoManager.undo()
        XCTAssertEqual(session.source, "# Title\n\n**bold** text")
        session.toggleMode()
        XCTAssertEqual(session.presentation.displayText, "Title\n\nbold text")
    }

    // MARK: Copy

    func testMarkdownForDisplayRange() {
        let (session, _) = makeSession("a **b** c")
        XCTAssertEqual(session.markdown(forDisplayRange: NSRange(location: 0, length: 5)), "a **b** c")
        XCTAssertEqual(session.markdown(forDisplayRange: NSRange(location: 2, length: 1)), "**b**")
        XCTAssertEqual(session.markdown(forDisplayRange: NSRange(location: 0, length: 2)), "a ")
    }

    // MARK: Fidelity

    func testCRLFPreservedAndNewlinesUseDocumentEnding() {
        let (session, _) = makeSession("a\r\nb")
        XCTAssertEqual(session.presentation.displayText, "a\nb")
        session.selection = NSRange(location: 3, length: 0)
        session.insertNewline()
        XCTAssertEqual(session.source, "a\r\nb\r\n")
        session.replaceDisplay(range: session.selection, with: "c")
        XCTAssertEqual(session.source, "a\r\nb\r\nc")
    }

    func testReconcileNativeEdit() {
        let (session, _) = makeSession("hello wrold")
        session.reconcile(displayText: "hello world", selection: NSRange(location: 11, length: 0))
        XCTAssertEqual(session.source, "hello world")
        XCTAssertEqual(session.selection, NSRange(location: 11, length: 0))
    }

    func testExternalReloadClearsUndoAndKeepsCaret() {
        let (session, _) = makeSession("abc")
        session.replaceDisplay(range: NSRange(location: 3, length: 0), with: "d")
        session.selection = NSRange(location: 2, length: 0)
        session.replaceSource(with: "abXcd")
        XCTAssertFalse(session.undoManager.canUndo)
        XCTAssertEqual(session.selection, NSRange(location: 2, length: 0))
    }

    func testUnicodeOffsets() {
        let (session, _) = makeSession("👍🏽 **b** 日本")
        XCTAssertEqual(session.presentation.displayText, "👍🏽 b 日本")
        session.selection = NSRange(location: 6, length: 0) // after "b" (emoji is 4 units + space)
        session.replaceDisplay(range: session.selection, with: "x")
        XCTAssertEqual(session.source, "👍🏽 **bx** 日本")
    }

    // MARK: Performance

    func testTypingLatencyOnLargeDocument() {
        var text = ""
        let fixture = try! String(contentsOf: Bundle.module.url(forResource: "mixed", withExtension: "md", subdirectory: "Fixtures")!)
        while (text as NSString).length < 100_000 { text += fixture + "\n" }
        let (session, _) = makeSession(text)
        session.selection = NSRange(location: 40, length: 0)
        var samples: [Double] = []
        for i in 0..<30 {
            session.replaceDisplay(range: session.selection, with: i % 2 == 0 ? "x" : " ")
            samples.append(session.lastMetrics.total)
        }
        samples.sort()
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        print("100KB typing p95 = \(p95 * 1000) ms (parse \(session.lastMetrics.parse * 1000) ms, present \(session.lastMetrics.present * 1000) ms, diff \(session.lastMetrics.diff * 1000) ms)")
        XCTAssertLessThan(p95, 0.25, "debug-build sanity bound; release target is 8 ms")
    }
}
