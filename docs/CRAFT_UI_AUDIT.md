# Craft reference review — September 13, 2026

Reference: [contact sheet](reference/contact-sheet.png), including the 25 phone
screens, three onboarding panels, and seven Mac images. The requested filename
`craft-contact-sheet.png` is not present; `contact-sheet.png` is the existing asset.

Scope: align presentation of existing FSNotes capabilities. Preserve Markdown
files, storage, synchronization, editor commands, and existing navigation actions.

## Differences corrected

| Area | Difference found | Change |
| --- | --- | --- |
| iOS Home | White canvas, oversized title, rectangular search, faint headers, loose rows, disabled-looking Home control | Semantic pale library background, smaller scalable title, capsule search, explicit section-heading rows, tighter row insets, selected Home styling |
| Starred / Folders / Tags | Heavy row titles, extra section rules, folder chevrons absent from the reference, oversized page glyphs | Regular-weight titles, quieter separators, smaller page glyphs, folder count grammar, consistent library background and bottom-bar plus |
| Starred hint | Explanatory card disappeared as soon as notes were pinned | Keep the explanatory card above the populated list, as in the reference |
| UIKit notes list | Previous captures showed notes beneath the status bar with the title/search missing | Identify the content scroll view, restore automatic safe-area handling, prepare and retain the search controller before navigation, keep search beneath the title |
| UIKit note rows | Tiny outline icons against the screen edge and bold titles | Inset page-shaped icons and aligned regular-weight title/preview columns; retain existing dates and image previews; scale plain/compact row heights with text |
| Editor chrome | Cyan custom buttons, duplicate circle around More, inconsistent compose icon | Native labeled Share, More, Undo, Redo, and plus items with neutral toolbar tint |
| Editor accessory bar | Ten fixed controls required horizontal scrolling on phones | Move the existing numbered-list and indentation commands into Aa; keep the visible toolbar within phone width and retain all existing actions |
| Daily Notes | Today's date, relative label, and weekday competed on one line | Stack today's date above “Today · weekday”; allow other date headings to reflow; use quiet, accessible day menus |
| Onboarding | Unrelated large symbols and multicolor panels; dots below the explanatory text | Blue illustrated panels showing existing note, folder-color, and tag features; dots above the title; capsule primary action; scrolling content for larger text |
| Mac sidebar | Accent-colored navigation symbols, uppercase headings, strong selection fill | Neutral symbols, sentence-case headings, adjusted row spacing, subtle selection that preserves custom folder colors |
| Mac overview | Dense bold rows, no row separators, right-aligned date columns | Regular titles, 56-point rows, subtle rules, aligned date columns, current sort indicator, and full-width content |
| Mac display control / cards | Custom unlabeled switcher; inconsistent star glyph and card heights | Native accessible segmented picker, yellow stars, uniform note-card height |

## Reference differences retained

- Home's Folders/Tags headings still appeared lighter than the reference in the
  final simulator capture despite explicit headline/label styling. The headings
  remain working navigation links; this visual difference is not marked verified.
- FSNotes uses notes, folders, inline tags and Markdown task lists. Craft's
  Connections, Shared with Me, account/workspace controls, AI, and notification
  controls have no matching UI behavior here.
- Craft's quick-capture sheets, task scheduling/filtering, calendar integrations,
  and calendar settings require capabilities outside this styling pass. Existing
  note creation and Daily Notes navigation are retained.
- Craft's per-document covers, paper/backdrop, colors, rich block decorations,
  block selection handles, and format inspector do not map directly to the
  existing Markdown editor. Its native formatting menus remain in place.
- Document glyphs are illustrative rather than rendered snapshots of each note.
- Starred and Mac overview lists already group by date. The legacy UIKit notes
  table retains its existing single-section sorting, pinning, and bulk-selection
  behavior; the Folders screen retains its existing hierarchy and alphabetic order.
  Converting these collection behaviors is a separate change.
- Dedicated Starred and Folders search, bulk-select, sort, and statistics controls
  from Craft were not added. FSNotes' existing notes-list search, Select, and
  folder settings are preserved.
- Mac overview retains the existing Name / Updated / Created metadata and grid
  options. No Last Viewed tracking, extra tab system, or new task/calendar view
  was introduced.
- Inline plus controls between paragraphs remain explicitly excluded.

## Validation

- iOS app and its share extension build using the installed 26.2 SDK; the
  installed simulator runtime is iOS 26.3.
- Mac target builds with the installed 26.2 SDK.
- iPhone runtime checks cover Home, Folders, Daily Notes, list title/search,
  existing Select mode, editor navigation, keyboard toolbar and Aa menu, and all
  onboarding pages.
- Mac code changes were reviewed against the reference crops. Mac runtime
  screenshots could not be obtained because app capture timed out.
- Bitrig build/simulator tools were unavailable in this session. Validation used
  the existing Xcode build configuration and simulator, with computer-use tools
  for screen observation and interaction. No temporary UI navigation hooks were
  added to app code.
