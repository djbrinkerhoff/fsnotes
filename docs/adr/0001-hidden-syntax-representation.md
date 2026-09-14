# ADR 0001: Hidden-syntax representation for the native Markdown editor

Date: 2026-09-14
Status: Accepted

## Context

The brief requires Markdown syntax to be hidden during ordinary editing (headings without `#`,
emphasis without `**`, tasks as checkboxes) while plain `.md` files stay the source of truth,
native selection and undo keep working, and cursor movement has no invisible stops.

The legacy FSNotes editor keeps Markdown in the text storage and colors markers gray. Its dormant
`hideSyntax` flag shrinks markers to a 0.1pt font. That approach was rejected before prototyping
because it demonstrably leaves caret stops on zero-width text, keeps layout width for spaces
inside markers, confuses VoiceOver, and cannot express task markers as controls.

Two candidates from the brief were evaluated with the same heading, emphasis and task fixtures:

1. Source in native text storage, presentation suppression plus custom selection/navigation.
2. Source in the core, an editable presentation buffer without delimiters, and a bidirectional
   source/display map.

## Decision

Option 2. `EditorSession` (MarkdownEditorCore) owns the canonical source string, a monotonically
increasing revision, the parse tree, the presentation and the undo stack. The text view shows the
*display text* = source minus hidden runs. `SourceDisplayMap` converts offsets and ranges in both
directions in O(log n).

Rules that make boundaries predictable:

- Hidden runs are `leading` (block markers, opening delimiters, escapes) or `trailing`
  (closing delimiters, `\r` of CRLF, hard-break markers).
- A collapsed caret at a display position sits after all leading runs and before the first trailing
  run at that position. Consequences: typing at the visible start of a heading goes after `# `,
  typing at either edge of a bold word extends the bold span, typing at end of line goes before `\r\n`.
- A selection includes a leading run only when it has visible content after it, and a trailing run
  only when it has visible content before it. Deleting a whole bold word therefore deletes its
  delimiters; deleting text adjacent to a bold word does not touch them.
- Incomplete syntax is not recognized by the parser and so stays visible; recognized syntax
  collapses immediately on the keystroke that completes it.
- Backspace at the visible start of a line that has hidden leading markers removes the innermost
  marker (heading, list, task or quote) instead of joining lines.

All edits, whether typed into the display buffer or issued as commands, become `SourceEdit`
transactions. Native undo is disabled for typing (`allowsUndo = false` on macOS; the UIKit view
returns the session's `UndoManager`) and the session registers inverse transactions itself, so undo
is source-based and survives source-mode toggles. Continuous typing and backward deletions coalesce.

Native input that bypasses the delegate (IME commit, dictation, autocorrect on iOS) is reconciled
by diffing the view's text against the last presentation (`TextDiff`) and applying the difference
as a transaction. Marked-text regions are never transformed while composition is active.

Block markers of lists, tasks and quotes are hidden too; bullets, numbers, checkboxes and quote
rules are drawn in the paragraph margin by a custom `NSTextLayoutFragment`. Checkboxes are hit-tested
in the margin and exposed as accessibility elements, so they never occupy a character position.
Wiki-link brackets and code fences stay visible (dimmed) so completion and fence editing keep working.

## Consequences

- One parse and presentation rebuild per transaction. The line-based parser and builder are
  linear; the adapter reapplies attributes only to lines whose style signature changed.
- Source mode is the same pipeline with an identity map and `syntax` style runs, so toggling
  preserves selection and undo.
- Copy defaults to visible text; Copy Markdown maps the display selection back to source.
- Attachments for images are deferred (P1); image syntax renders as styled alt text for now.
