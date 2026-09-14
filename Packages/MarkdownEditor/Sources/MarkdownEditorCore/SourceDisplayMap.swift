import Foundation

/// How a hidden source run behaves for caret placement and range mapping.
public enum HiddenRunAttachment: Sendable, Equatable {
    /// Attaches to the display text that follows it (opening delimiters, block markers).
    /// A caret at the run's display position is placed after the run.
    case leading
    /// Attaches to the display text that precedes it (closing delimiters, `\r` in CRLF).
    /// A caret at the run's display position is placed before the run.
    case trailing
}

/// Bidirectional map between source (Markdown) and display (presentation) UTF-16 offsets.
///
/// The display text is the source text with `runs` removed. Runs never overlap and are sorted.
/// Every run maps to zero display characters.
public struct SourceDisplayMap: Sendable, Equatable {
    public struct Run: Sendable, Equatable {
        public var sourceRange: NSRange
        public var attachment: HiddenRunAttachment

        public init(sourceRange: NSRange, attachment: HiddenRunAttachment) {
            self.sourceRange = sourceRange
            self.attachment = attachment
        }
    }

    public private(set) var runs: [Run]
    /// displayPosition[i] = display offset at which runs[i] collapses.
    private var displayPositions: [Int]
    /// deltaBefore[i] = total hidden source length of runs before runs[i].
    private var deltaBefore: [Int]
    public let sourceLength: Int
    public let displayLength: Int

    public static func identity(sourceLength: Int) -> SourceDisplayMap {
        SourceDisplayMap(sourceLength: sourceLength, runs: [])
    }

    public init(sourceLength: Int, runs: [Run]) {
        let sorted = runs.filter { $0.sourceRange.length > 0 }.sorted { $0.sourceRange.location < $1.sourceRange.location }
        var positions: [Int] = []
        var deltas: [Int] = []
        positions.reserveCapacity(sorted.count)
        deltas.reserveCapacity(sorted.count)
        var delta = 0
        var lastEnd = 0
        for run in sorted {
            precondition(run.sourceRange.location >= lastEnd, "Hidden runs must not overlap")
            precondition(NSMaxRange(run.sourceRange) <= sourceLength, "Hidden run out of bounds")
            deltas.append(delta)
            positions.append(run.sourceRange.location - delta)
            delta += run.sourceRange.length
            lastEnd = NSMaxRange(run.sourceRange)
        }
        self.runs = sorted
        self.displayPositions = positions
        self.deltaBefore = deltas
        self.sourceLength = sourceLength
        self.displayLength = sourceLength - delta
    }

    // MARK: Source -> display

    /// Index of the last run whose source location is <= `source`, or nil.
    private func runIndex(atOrBeforeSource source: Int) -> Int? {
        var low = 0, high = runs.count - 1, result: Int? = nil
        while low <= high {
            let mid = (low + high) / 2
            if runs[mid].sourceRange.location <= source { result = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return result
    }

    public func displayOffset(forSource source: Int) -> Int {
        let s = max(0, min(source, sourceLength))
        guard let i = runIndex(atOrBeforeSource: s) else { return s }
        let run = runs[i]
        if s < NSMaxRange(run.sourceRange) { return displayPositions[i] }
        return s - deltaBefore[i] - run.sourceRange.length
    }

    public func displayRange(forSource range: NSRange) -> NSRange {
        let start = displayOffset(forSource: range.location)
        let end = displayOffset(forSource: NSMaxRange(range))
        return NSRange(location: start, length: max(0, end - start))
    }

    // MARK: Display -> source

    /// Index of the first run whose display position is >= `display`.
    private func firstRunIndex(atOrAfterDisplay display: Int) -> Int {
        var low = 0, high = runs.count
        while low < high {
            let mid = (low + high) / 2
            if displayPositions[mid] < display { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Source offset for a collapsed caret at `display`.
    /// Leading runs at that position are skipped; the caret stops before the first trailing run.
    public func sourceOffset(forDisplay display: Int) -> Int {
        let d = max(0, min(display, displayLength))
        var i = firstRunIndex(atOrAfterDisplay: d)
        var base = d + (i < runs.count ? deltaBefore[i] : (sourceLength - displayLength))
        // Skip leading runs that collapse exactly at d.
        while i < runs.count, displayPositions[i] == d {
            if runs[i].attachment == .leading {
                base += runs[i].sourceRange.length
                i += 1
            } else {
                break
            }
        }
        return base
    }

    /// Smallest source offset that maps to `display` (before every run collapsing there).
    public func minimumSourceOffset(forDisplay display: Int) -> Int {
        let d = max(0, min(display, displayLength))
        let i = firstRunIndex(atOrAfterDisplay: d)
        if i < runs.count { return d + deltaBefore[i] }
        return d + (sourceLength - displayLength)
    }

    /// Largest source offset that maps to `display` (after every run collapsing there).
    public func maximumSourceOffset(forDisplay display: Int) -> Int {
        let d = max(0, min(display, displayLength))
        var i = firstRunIndex(atOrAfterDisplay: d)
        var base = minimumSourceOffset(forDisplay: d)
        while i < runs.count, displayPositions[i] == d {
            base += runs[i].sourceRange.length
            i += 1
        }
        return base
    }

    /// Source range for a display range. Leading runs at the start are included when the range
    /// has content after them; trailing runs at the end are included when the range has content before them.
    /// A collapsed range maps to the collapsed insertion point.
    public func sourceRange(forDisplay range: NSRange) -> NSRange {
        if range.length == 0 {
            let s = sourceOffset(forDisplay: range.location)
            return NSRange(location: s, length: 0)
        }
        let startD = max(0, min(range.location, displayLength))
        let endD = max(0, min(NSMaxRange(range), displayLength))
        // Start: include leading runs at startD (attach to following selected content), exclude trailing runs.
        var start = minimumSourceOffset(forDisplay: startD)
        var i = firstRunIndex(atOrAfterDisplay: startD)
        while i < runs.count, displayPositions[i] == startD, runs[i].attachment == .trailing {
            start += runs[i].sourceRange.length
            i += 1
        }
        // End: include everything strictly inside, plus trailing runs at endD, excluding leading runs at endD.
        var end = minimumSourceOffset(forDisplay: endD)
        var j = firstRunIndex(atOrAfterDisplay: endD)
        while j < runs.count, displayPositions[j] == endD, runs[j].attachment == .trailing {
            end += runs[j].sourceRange.length
            j += 1
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Hidden runs whose display position lies within `displayRange` (inclusive of both ends).
    public func runs(touchingDisplay displayRange: NSRange) -> [Run] {
        let start = firstRunIndex(atOrAfterDisplay: displayRange.location)
        var result: [Run] = []
        var i = start
        while i < runs.count, displayPositions[i] <= NSMaxRange(displayRange) {
            result.append(runs[i])
            i += 1
        }
        return result
    }
}
