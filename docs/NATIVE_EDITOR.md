# Native Markdown Editor

The native editor is a TextKit 2, hidden-syntax Markdown editor that replaces the legacy
live-preview `EditTextView` when the **Native Markdown Editor** preference is on. Markdown files
stay the only source of truth; the editor never writes a proprietary format.

Design records: `docs/adr/0001-hidden-syntax-representation.md`, `docs/adr/0002-parser.md`.

## Turning it on

- macOS: **View ▸ Native Markdown Editor**. **View ▸ Show Markdown Source** (⌥⌘U) toggles source mode.
  **Edit ▸ Copy Markdown** (⌥⌘C) copies the Markdown for the selection; plain Copy copies visible text.
- iOS: **Settings ▸ Editor ▸ Native Markdown Editor (Beta)**. In the editor, the **Aa** menu gains
  **Markdown Source**; the edit menu gains **Copy Markdown**. Tab / Shift-Tab on a hardware keyboard
  indent and outdent list items.

The preference is stored in `UserDefaultsManagement.useNativeMarkdownEditor`. Turning it off
restores the legacy editor with no migration; both editors read and write the same files.

## Building and testing

```
# Package (core, adapters, tests)
cd Packages/MarkdownEditor
swift build
swift test                                   # 128 tests
swift test -c release --filter BenchmarkTests  # prints BENCH lines

# Apps
xcodebuild -project FSNotes.xcodeproj -scheme "FSNotes" -destination 'platform=macOS' build
xcodebuild -project FSNotes.xcodeproj -scheme "FSNotes iOS" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Where things live

| Brief module | Repository component |
| --- | --- |
| `MarkdownEditorCore` | `Packages/MarkdownEditor/Sources/MarkdownEditorCore`: `SourceDocument`, `SourceEdit`, `EditorSession` (+Commands), `MarkdownParser` / `CommonMarkLineParser`, `MarkdownSyntaxTree`, `PresentationBuilder`, `SourceDisplayMap`, `TextDiff`, `EditorTheme`, `MarkdownFileCodec` |
| `MarkdownEditorTextKit` | `Sources/MarkdownEditorTextKit`: `ResolvedTheme`, `EditorPalette`, `AttributeBuilder`, `BlockDecoration` attribute |
| `MarkdownEditorAppKit` | `Sources/MarkdownEditorAppKit`: `MarkdownTextView` (NSTextView, TextKit 2), `MarkdownLayoutFragment`, `AppKitEditorAdapter`, task accessibility elements |
| `MarkdownEditorUIKit` | `Sources/MarkdownEditorUIKit`: `MarkdownTextView` (UITextView, TextKit 2), `MarkdownLayoutFragment`, `UIKitEditorAdapter`, `CheckboxAccessibilityOverlay` |
| `MarkdownEditorSwiftUI` | `Sources/MarkdownEditorSwiftUI/MarkdownEditorView` (`NSViewRepresentable` / `UIViewRepresentable`) |
| `MarkdownLibrary` | Existing `FSNotesCore/Business/{Storage,Note,Project}.swift`, `FSNotes/Helpers/FileSystemEventManager.swift`, `FSNotes iOS/Helpers/CloudDriveManager.swift`, hardened in place |
| App integration | `FSNotes/View/NativeEditorHost.swift`, `FSNotes iOS/View/NativeEditorHost.swift`, hooks in `EditTextView.fill` (macOS) and `EditorViewController.fill` (iOS) |

## Requirement status

| Requirement | Status | Evidence |
| --- | --- | --- |
| P0.1 `.md` source of truth | Passed | `Note.loadSource` / `Note.save(source:)`; no derived document format |
| P0.2 Constructs | Passed (styling); tables/HTML kept as dimmed source | `ParserTests`, `PresentationBuilderTests` |
| P0.3 `# ` enters H1 immediately | Passed | `EditorSessionTests.testTypingHashSpaceMakesHeadingWithHiddenMarker`, `AppKitEditorTests` scenario 1 |
| P0.4 Markers hidden, explicit source mode | Passed | source mode toggle in View menu / Aa menu; `testSourceModeToggleKeepsSelectionAndUndo` |
| P0.5 Inline delimiters hidden, incomplete syntax visible | Passed | `testHiddenDelimitersAndInsertionAtBoundaries`, `testIncompleteSyntaxStaysVisible`; boundary rules in ADR 0001 |
| P0.6 Interactive tasks, one undo, selection preserved | Passed (mouse, keyboard/VoiceOver via accessibility elements) | `testToggleTaskIsOneUndoStepAndKeepsSelection`, AppKit scenario 2; touch path unverified at runtime |
| P0.7 Return / Tab / Backspace | Passed | `testReturnContinuesAndExitsLists`, `testIndentOutdent`, `testBackspaceAt…` |
| P0.8 Native selection, undo, clipboard, spelling, accessibility | Passed on macOS offscreen; iOS unverified at runtime | AppKit scenario 3 (no hidden caret stops) |
| P0.9 Shared theme, light/dark, Dynamic Type | Passed | `EditorTheme` + `ResolvedTheme`; iOS re-themes on content size change |
| P0.10 Byte fidelity (BOM, CRLF) | Passed | `MarkdownFileCodecTests` round-trip every fixture; CRLF edit test |
| P0.11 Source toggle keeps selection/undo; Copy vs Copy Markdown | Passed | `testSourceModeToggle…`, `testMarkdownForDisplayRange`, AppKit scenario 7 |
| Library: picker, bookmarks, listing, create | Passed (pre-existing) | unchanged FSNotes behaviour |
| Library: coordinated writes, debounce, flush | Passed | `Note.write(data:)` under `NSFileCoordinator`; `scheduleSave` 0.6 s debounce; flush on switch, background, resign active, terminate |
| Library: clean reload vs dirty conflict | Implemented, unverified at runtime | `FileSystemEventManager` / `CloudDriveManager` post `fsnotesNoteDidReloadExternally` / `fsnotesNoteConflictDetected`; hosts reload or alert |
| Library: per-document undo isolation | Passed | sessions use `Note.undoManager`; iOS `EditTextView.undoManager` override |

## Benchmark report

Hardware: Apple Silicon Mac (host of this session), macOS 15 SDK 26.2 toolchain Swift 6.2.4,
`swift test -c release`, 20 to 50 samples per scenario, fixture = `Fixtures/mixed.md` repeated.
No physical iPhone was available; iOS numbers are **unverified**.

| Scenario | Target | Measured (release, Mac) | Verdict |
| --- | --- | --- | --- |
| Open 100 KB note to editable presentation | ≤ 500 ms | 12 ms (8,846 lines) | Passed |
| Typing in 100 KB mixed note, editor-owned sync work | p95 ≤ 8 ms | p95 12.8 ms (parse 7.0, present 3.8, diff 1.4) | **Failed** (see below) |
| 1 MB note + 2,000 tasks + 100 KB unbroken paragraph + 40-level list | no crash, no lost edit, report latency | p50 143 ms, p95 152 ms per keystroke; task toggle 154 ms; no crash, edit verified | Reported |
| Parse 1 MB (26,567 lines) | well under 100 ms | 47 ms | Passed |
| Repeated document switching | bounded | 50 sessions created and released, no retention (`testRepeatedDocumentSwitchingDoesNotLeak`) | Passed |
| Continuous scrolling frame timing | no stalls > 50 ms | not measured (no UI harness) | Unverified |

The 100 KB typing target is missed because every transaction reparses and re-presents the whole
document. The dominant cost is the parser (55%), then the presentation builder (30%). The
architecture keeps both behind protocols (`MarkdownParser`, `PresentationBuilding`); the next
step is block-level reuse of unaffected top-level blocks between revisions. Thresholds were not
changed to make this pass.

## Tested matrix

- macOS 15 host, Xcode 26.3, `FSNotes` scheme: builds; 8 offscreen NSTextView scenarios pass.
- iOS 26.3 simulator (iPhone 17 Pro): `FSNotes iOS` builds. No runtime interaction test was run
  (the simulator automation bridge was unavailable in this session).
- No physical devices.

## Known limitations

- Images render as styled alt text; inline image attachments, code syntax highlighting inside the
  native editor, and editable tables are P1 and not implemented. The legacy editor still handles them.
- IME composition, dictation and autocorrect are reconciled by diffing after the native view commits
  (see ADR 0001). This path is unit-tested (`testReconcileNativeEdit`) but not exercised with a real
  Japanese or Chinese keyboard.
- Wiki-link and tag completion popovers of the legacy editor are not wired into the native editor.
- Font and margin preference changes apply when a note is (re)opened, not live.
- A numbered task item (`1. [ ]`) shows a checkbox and drops the number in the margin.
