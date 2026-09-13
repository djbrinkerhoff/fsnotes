//
//  NoteListDisplayMode.swift
//  FSNotes
//
//  Craft-style "Display as" option for a folder's note list.
//

import Foundation

public enum NoteListDisplayMode: String, CaseIterable {
    case list
    case compact
    case cards

    public var title: String {
        switch self {
        case .list: return NSLocalizedString("List", comment: "Display as")
        case .compact: return NSLocalizedString("Compact", comment: "Display as")
        case .cards: return NSLocalizedString("Cards", comment: "Display as")
        }
    }

    public var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .compact: return "list.dash"
        case .cards: return "rectangle.grid.1x2"
        }
    }
}
