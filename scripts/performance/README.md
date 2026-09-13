# FSNotes performance harness

`run-performance.sh` compiles a temporary Swift executable from the current production implementations of:

- `HomeLibraryModel.reload()` and its folder hierarchy helpers (`children`, `hasChildren`, `noteCount`, and `node`)
- `DailyNotesModel.reload()` and the `previous` getter
- the exact macOS `groupedByDate` implementation from `OverviewView.swift`

The executable uses small in-memory stand-ins for `Storage`, `Note`, `Project`, UIKit and sidebar objects. This avoids disk, Core Data and UI startup noise while retaining the production model algorithms. The source is extracted at run time, so the harness follows later edits to those implementations.

Each fixture uses 5 or 5,000 notes, 2 or 250 nested folders, three tags per note, approximately 1 KB of preview text, five percent pinned notes, two percent trash notes and ten percent daily-note filenames. The folder fixtures are deliberately a single parent-child chain, which exposes recursive subtree costs; they do not represent a balanced production tree. Each operation gets three warmups and fifteen timed samples using Swift `ContinuousClock`; output reports milliseconds, median, p95 and a checksum. The harness also measures repeated access to the cached overview groups.

Before emitting timings, independent assertions verify trash exclusion, pinned-note counts, root and per-folder subtree totals, daily-date counts, previous-day counts, grouped item counts, fixed `now` boundaries across a Chicago DST transition, and cache invalidation after note-array replacement.

Run from the repository root:

```sh
scripts/performance/run-performance.sh > /tmp/fsnotes-performance.json
```

The checked-in `docs/performance-baseline.json` records one run used for the audit. The command emits a document with the same metadata wrapper and retains all fifteen raw samples per metric. Timing varies by machine and build toolchain; correctness fields should remain stable and catch fixture or extraction mistakes.
