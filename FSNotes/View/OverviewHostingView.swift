//
//  OverviewHostingView.swift
//  FSNotes
//
//  AppKit-facing wrapper around the SwiftUI overview canvas. Kept usable on the
//  project's 10.14 deployment target: everything SwiftUI-specific is created
//  lazily behind an `#available(macOS 12, *)` check, so on older systems this
//  simply behaves like an inert, always-hidden NSView.
//

import Cocoa
import SwiftUI

final class OverviewHostingView: NSView {

    // Type-erased so the stored property itself has no availability requirement.
    private var boxedModel: AnyObject?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        guard #available(macOS 12, *) else { return }

        let model = OverviewModel()
        boxedModel = model

        let hosting = NSHostingView(rootView: OverviewView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(macOS 12, *)
    private var model: OverviewModel? {
        boxedModel as? OverviewModel
    }

    /// Wires up card-click callbacks. Safe to call once, right after creation.
    public func configure(onSelectNote: @escaping (Note) -> Void, onSelectProject: @escaping (Project) -> Void) {
        guard #available(macOS 12, *), let model = model else { return }

        model.onSelectNote = onSelectNote
        model.onSelectProject = onSelectProject
    }

    public func showHome(pinned: [OverviewNoteItemInput], recent: [OverviewNoteItemInput], folders: [OverviewFolderItemInput]) {
        guard #available(macOS 12, *), let model = model else { return }

        model.pinnedNotes = pinned.map { $0.makeItem() }
        model.recentNotes = recent.map { $0.makeItem() }
        model.folders = folders.map { $0.makeItem() }
        model.mode = .home

        isHidden = false
    }

    public func showFolder(
        title: String,
        notes: [OverviewNoteItemInput],
        displayMode: NoteListDisplayMode,
        showsFolderPath: Bool,
        onDisplayModeChange: @escaping (NoteListDisplayMode) -> Void
    ) {
        guard #available(macOS 12, *), let model = model else { return }

        model.folderTitle = title
        model.folderNotes = notes.map { $0.makeItem() }
        model.displayMode = displayMode
        model.showsFolderPath = showsFolderPath
        model.onDisplayModeChange = onDisplayModeChange
        model.mode = .folder

        isHidden = false
    }

    public func hide() {
        isHidden = true

        guard #available(macOS 12, *), let model = model else { return }
        model.mode = .hidden
    }
}

/// Plain-old-data description of a note card, built by `ViewController` (which
/// has no availability constraint) and turned into a `@available` SwiftUI model
/// type only inside this file.
struct OverviewNoteItemInput {
    let note: Note
    let title: String
    let preview: String
    let dateLabel: String
    let isPinned: Bool

    @available(macOS 12, *)
    func makeItem() -> OverviewNoteItem {
        OverviewNoteItem(
            id: note.url.path,
            title: title,
            preview: preview,
            dateLabel: dateLabel,
            isPinned: isPinned,
            note: note
        )
    }
}

struct OverviewFolderItemInput {
    let project: Project
    let title: String
    let noteCount: Int
    let tintColor: NSColor
    let iconName: String

    @available(macOS 12, *)
    func makeItem() -> OverviewFolderItem {
        OverviewFolderItem(
            id: project.url.path,
            title: title,
            noteCount: noteCount,
            tintColor: tintColor,
            iconName: iconName,
            project: project
        )
    }
}
