# Craft-style UI refactor plan

Goal: keep FSNotes' file-based core (Markdown/TextBundle files, folders, tags,
iCloud Drive, git, encryption, Spotlight, share extension) and reshape the
interface, interaction design and navigation structure after Craft Docs.
Anything about AI assistants or AI search in the reference screenshots is out
of scope.

## Structure mapping (Craft → FSNotes)

| Craft                        | FSNotes                                   |
|------------------------------|-------------------------------------------|
| Home                         | New root screen (iOS), sidebar root (Mac) |
| All Docs                     | Notes (`SidebarItemType.All`)             |
| Starred                      | Pinned notes                              |
| Folders (nested, colored)    | Projects tree (`Project.child`)           |
| Tags                         | Inline `#tags` (`FSTag` tree)             |
| Unsorted                     | Inbox (default project)                   |
| Daily note ("Sep 13")        | Note named after today's date in Inbox    |
| Document                     | Note (Markdown file)                      |
| Block "+" menu               | Markdown insert menu in editor accessory  |
| Sort by / Display as         | Existing sort settings + list style menu  |

## Phase 1 – iOS navigation and Home (this branch)

- New SwiftUI **Home** screen is the navigation root: search field, quick
  links (Notes, Inbox, Todo, Untagged, Trash), **Starred** (pinned notes),
  **Folders** (collapsible tree) and **Tags**.
- Bottom bar: Home, Daily note, New note, Settings.
- Tapping a folder/tag/quick link pushes the existing notes list controller
  with that selection; tapping a starred note opens the editor directly.
- The old slide-in sidebar stays in code but is hidden. All library data
  still flows through `Storage`, `Sidebar`, `SidebarTableView` and
  `NotesTableView`; Home observes `Notification.Name.fsnotesLibraryDidChange`.
- Notes list rows restyled as Craft document rows (document icon, title,
  snippet, date). "Select" and the "…" menu stay in the navigation bar.
- Editor keyboard accessory redesigned: leading "+" insert-block menu
  (heading, to-do, lists, quote, code, link, attachment), inline formatting,
  indent, undo/redo, dismiss keyboard. Wider content insets.

## Phase 1 – macOS

- Sidebar uses SF Symbols, section headers ("Folders", "Tags") instead of
  blank separators, rounded row selection and taller rows.
- Notes list rows: title / snippet / date hierarchy tuned to Craft.
- Editor content column: centered line width by default.

## Phase 2 (next)

- iOS: grid ("Display as") option for the notes list, per-folder colors and
  icons stored in `ProjectSettings`, Craft-style onboarding carousel.
- macOS: Home page in the content area (Starred + recent), folder view as a
  card grid, breadcrumb title bar, inspector panel for note metadata.
- Both: block-style paragraph handles and inline "+" between paragraphs on
  top of the Markdown text storage.
