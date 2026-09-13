//
//  Sidebar.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 4/7/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa
typealias Image = NSImage

class Sidebar {
    var list = [Any]()
    let storage = Storage.shared()
    public var items = [[SidebarItem]]()
    
    init() {
        guard let defaultURL = Storage.shared().getDefault()?.url else { return }

        var system = [SidebarItem]()

        // Craft-style overview landing row, always first.
        system.append(SidebarItem(name: NSLocalizedString("Home", comment: "Sidebar"), type: .Home))

        if UserDefaultsManagement.sidebarVisibilityNotes {
            // Notes
            guard let defaultURL = Storage.shared().getDefault()?.url else { return }
            
            let notesUrl = defaultURL.appendingPathComponent("Fake Virtual Notes Dir")
            let notesLabel = NSLocalizedString("Notes", comment: "")
            let fakeNotesProject =
                Project(
                    storage: Storage.shared(),
                    url: notesUrl,
                    label: notesLabel,
                    isVirtual: true
                )

            let notes = SidebarItem(name: NSLocalizedString("Notes", comment: ""), project: fakeNotesProject, type: .All)
            system.append(notes)

            Storage.shared().allNotesProject = fakeNotesProject
        }

        if UserDefaultsManagement.sidebarVisibilityInbox {
            let project = Storage.shared().getDefault()
            let notes = SidebarItem(name: NSLocalizedString("Inbox", comment: ""), project: project, type: .Inbox)
            system.append(notes)
        }

        if UserDefaultsManagement.sidebarVisibilityTodo {
            let todoUrl = defaultURL.appendingPathComponent("Fake Virtual Todo Dir")
            let todoLabel = NSLocalizedString("Todo", comment: "")
            let fakeTodoProject =
                Project(
                    storage: Storage.shared(),
                    url: todoUrl,
                    label: todoLabel,
                    isVirtual: true
                )
            
            let todo =
                SidebarItem(name: NSLocalizedString("Todo", comment: ""), project: fakeTodoProject, type: .Todo)
            system.append(todo)

            Storage.shared().todoProject = fakeTodoProject
        }

        if UserDefaultsManagement.sidebarVisibilityUntagged {
            let todoUrl = defaultURL.appendingPathComponent("Fake Virtual Utagged Dir")
            let untaggedLabel = NSLocalizedString("Untagged", comment: "")
            let fakeUntaggedProject =
                Project(
                    storage: Storage.shared(),
                    url: todoUrl,
                    label: untaggedLabel,
                    isVirtual: true
                )

            let todo = SidebarItem(name: NSLocalizedString("Untagged", comment: ""), project: fakeUntaggedProject, type: .Untagged)
            system.append(todo)

            Storage.shared().untaggedProject = fakeUntaggedProject
        }

        if UserDefaultsManagement.sidebarVisibilityTrash {
            let trashProject = Storage.shared().getDefaultTrash()
            let trash = SidebarItem(name: NSLocalizedString("Trash", comment: ""), project: trashProject, type: .Trash)
            system.append(trash)
        }

        if system.count > 0 {
            list = system
        }

        // Craft-style "Starred" section: newest-modified pinned notes first,
        // capped at 12. Hidden entirely when nothing is pinned.
        let pinnedNotes = (storage.getPinned() ?? []).sorted { $0.modifiedLocalAt > $1.modifiedLocalAt }
        if !pinnedNotes.isEmpty {
            list.append(SidebarItem(name: "starred", type: .Separator))

            for note in pinnedNotes.prefix(12) {
                list.append(StarredNoteItem(note: note))
            }
        }

        list.append(SidebarItem(name: "projects", type: .Separator))

        let projects = storage.getSidebarProjects()
        if projects.count > 0 {
            for project in projects {
                list.append(project)
            }
        }

        list.append(SidebarItem(name: "tags", type: .Separator))
    }
    
    public func getList() -> [Any] {
        return list
    }

    private func getDefaultLabelName(project: Project) -> String {
        var name = project.label

        let iCloudPath = "/Users/\(NSUserName())/Library/Mobile Documents"
        if project.url.path.starts(with: iCloudPath) {
            name = NSLocalizedString("iCloud Drive", comment: "")
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
        if let path = documentsPath, project.url.path.starts(with: path) {
            name = NSLocalizedString("Documents", comment: "")
        }

        return name
    }
}
