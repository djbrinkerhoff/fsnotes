//
//  ViewController+Home.swift
//  FSNotes iOS
//
//  Entry points used by the Craft-style Home screen. The list controller is
//  no longer the navigation root, so these helpers push it on demand and
//  drive the (hidden) sidebar table so all existing selection, search and
//  note-list logic keeps working unchanged.
//

import UIKit

extension ViewController {

    /// Whether the app uses the Craft-style Home screen as its root instead of
    /// the legacy slide-in sidebar.
    static let usesHomeNavigation = true

    // MARK: - Navigation

    /// Makes the notes list the visible controller, pushing it if needed.
    public func presentNotesList(animated: Bool = true) {
        guard let nav = UIApplication.getNC() else { return }

        if nav.viewControllers.contains(self) {
            if nav.topViewController !== self {
                nav.popToViewController(self, animated: animated)
            }
            return
        }

        nav.pushViewController(self, animated: animated)
    }

    /// Opens the notes list for a system item (Notes, Inbox, Todo, Untagged, Trash) or folder.
    public func showLibrary(item: SidebarItem) {
        if let project = item.project, item.type == .Project
            || item.type == .ProjectEncryptedLocked
            || item.type == .ProjectEncryptedUnlocked {
            showLibrary(project: project)
            return
        }

        loadViewIfNeeded()

        if let indexPath = sidebarTableView.getIndexPathBy(type: item.type) {
            sidebarTableView.tableView(sidebarTableView, didSelectRowAt: indexPath)
        }

        presentNotesList()
    }

    /// Opens the notes list for a folder, expanding collapsed parents so the
    /// sidebar row exists.
    public func showLibrary(project: Project) {
        loadViewIfNeeded()

        var parent = project.parent
        var didExpand = false
        while let current = parent, !current.isDefault {
            if !current.isExpanded {
                current.isExpanded = true
                didExpand = true
            }
            parent = current.parent
        }

        if didExpand {
            Storage.shared().saveProjectsExpandState()
            sidebarTableView.sidebar.reloadProjects()
            sidebarTableView.reloadData()
        }

        if let indexPath = sidebarTableView.getIndexPathBy(project: project) {
            sidebarTableView.tableView(sidebarTableView, didSelectRowAt: indexPath)
        }

        presentNotesList()
    }

    /// Opens the notes list filtered by an inline tag across all notes.
    public func showLibrary(tag: String) {
        loadViewIfNeeded()

        guard let allPath = sidebarTableView.getIndexPathBy(type: .All)
                ?? sidebarTableView.getIndexPathBy(type: .Inbox) else {
            presentNotesList()
            return
        }

        // Select the "Notes" row silently so the query covers every folder.
        sidebarTableView.deselectAll()
        sidebarTableView.selectRow(at: allPath, animated: false, scrollPosition: .none)

        // Make sure nested tag rows are reachable.
        let components = tag.split(separator: "/").map(String.init)
        if components.count > 1 {
            var expanded = Set(UserDefaultsManagement.expandedSidebarTags)
            var prefix = ""
            for component in components.dropLast() {
                prefix = prefix.isEmpty ? component : "\(prefix)/\(component)"
                expanded.insert(prefix)
            }
            UserDefaultsManagement.expandedSidebarTags = expanded.sorted()
        }

        sidebarTableView.insert(tags: [tag])

        if let tagPath = sidebarTableView.getIndexPathBy(tag: tag) {
            sidebarTableView.tableView(sidebarTableView, didSelectRowAt: tagPath)
        } else {
            sidebarTableView.tableView(sidebarTableView, didSelectRowAt: allPath)
        }

        presentNotesList()
    }

    /// Pushes the notes list and focuses the search field.
    public func showSearchFromHome() {
        loadViewIfNeeded()

        if sidebarTableView.indexPathForSelectedRow == nil,
           let allPath = sidebarTableView.getIndexPathBy(type: .All)
                ?? sidebarTableView.getIndexPathBy(type: .Inbox) {
            sidebarTableView.tableView(sidebarTableView, didSelectRowAt: allPath)
        }

        enableSearchFocus()
        presentNotesList()
    }

    // MARK: - Notes

    /// Opens a note directly from Home (starred list).
    public func openFromHome(note: Note) {
        loadViewIfNeeded()

        if note.isEncrypted() && !note.isUnlocked() {
            unLock(notes: [note]) { unlocked in
                guard let unlocked = unlocked, !unlocked.isEmpty else { return }
                DispatchQueue.main.async {
                    UIApplication.getEVC().load(note: note)
                }
            }
            return
        }

        UIApplication.getEVC().load(note: note)
    }

    /// Creates a note in the given folder (or the current/default one).
    public func createNoteFromHome(in project: Project?) {
        loadViewIfNeeded()

        if let project = project {
            if project.isEncrypted, project.password == nil {
                unlockProject(selectedProject: project, createNote: true)
                return
            }

            if let indexPath = sidebarTableView.getIndexPathBy(project: project) {
                sidebarTableView.tableView(sidebarTableView, didSelectRowAt: indexPath)
            }
        }

        newButtonAction()
    }

    /// Opens (or creates) today's daily note in the Inbox, Craft style.
    public func openDailyNote() {
        loadViewIfNeeded()

        guard let inbox = storage.getDefault() else { return }

        let fileFormatter = DateFormatter()
        fileFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = fileFormatter.string(from: Date())

        if let existing = storage.getBy(fileName: fileName)
            ?? storage.noteList.first(where: { $0.fileName == fileName && !$0.isTrash() }) {
            UIApplication.getEVC().load(note: existing)
            return
        }

        let titleFormatter = DateFormatter()
        titleFormatter.dateStyle = .full
        titleFormatter.timeStyle = .none
        let heading = titleFormatter.string(from: Date())

        let note = Note(name: fileName, project: inbox)
        note.content = NSMutableAttributedString(string: "# \(heading)\n\n")

        if note.save() {
            Storage.shared().add(note)
        }

        if isActiveTableUpdating {
            notesTable.reloadData()
        } else {
            notesTable.insertRows(notes: [note])
        }

        let evc = UIApplication.getEVC()
        evc.note = note
        evc.fill(note: note, selectedRange: NSRange(location: note.content.length, length: 0))
        openEditorViewController()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            evc.editArea.becomeFirstResponder()
        }

        LibraryNotifier.libraryDidChange()
    }

    /// Opens the folder settings screen for a project.
    public func openFolderSettingsFromHome(project: Project) {
        loadViewIfNeeded()

        let item = sidebarTableView.getSidebarItem(project: project)
            ?? SidebarItem(name: project.label, project: project, type: .Project)

        presentNotesList(animated: false)
        openProjectSettings(sidebarItem: item)
    }
}
