# Performance audit — September 13, 2026

Audited the Craft navigation branch with a small library, then a synthetic
5,000-note library. Four fixes were implemented by lower-cost agents, reviewed,
built, and measured again.

## Checks and results

The checks cover library loading, Home/folder queries, Daily Notes, and Mac date
grouping. Timings below are medians; smaller is better.

### Running iPhone app

iPhone 17 Pro simulator, iOS 26.3 runtime, built with the installed iOS 26.2 SDK,
Debug configuration. The 5,000-note fixture has 100 leaf folders under 10 parent
folders, approximately 1 KB per Markdown file, three tags per note, and 500
daily filenames. These disk files are unpinned and non-trash.

| App-reported phase | 5 notes before | 5,000 notes before | 5,000 notes after |
| --- | ---: | ---: | ---: |
| Folder discovery/relations | 6.18 ms | 345.61 ms | 327.74 ms |
| Note loading | 3.52 ms | 5,587.62 ms | 773.17 ms |
| Note diff/content validation | 3.33 ms | 2,069.52 ms | 2,025.43 ms |
| Full content loading | 1.19 ms | 1,086.71 ms | 1,071.97 ms |
| Spotlight preparation/submission | 22.76 ms | 146.03 ms | 143.53 ms |

Note loading improved by **86.2% (7.2× faster)**. The other loading phases were
not targeted; their small differences should be treated as run-to-run variation.
These are the existing `loadDB()` phase timers, not end-to-end launch, time to
first frame, or completion of asynchronous Spotlight indexing.

There are two retained small-library samples and three samples per large-library
version. Every retained large sample reports exactly 5,000 notes loaded from disk.
The app was relaunched between samples; filesystem caches were warm, and this
does not represent a physical-device cold launch. Raw phase samples are in
[performance-simulator.json](performance-simulator.json).

### Production-model benchmarks

Optimized Swift executable on the host Mac, using the current production model
implementations with in-memory storage/note/sidebar stand-ins. Three warmups and
15 measured samples use `ContinuousClock`. The large model fixture includes
5% pinned and 2% trashed notes; date grouping processes 4,900 non-trash notes.

| Operation | 5 notes / 2 folders before | 5,000 notes / 250 folders before | 5,000 notes / 250 folders after |
| --- | ---: | ---: | ---: |
| Home reload | 0.023 ms | 2.151 ms | 1.780 ms |
| All folder node queries | 0.002 ms | 110.472 ms | 0.023 ms |
| Daily Notes reload | 0.100 ms | 69.521 ms | 11.260 ms |
| Previous daily notes getter | 0.002 ms | 1.241 ms | 0.003 ms |
| Mac date grouping | 0.014 ms | 105.759 ms | 1.943 ms |

The 250 folders form a **single deeply nested chain**, deliberately stressing
recursive folder queries. It is not the simulator's shallower folder layout.
The harness also measures both library sizes with two folders to distinguish
note-count costs from folder-depth costs. Cached Mac group access measured
0.007 ms for the large fixture. Small-library Home reload increased from 0.023 ms
to 0.037 ms due to index construction; the absolute overhead is about 0.014 ms.

These measure model algorithms, not rendering, file I/O, or production title/date
formatting: those dependencies are stubs. The Mac lazy-row improvement is built
and reviewed but has no measured frame-rate claim. Full summaries, p95 values,
and final raw sample arrays are in [performance-baseline.json](performance-baseline.json)
and [performance-after.json](performance-after.json).

## Implemented changes

1. **Batch project insertion.** `Storage.add([Note])` builds a temporary
   `(name, project URL)` duplicate index under the existing lock. `Project.loadNotes()`
   uses it instead of scanning the growing library for every note. Empty batches
   skip index creation. This preserves insertion order, case sensitivity,
   cross-folder names, duplicate logging, and URL-based project equality.
2. **Index folder relationships/counts.** `HomeLibraryModel` builds sorted child
   lists, roots, and subtree counts once per reload. Repeated folder queries use
   indexed lookups. Default and hidden parents retain their previous behavior.
3. **Reduce Daily Notes parsing/sorting.** Gate filenames by ASCII `yyyy-MM-dd`
   shape, parse strictly in the Gregorian calendar with the current time zone,
   reuse the formatter, and sort date keys only on reload. Invalid dates are
   excluded; pagination uses the cached order and the current day.
4. **Cache Mac date groups and load rows lazily.** Compute calendar boundaries
   once per grouping pass, refresh cached groups when arrays change or a day/time
   zone notification arrives, and use lazy stacks for groups and rows. The
   existing bucket cutoffs, sorting, and presentation are retained.

## Validation and remaining limits

- iOS app/share extension and Mac app builds passed using the 26.2 SDKs.
- Production-model regression checks cover subtree counts, trash/starred
  exclusion, date boundaries across daylight saving time, group-cache assignment,
  malformed filenames, leap dates, duplicate daily notes, pagination, and reload
  replacement. Batch insertion is compared with the former sequential behavior.
- Simulator checks passed for Home counts, a 500-note parent folder, its 50-note
  children, note-list navigation, a matching search result, today's daily note,
  and showing previous days. Search latency and scroll FPS were not instrumented.
- One idle sample after the large baseline loaded showed 0% CPU and about 451 MiB
  process RSS. This is a simulator snapshot, includes shared/resident pages, and
  is neither a peak-memory nor a memory-regression measurement.
- The default child-directory discovery limit is 200 (the loop currently permits
  one extra directory). The original 250-leaf-folder disk fixture loaded only
  3,640 notes. Those samples were excluded, and the fixture was repacked into
  100 leaf folders. The existing discovery limit was not changed.
- Diff/content loading still takes several seconds at 5,000 notes. Further work
  should profile that path, image-heavy/TextBundle libraries, search latency,
  scrolling hitches, peak memory, and physical-device cold launches.

## Reproduction

```sh
scripts/performance/run-performance.sh > /tmp/fsnotes-performance.json
swift scripts/test-batch-insertion.swift
swift scripts/make-performance-library.swift /tmp/new-fsnotes-library 5000
```

The fixture generator requires a new output directory and refuses overwrites.
Use an isolated simulator's app Documents directory, never a real notes library.
The audit's separate simulator is named `FSNotes Performance Audit`; the completed
5,000-note fixture remains installed there. The five-note fixture and rejected
over-limit fixture were retained outside its active Documents folder.

Bitrig's simulator/build connector was not exposed to this session. Builds used
the existing project configuration through `xcodebuild`, loading measurements used
`simctl --console-pty`, and UI verification used the Simulator app. No project
settings, user libraries, or Bitrig simulator libraries were changed.
