# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FSNotes is a native notes app for macOS (AppKit) and iOS (UIKit), written in Swift 5. Notes are plain files on disk (Markdown, plain text, TextBundle, or encrypted `.etp`) — there is no database; the file system is the source of truth.

## Building

Everything builds through the Xcode project (`FSNotes.xcodeproj`; the `.xcworkspace` just wraps it). Dependencies are Swift Package Manager packages resolved automatically by Xcode/xcodebuild — there is no CocoaPods or standalone `Package.swift`.

Targets/schemes:
- `FSNotes` — macOS app (uses `FSNotes/FSNotes.entitlements`)
- `FSNotes (iCloud)` — macOS app with CloudKit/iCloud entitlements (`FSNotes (CloudKit).entitlements`); App Store variant
- `FSNotes iOS` — iOS app
- `FSNotes iOS Share Extension` — iOS share extension

```bash
# macOS build
xcodebuild -project FSNotes.xcodeproj -scheme FSNotes -configuration Debug build

# iOS build (simulator)
xcodebuild -project FSNotes.xcodeproj -scheme "FSNotes iOS" -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

There are no test targets in this project.

Linting: SwiftLint is configured via `.swiftlint.yml` and only lints `FSNotesCore/`. Run with `swiftlint`. Notable overrides: line length warning at 220, `identifier_name` and `implicit_getter` disabled, function body length 100, file length 1000.

## Architecture

### Three source layers

- **`FSNotesCore/`** — cross-platform core compiled directly into both the macOS and iOS targets (it is not a framework; files have membership in multiple targets). Platform differences are handled with `#if os(OSX)` / `#else` conditionals. Contains the domain model (`Business/`), Foundation/AppKit/UIKit extensions (`Extensions/`), and the libgit2-based Git layer (`Git/`).
- **`FSNotes/`** — macOS AppKit UI: `ViewController` (main split view), `EditorViewController`, `EditTextView`, sidebar views, preferences. Large controllers are split into feature extensions in separate files (`ViewController+Git.swift`, `EditorViewController+Sharing.swift`, `EditTextView+Todo.swift`, etc.) — follow that pattern when adding controller functionality.
- **`FSNotes iOS/`** — iOS UIKit UI, same extension-file pattern. `FSNotes iOS Share/` is the share extension.

### Domain model (FSNotesCore/Business)

- **`Storage`** — singleton (`Storage.shared()`) owning the full in-memory note list and project (folder) list. Note/project collections are guarded by recursive locks; go through its accessors rather than holding references to internal arrays.
- **`Project`** — a notes folder (root storage location, subfolder, or trash). `ProjectSettings` persists per-folder options.
- **`Note`** — one file on disk. Handles loading/saving across container types (`NoteContainer`: plain file vs `.textbundle`), encryption state, preview generation, and metadata (`NoteMeta` for cached serialization).
- **`SearchQuery`**, `Sidebar*`, `SortBy` — search/navigation state.

### Key subsystems

- **Markdown rendering pipeline**: `NotesTextProcessor` + `FSParser` (regex-based) handle in-editor syntax highlighting; code blocks use `SwiftHighlighter`. Web preview is `MPreviewView` (WKWebView) rendering via `libcmark_gfm` into the template at `Resources/MPreview.bundle` (contains the JS — MathJax, Mermaid — and CSS themes).
- **Git integration**: `FSNotesCore/Git/` wraps libgit2 (via the `swift-git`/`swift-cgit2` packages) for per-project history/backup; SSH pushes use Shout/libssh2. `FSNotes/bin/git` is a bundled git binary shipped with the macOS app.
- **External change sync**: `FSNotes/Helpers/FileSystemEventManager.swift` + `FileWatcher` watch storage directories with FSEvents so edits from other apps are picked up live.
- **Encryption**: notes are encrypted with RNCryptor (AES-256); an encrypted note becomes an `.etp` (Encrypted Text Pack) file. Keychain access goes through `KeychainConfiguration`/`KeychainPasswordItem`.
- **URL routes / web API**: `AppDelegate+URLRoutes.swift` handles the `fsnotes://` scheme; `ViewController+WebApi.swift` handles publish-to-web.

### Platform notes

- macOS deployment target 12.4 (some configs 10.14); iOS 18.0 (some configs 12.0).
- Allowed note extensions are defined in `Storage.allowedExtensions` (`md`, `markdown`, `txt`, `fountain`, `textbundle`, `etp`).
- Localization uses `.xcstrings` string catalogs plus per-language `.lproj` folders; user-facing strings should go through `NSLocalizedString`.
