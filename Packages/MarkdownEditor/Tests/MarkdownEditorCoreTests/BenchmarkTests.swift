import XCTest
@testable import MarkdownEditorCore

/// Stress and latency scenarios from the brief. Run with `swift test -c release --filter BenchmarkTests`
/// and read the printed numbers; the assertions are loose sanity bounds so debug runs also pass.
@MainActor
final class BenchmarkTests: XCTestCase {

    private func fixture(_ name: String) -> String {
        try! String(contentsOf: Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures")!)
    }

    private func repeated(_ text: String, toAtLeast bytes: Int) -> String {
        var out = ""
        out.reserveCapacity(bytes + text.utf8.count)
        while out.utf8.count < bytes { out += text; out += "\n" }
        return out
    }

    private func percentile(_ samples: [Double], _ p: Double) -> Double {
        let sorted = samples.sorted()
        return sorted[Int(Double(sorted.count - 1) * p)]
    }

    func testOpen100KB() {
        let text = repeated(fixture("mixed"), toAtLeast: 100_000)
        let clock = ContinuousClock()
        let start = clock.now
        let session = EditorSession(source: text, parser: CommonMarkLineParser(), builder: PresentationBuilder())
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("BENCH open 100KB: \(ms) ms, lines=\(session.presentation.lines.count)")
        XCTAssertLessThan(ms, 2000)
    }

    func testTyping1MBAnd2000Tasks() {
        var text = repeated(fixture("mixed"), toAtLeast: 1_000_000)
        text += "\n" + (0..<2000).map { "- [ ] Task number \($0)" }.joined(separator: "\n") + "\n"
        text += "\n" + String(repeating: "long unbroken paragraph word ", count: 4000) + "\n"
        text += (0..<40).map { String(repeating: "  ", count: $0) + "- level \($0)" }.joined(separator: "\n")
        let session = EditorSession(source: text, parser: CommonMarkLineParser(), builder: PresentationBuilder())
        let taskLineIndex = session.presentation.lines.lastIndex { if case .task = $0.block.listMarker ?? .bullet { return $0.block.listMarker != nil } else { return false } }!
        var samples: [Double] = []
        session.selection = NSRange(location: 100, length: 0)
        for i in 0..<20 {
            session.replaceDisplay(range: session.selection, with: i % 5 == 4 ? " " : "a")
            samples.append(session.lastMetrics.total * 1000)
        }
        let toggleStart = ContinuousClock.now
        XCTAssertTrue(session.toggleTask(atDisplayLine: taskLineIndex))
        let toggleMs = Double((ContinuousClock.now - toggleStart).components.attoseconds) / 1e15
        print("BENCH 1MB typing p50=\(percentile(samples, 0.5)) ms p95=\(percentile(samples, 0.95)) ms; task toggle \(toggleMs) ms; parse=\(session.lastMetrics.parse * 1000) present=\(session.lastMetrics.present * 1000) diff=\(session.lastMetrics.diff * 1000)")
        XCTAssertTrue(session.source.contains("- [x] Task number 1999"))
        XCTAssertEqual(session.presentation.displayText.utf16.count, session.presentation.map.displayLength)
    }

    func testTyping100KBLatency() {
        let text = repeated(fixture("mixed"), toAtLeast: 100_000)
        let session = EditorSession(source: text, parser: CommonMarkLineParser(), builder: PresentationBuilder())
        session.selection = NSRange(location: 60, length: 0)
        var samples: [Double] = []
        for i in 0..<50 {
            session.replaceDisplay(range: session.selection, with: i % 6 == 5 ? " " : "b")
            samples.append(session.lastMetrics.total * 1000)
        }
        print("BENCH 100KB typing p50=\(percentile(samples, 0.5)) ms p95=\(percentile(samples, 0.95)) ms (parse \(session.lastMetrics.parse * 1000), present \(session.lastMetrics.present * 1000), diff \(session.lastMetrics.diff * 1000))")
        XCTAssertLessThan(percentile(samples, 0.95), 500)
    }

    func testRepeatedDocumentSwitchingDoesNotLeak() {
        weak var weakSession: EditorSession?
        autoreleasepool {
            for _ in 0..<50 {
                let session = EditorSession(source: fixture("mixed"), parser: CommonMarkLineParser(), builder: PresentationBuilder())
                session.replaceDisplay(range: NSRange(location: 0, length: 0), with: "x")
                weakSession = session
            }
        }
        XCTAssertNil(weakSession, "sessions must not be retained after switching")
    }
}
