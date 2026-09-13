//
//  HomeLibraryModel.swift
//  FSNotes iOS
//
//  Observable snapshot of the note library used by the Craft-style Home
//  screen. It derives everything from `Storage` and the existing `Sidebar`
//  model so the UIKit list/editor controllers stay the single source of truth.
//

import UIKit
import Observation

@MainActor
@Observable
final class HomeLibraryModel {

    struct QuickLink: Identifiable {
        var id: Int { sidebarItem.type.rawValue }
        var sidebarItem: SidebarItem
        var title: String { sidebarItem.name }
        var systemImage: String { sidebarItem.type.systemImage ?? "doc" }
    }

    struct FolderNode: Identifiable {
        var id: URL { project.url }
        var project: Project
        var depth: Int
        var isExpandable: Bool
        var isExpanded: Bool
        var noteCount: Int = 0

        var title: String { project.label }

        var systemImage: String {
            if project.isEncrypted {
                return project.isLocked() ? "lock.fill" : "lock.open.fill"
            }
            if let icon = project.settings.folderIcon, !icon.isEmpty {
                return icon
            }
            return isExpanded && isExpandable ? "folder.fill" : "folder"
        }

        var tint: UIColor? { project.settings.folderColor?.platformColor }
        var color: FolderColor? { project.settings.folderColor }
        var icon: String? { project.settings.folderIcon }
    }

    struct TagNode: Identifiable {
        var id: String { fullName }
        var fullName: String
        var name: String
        var depth: Int
        var isExpandable: Bool
        var isExpanded: Bool
    }

    struct StarredNote: Identifiable {
        var id: URL { note.url }
        var note: Note
        var title: String
        var subtitle: String
        var detail: String
    }

    var quickLinks = [QuickLink]()
    var trashLink: QuickLink?
    var trashCount = 0
    var starred = [StarredNote]()
    /// Top-level folders only (Craft's Home lists roots; nested folders live on the Folders screen).
    var folders = [FolderNode]()
    var tags = [TagNode]()
    var showsTags = UserDefaultsManagement.inlineTags
    var isLoaded = false

    /// Notes per folder URL, computed once per reload.
    private var noteCounts = [URL: Int]()
    private var availableProjects = [Project]()

    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .fsnotesLibraryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Loading

    func reload() {
        let storage = Storage.shared()
        guard storage.getDefault() != nil else { return }

        let sidebar = UIApplication.getVC().sidebarTableView?.sidebar ?? Sidebar()

        let systemItems = sidebar.items.first ?? []
        quickLinks = systemItems.filter { $0.type != .Trash }.map { QuickLink(sidebarItem: $0) }
        trashLink = systemItems.first(where: { $0.type == .Trash }).map { QuickLink(sidebarItem: $0) }

        var counts = [URL: Int]()
        var trashed = 0
        for note in storage.noteList {
            if note.isTrash() {
                trashed += 1
            } else {
                counts[note.project.url, default: 0] += 1
            }
        }
        noteCounts = counts
        trashCount = trashed

        availableProjects = storage.getAvailableProjects()
        folders = children(of: nil).map { node(for: $0, depth: 0) }
        showsTags = UserDefaultsManagement.inlineTags
        tags = showsTags ? makeTags(from: storage.noteList) : []
        starred = makeStarred(from: storage)
        isLoaded = UIApplication.getVC().isLoadedDB || !folders.isEmpty || !starred.isEmpty
    }

    // MARK: - Folder hierarchy

    /// Visible child folders of a folder (or the top-level folders when nil).
    func children(of parent: Project?) -> [Project] {
        let list: [Project]
        if let parent {
            list = availableProjects.filter { $0.parent === parent }
        } else {
            list = availableProjects.filter { project in
                guard let up = project.parent else { return true }
                return up.isDefault || !availableProjects.contains(where: { $0 === up })
            }
        }
        return list.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    func hasChildren(_ project: Project) -> Bool {
        availableProjects.contains { $0.parent === project }
    }

    /// Notes directly inside a folder plus everything nested below it.
    func noteCount(for project: Project) -> Int {
        var total = noteCounts[project.url] ?? 0
        for child in children(of: project) {
            total += noteCount(for: child)
        }
        return total
    }

    func node(for project: Project, depth: Int) -> FolderNode {
        FolderNode(
            project: project,
            depth: depth,
            isExpandable: hasChildren(project),
            isExpanded: project.isExpanded,
            noteCount: noteCount(for: project)
        )
    }

    // MARK: - Expansion

    func toggle(folder: FolderNode) {
        folder.project.isExpanded.toggle()
        Storage.shared().saveProjectsExpandState()
        UIApplication.getVC().sidebarTableView?.sidebar.reloadProjects()
        UIApplication.getVC().sidebarTableView?.reloadData()
        reload()
    }

    func toggle(tag: TagNode) {
        var expanded = Set(UserDefaultsManagement.expandedSidebarTags)
        if expanded.contains(tag.fullName) {
            expanded.remove(tag.fullName)
        } else {
            expanded.insert(tag.fullName)
        }
        UserDefaultsManagement.expandedSidebarTags = expanded.sorted()
        reload()
    }

    // MARK: - Appearance

    func setColor(_ color: FolderColor?, for folder: FolderNode) {
        folder.project.settings.folderColor = color
        folder.project.saveSettings()
        didChangeAppearance()
    }

    func setIcon(_ icon: String?, for folder: FolderNode) {
        folder.project.settings.folderIcon = (icon == FolderIcon.defaultName) ? nil : icon
        folder.project.saveSettings()
        didChangeAppearance()
    }

    private func didChangeAppearance() {
        UIApplication.getVC().sidebarTableView?.reloadData()
        reload()
        LibraryNotifier.libraryDidChange()
    }

    // MARK: - Builders

    private func makeTags(from notes: [Note]) -> [TagNode] {
        final class Node {
            var name: String
            var children = [String: Node]()
            init(name: String) { self.name = name }
        }

        let root = Node(name: "")
        var names = Set<String>()

        for note in notes where !note.isTrash() {
            for tag in note.tags {
                names.insert(tag)
            }
        }

        for name in names {
            var current = root
            for component in name.split(separator: "/").map(String.init) {
                if let next = current.children[component] {
                    current = next
                } else {
                    let next = Node(name: component)
                    current.children[component] = next
                    current = next
                }
            }
        }

        let expanded = Set(UserDefaultsManagement.expandedSidebarTags)
        var result = [TagNode]()

        func append(_ node: Node, prefix: String, depth: Int) {
            let fullName = prefix.isEmpty ? node.name : "\(prefix)/\(node.name)"
            let isExpanded = expanded.contains(fullName)
            result.append(
                TagNode(
                    fullName: fullName,
                    name: node.name,
                    depth: depth,
                    isExpandable: !node.children.isEmpty,
                    isExpanded: isExpanded
                )
            )

            guard isExpanded else { return }

            for child in node.children.values.sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }) {
                append(child, prefix: fullName, depth: depth + 1)
            }
        }

        for child in root.children.values.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }) {
            append(child, prefix: "", depth: 0)
        }

        return result
    }

    private func makeStarred(from storage: Storage) -> [StarredNote] {
        let pinned = (storage.getPinned() ?? []).filter { !$0.isTrash() }
        let sorted = storage.sortNotes(noteList: pinned)

        return sorted.map { note in
            let title = note.getTitle() ?? note.getShortTitle()
            let preview = note.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = preview.isEmpty ? note.project.getFullLabel() : preview

            return StarredNote(
                note: note,
                title: title.isEmpty ? NSLocalizedString("Untitled Note", comment: "") : title,
                subtitle: subtitle,
                detail: note.getDateForLabel()
            )
        }
    }
}
