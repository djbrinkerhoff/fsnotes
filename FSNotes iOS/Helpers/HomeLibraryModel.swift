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

        var title: String { project.label }

        var systemImage: String {
            if project.isEncrypted {
                return project.isLocked() ? "lock.fill" : "lock.open.fill"
            }
            return isExpanded && isExpandable ? "folder.fill" : "folder"
        }
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
    var starred = [StarredNote]()
    var folders = [FolderNode]()
    var tags = [TagNode]()
    var showsTags = UserDefaultsManagement.inlineTags
    var isLoaded = false

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

        quickLinks = (sidebar.items.first ?? []).map { QuickLink(sidebarItem: $0) }
        folders = makeFolders(from: storage.getAvailableProjects())
        showsTags = UserDefaultsManagement.inlineTags
        tags = showsTags ? makeTags(from: storage.noteList) : []
        starred = makeStarred(from: storage)
        isLoaded = UIApplication.getVC().isLoadedDB || !folders.isEmpty || !starred.isEmpty
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

    // MARK: - Builders

    private func makeFolders(from projects: [Project]) -> [FolderNode] {
        var visited = Set<URL>()
        var result = [FolderNode]()

        func sorted(_ list: [Project]) -> [Project] {
            list.sorted {
                $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
        }

        func append(_ project: Project, depth: Int) {
            guard !visited.contains(project.url) else { return }
            visited.insert(project.url)

            let children = sorted(projects.filter { $0.parent === project })
            result.append(
                FolderNode(
                    project: project,
                    depth: depth,
                    isExpandable: !children.isEmpty,
                    isExpanded: project.isExpanded
                )
            )

            if project.isExpanded {
                children.forEach { append($0, depth: depth + 1) }
            }
        }

        let roots = projects.filter { project in
            guard let parent = project.parent else { return true }
            return parent.isDefault || !projects.contains(where: { $0 === parent })
        }

        sorted(roots).forEach { append($0, depth: 0) }

        return result
    }

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
