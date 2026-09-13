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

## Phase 2 (this branch)

- Shared: `FolderColor`, `FolderIcon`, `NoteListDisplayMode`; `ProjectSettings`
  gained `folderColor`, `folderIcon`, `displayMode` (persisted with the other
  folder settings). New `SidebarItemType.Home`.
- iOS: folder rows on Home use the folder color and icon; long-press a folder
  for "Folder Color" / "Folder Icon"; Folder Settings has an Appearance
  section. The notes list "…" menu gained "Sort by" and "Display as"
  (List, Compact, Cards). Craft-style onboarding carousel on first launch.
- macOS: "Home" sidebar entry with an overview canvas (Starred, Recent,
  Folders); folder selections with no open note show a card grid of the
  notes; colored/custom folder icons with context-menu pickers; breadcrumb
  title ("Folder › Title"); note inspector popover (dates, counts, tags,
  pinned, encryption, reveal in Finder).

## Phase 3 – screen-by-screen alignment (this branch)

Compared every screen of `docs/reference/contact-sheet.png` with the build.

- iOS Home: quick links without chevrons; "Starred ›", "Folders ›", "Tags ›"
  headers open full screens; starred rows show the title only; folder rows
  show note counts; Trash sits at the bottom with its count; bottom bar is
  Home / Todo / Daily Notes plus a separate "+"; "…" menu top right.
- iOS Starred, Folders and Tags screens: large titles, Craft document glyph,
  yellow star, folder path in the subtitle, Starred grouped by Today /
  Yesterday / Last 7 days / Last 30 days / year, folders with "N Items" and
  nested folder navigation, one "+" in the bottom bar.
- iOS note list: large title, search field stacked under the title (iOS 26),
  "Select" and "…", "Folder · snippet" subtitles when a list spans folders,
  star glyph for pinned notes, only "+" in the bottom bar.
- iOS editor: no navigation title, Share and "…" pill (Preview and Find moved
  into the menu), bottom bar undo/redo and new note, accessory bar led by an
  "Aa" text-style menu with a "+" insert menu (link, attachment, tag, divider).
- iOS Daily Notes: vertical timeline of days ("Sep 13  Today · Sunday"), note
  preview or "Create Daily Note" per day, "Show Previous Days", "Jump To Day".
- iOS onboarding: full-bleed illustration panel, dots, Next / Start Writing,
  close button.
- macOS: Starred documents in the sidebar; folder overview as a date-grouped
  table (Name / Updated / Created) with a grid-or-table display switcher;
  Home "Recent" uses the same table.

## Later

See [the September 13 visual audit](CRAFT_UI_AUDIT.md) for presentation fixes,
runtime verification, and differences intentionally retained in the styling pass.

- Date-grouped sections inside the UIKit notes list (Today / Yesterday / …).
  The table is single-section and its insert, remove and pin code assumes
  that, so it needs its own careful pass.
- A true multi-column grid on iPad (the current "Cards" mode is a single
  column, which matches Craft on phone).
- Colored text and highlights from the editor toolbar are out of scope: they
  have no portable Markdown representation.
- Inline "+" between paragraphs is intentionally not planned.
