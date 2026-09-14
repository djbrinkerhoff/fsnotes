# ADR 0002: Parser choice

Date: 2026-09-14
Status: Accepted

## Context

The brief asks to evaluate `swift-markdown` first and to avoid an ad hoc regular-expression grammar.
The editor needs, on every keystroke, exact UTF-16 ranges for every delimiter (open and close
separately), for block markers per physical line, for task markers, and lossless behaviour on
incomplete syntax. `libcmark_gfm` is already a dependency for HTML preview.

## Evaluation

- `swift-markdown` exposes `SourceRange` per node in line/column form (UTF-8 columns) but not the
  ranges of individual delimiters; decoded node text is not a lossless source slice; it drops
  unmatched delimiters silently in the tree; adding it also requires network access to resolve the
  package, which the build environment used for this work did not have. Marked "not adopted".
- `libcmark_gfm` yields byte offsets per node at line granularity, no delimiter ranges, and its
  extensions run in C; the same range gaps apply.
- A focused line-based block parser plus the CommonMark delimiter-run algorithm for inlines
  (`CommonMarkLineParser`) gives exact ranges by construction, is pure Swift, and parses 1 MB in
  tens of milliseconds. It intentionally supports CommonMark + GFM task lists, strikethrough,
  autolinks and tables (block only), plus FSNotes' wiki links and `#tags`.

## Decision

Use `CommonMarkLineParser` behind the `MarkdownParser` protocol. Unsupported constructs are left
as paragraph text, so their source survives round trips. Reference definitions affect distant
links, and fences affect later blocks; because every transaction reparses the whole document these
dependencies are always consistent. Incremental reparse is an optimization to add behind the same
protocol if measurements demand it.
