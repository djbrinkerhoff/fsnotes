//
//  StarredNoteItem.swift
//  FSNotes
//
//  Craft-style "Starred" sidebar section: a pinned note rendered directly as a
//  sidebar row. The outline view's data source is `[Any]`, so this is a tiny
//  final wrapper (parallel to `SidebarItem`/`Project`/`FSTag`) that lets a
//  `Note` live in that list without touching the read-only `SidebarItem`/
//  `SidebarItemType` types.
//

import Cocoa

final class StarredNoteItem {
    let note: Note

    init(note: Note) {
        self.note = note
    }
}
