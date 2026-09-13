//
//  SidebarItemType.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 4/7/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

enum SidebarItemType: Int {
    case Label = 0x00
    case All = 0x01
    case Trash = 0x02    
    case Todo = 0x06
    case Inbox = 0x07
    case Tag = 0x08
    case Project = 0x09
    case Header = 0x10
    case Untagged = 0x11
    case ProjectEncryptedLocked = 12
    case ProjectEncryptedUnlocked = 13
    case Separator = 14
    case Home = 15

    public var icon: String? {
        switch self {
        case .Label: return nil
        case .All: return "sidebar_notes"
        case .Trash: return "sidebar_trash"
        case .Todo: return "sidebar_todo"
        case .Inbox: return "sidebar_inbox"
        case .Tag: return "sidebar_tag"
        case .Project: return "sidebar_project"
        case .Header: return "sidebar_icloud_drive"
        case .Untagged: return "sidebar_untagged"
        case .ProjectEncryptedLocked: return "sidebar_project_encrypted_locked"
        case .ProjectEncryptedUnlocked: return "sidebar_project_encrypted_unlocked"
        case .Separator: return nil
        case .Home: return nil
        }
    }

    /// SF Symbol used by the Craft-style UI on every platform.
    public var systemImage: String? {
        switch self {
        case .Label, .Separator: return nil
        case .All: return "doc.text"
        case .Trash: return "trash"
        case .Todo: return "checklist"
        case .Inbox: return "tray"
        case .Tag: return "number"
        case .Project: return "folder"
        case .Header: return "icloud"
        case .Untagged: return "tag.slash"
        case .ProjectEncryptedLocked: return "lock.fill"
        case .ProjectEncryptedUnlocked: return "lock.open.fill"
        case .Home: return "house"
        }
    }
}
