#if canImport(AppKit)
import AppKit
import XCTest
@testable import MarkdownEditorAppKit
@testable import MarkdownEditorCore

@MainActor
final class AppKitEditorTests: XCTestCase {

    /// Builds an offscreen editor, hosted in a real (borderless) `NSWindow` so layout runs, backed by
    /// a fresh `EditorSession` over `source`.
    private func makeEditor(source: String = "") -> (window: NSWindow, scrollView: NSScrollView, textView: MarkdownTextView, session: EditorSession, adapter: AppKitEditorAdapter) {
        let theme = ResolvedTheme(bodyFont: .systemFont(ofSize: 13))
        let (scrollView, textView) = MarkdownTextView.makeScrollableEditor(theme: theme)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = scrollView
        let session = EditorSession(source: source, parser: CommonMarkLineParser(), builder: PresentationBuilder())
        let adapter = AppKitEditorAdapter(textView: textView, session: session, theme: theme)
        // Force layout so TextKit 2 fragments are created.
        textView.layoutSubtreeIfNeeded()
        return (window, scrollView, textView, session, adapter)
    }

    private func assertInvariant(_ textView: MarkdownTextView, _ session: EditorSession, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(textView.string, session.presentation.displayText, "display text invariant broken", file: file, line: line)
    }

    private func type(_ textView: MarkdownTextView, _ text: String) {
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    private func doCommand(_ textView: MarkdownTextView, _ selector: Selector) {
        textView.doCommand(by: selector)
    }

    // MARK: 1. Typing a heading + return + body

    func testTypingHeadingAndBodyWithUndoRedo() {
        let (_, _, textView, session, _) = makeEditor()

        type(textView, "#")
        type(textView, " ")
        assertInvariant(textView, session)
        type(textView, "T")
        type(textView, "i")
        type(textView, "t")
        type(textView, "l")
        type(textView, "e")
        assertInvariant(textView, session)
        doCommand(textView, #selector(NSResponder.insertNewline(_:)))
        assertInvariant(textView, session)
        type(textView, "B")
        type(textView, "o")
        type(textView, "d")
        type(textView, "y")
        assertInvariant(textView, session)

        XCTAssertEqual(session.source, "# Title\nBody")
        XCTAssertEqual(session.presentation.displayText, "Title\nBody")

        let firstLine = session.presentation.lines[0]
        let secondLine = session.presentation.lines[1]
        XCTAssertTrue(firstLine.block.kind == .heading(level: 1))
        XCTAssertEqual(secondLine.block.kind, .paragraph)

        let headingFont = AttributeBuilder(theme: ResolvedTheme(bodyFont: .systemFont(ofSize: 13))).attributes(for: firstLine).paragraph[.font] as? NSFont
        let bodyFont = AttributeBuilder(theme: ResolvedTheme(bodyFont: .systemFont(ofSize: 13))).attributes(for: secondLine).paragraph[.font] as? NSFont
        XCTAssertNotNil(headingFont)
        XCTAssertNotNil(bodyFont)
        XCTAssertGreaterThan(headingFont!.pointSize, bodyFont!.pointSize)

        // Undo back to empty.
        var guardCount = 0
        while session.undoManager.canUndo, guardCount < 50 {
            session.undoManager.undo()
            guardCount += 1
        }
        assertInvariant(textView, session)
        XCTAssertEqual(session.source, "")

        // Redo restores everything.
        guardCount = 0
        while session.undoManager.canRedo, guardCount < 50 {
            session.undoManager.redo()
            guardCount += 1
        }
        assertInvariant(textView, session)
        XCTAssertEqual(session.source, "# Title\nBody")
    }

    // MARK: 2. Toggling a task

    func testToggleTaskProducesSingleUndoStep() {
        let (_, _, textView, session, _) = makeEditor(source: "- [ ] Task")
        assertInvariant(textView, session)
        let selectionBefore = session.selection

        guard let markerRange = session.presentation.lines[0].block.taskMarkerSourceRange else {
            return XCTFail("expected a task marker range")
        }
        let undoCountBefore = session.undoManager.canUndo
        XCTAssertTrue(session.toggleTask(markerSourceRange: markerRange))
        assertInvariant(textView, session)
        XCTAssertEqual(session.source, "- [x] Task")
        XCTAssertEqual(session.selection, selectionBefore)

        session.undoManager.undo()
        assertInvariant(textView, session)
        XCTAssertEqual(session.source, "- [ ] Task")
        XCTAssertEqual(session.undoManager.canUndo, undoCountBefore)
    }

    // MARK: 3. Moving the caret across a hidden delimiter

    func testCaretStepsOverHiddenDelimitersOneAtATime() {
        let (_, _, textView, session, _) = makeEditor(source: "a **b** c")
        assertInvariant(textView, session)
        XCTAssertEqual(session.presentation.displayText, "a b c")

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        for expected in 1...5 {
            doCommand(textView, #selector(NSResponder.moveRight(_:)))
            XCTAssertEqual(textView.selectedRange().location, expected, "caret should advance by exactly one display character per step")
            XCTAssertEqual(textView.selectedRange().length, 0)
        }
    }

    // MARK: 4. Source mode round-trip

    func testToggleSourceModePreservesSelectionAndUndoState() {
        let (_, _, textView, session, adapter) = makeEditor(source: "# Title\n\nBody text.")
        assertInvariant(textView, session)

        let displayRange = NSRange(location: 2, length: 3) // inside "Title"
        textView.setSelectedRange(displayRange)
        session.selection = displayRange
        let sourceSelectionBefore = session.sourceSelection()
        let canUndoBefore = session.undoManager.canUndo

        adapter.toggleSourceMode()
        assertInvariant(textView, session)
        XCTAssertTrue(adapter.isSourceMode)

        adapter.toggleSourceMode()
        assertInvariant(textView, session)
        XCTAssertFalse(adapter.isSourceMode)

        XCTAssertEqual(session.sourceSelection(), sourceSelectionBefore)
        XCTAssertEqual(session.undoManager.canUndo, canUndoBefore)
    }

    // MARK: 5. Backspace removes a heading marker

    func testBackspaceAtHeadingStartRemovesMarker() {
        let (_, _, textView, session, _) = makeEditor(source: "# Title")
        assertInvariant(textView, session)
        XCTAssertEqual(session.presentation.displayText, "Title")

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        session.selection = NSRange(location: 0, length: 0)
        doCommand(textView, #selector(NSResponder.deleteBackward(_:)))
        assertInvariant(textView, session)
        XCTAssertEqual(session.source, "Title")
    }

    // MARK: 6. Return on an empty list item exits the list

    func testReturnOnEmptyListItemExitsList() {
        let (_, _, textView, session, _) = makeEditor(source: "- Item")
        assertInvariant(textView, session)

        // Caret at the end of "Item", then a newline starts a new (empty) item...
        textView.setSelectedRange(NSRange(location: session.presentation.displayText.utf16.count, length: 0))
        session.selection = textView.selectedRange()
        doCommand(textView, #selector(NSResponder.insertNewline(_:)))
        assertInvariant(textView, session)
        XCTAssertEqual(session.source, "- Item\n- ")

        // ...and Return again on that now-empty item exits the list.
        doCommand(textView, #selector(NSResponder.insertNewline(_:)))
        assertInvariant(textView, session)
        XCTAssertEqual(session.source, "- Item\n")
    }

    // MARK: 7. Copy vs Copy Markdown

    func testCopyMarkdownVsCopy() {
        let (_, _, textView, session, _) = makeEditor(source: "a **b** c")
        assertInvariant(textView, session)
        textView.setSelectedRange(NSRange(location: 0, length: session.presentation.displayText.utf16.count))

        textView.copyMarkdown(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "a **b** c")

        textView.copy(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "a b c")
    }

    // MARK: 8. Incomplete inline syntax stays visible

    func testIncompleteAsteriskStaysVisible() {
        let (_, _, textView, session, _) = makeEditor(source: "word word")
        assertInvariant(textView, session)

        // Place the caret in the middle of the second word and type a single "*".
        let middle = "word word".utf16.count - 2
        textView.setSelectedRange(NSRange(location: middle, length: 0))
        session.selection = NSRange(location: middle, length: 0)
        type(textView, "*")
        assertInvariant(textView, session)

        XCTAssertTrue(session.presentation.displayText.contains("*"), "an incomplete emphasis marker must stay visible in the display text")
        XCTAssertEqual(session.source, session.presentation.displayText, "no hidden runs should be introduced for an unmatched delimiter")
    }
}
#endif
