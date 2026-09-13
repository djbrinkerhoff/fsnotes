//
//  HomeView.swift
//  FSNotes iOS
//
//  Craft-style Home: search, quick links, starred notes, folders and tags.
//

import SwiftUI

struct HomeActions {
    var search: () -> Void = {}
    var openSidebarItem: (SidebarItem) -> Void = { _ in }
    var openFolder: (Project) -> Void = { _ in }
    var openTag: (String) -> Void = { _ in }
    var openNote: (Note) -> Void = { _ in }
    var newNote: (Project?) -> Void = { _ in }
    var folderSettings: (Project) -> Void = { _ in }
    var dailyNote: () -> Void = {}
    var settings: () -> Void = {}
}

struct HomeView: View {
    @Bindable var model: HomeLibraryModel
    var actions: HomeActions

    var body: some View {
        List {
            Section {
                HomeSearchRow(action: actions.search)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
            }

            Section {
                ForEach(model.quickLinks) { link in
                    Button {
                        actions.openSidebarItem(link.sidebarItem)
                    } label: {
                        HomeRow(
                            title: link.title,
                            systemImage: link.systemImage,
                            iconStyle: .accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !model.starred.isEmpty {
                Section {
                    if !model.isCollapsed(.starred) {
                        ForEach(model.starred) { item in
                            Button {
                                actions.openNote(item.note)
                            } label: {
                                HomeNoteRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HomeSectionHeader(
                        title: NSLocalizedString("Starred", comment: "Home section"),
                        count: model.starred.count,
                        isCollapsed: model.isCollapsed(.starred)
                    ) {
                        model.toggle(section: .starred)
                    }
                }
            }

            Section {
                if model.isCollapsed(.folders) {
                    EmptyView()
                } else if model.folders.isEmpty {
                    Text(model.isLoaded
                         ? NSLocalizedString("No folders yet", comment: "Home empty state")
                         : NSLocalizedString("Loading…", comment: "Home loading state"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(model.folders) { folder in
                        HomeOutlineRow(
                            title: folder.title,
                            systemImage: folder.systemImage,
                            depth: folder.depth,
                            isExpandable: folder.isExpandable,
                            isExpanded: folder.isExpanded,
                            iconStyle: .folder,
                            tint: folder.tint.map { SwiftUI.Color(uiColor: $0) },
                            open: { actions.openFolder(folder.project) },
                            toggle: { model.toggle(folder: folder) }
                        )
                        .id(folder.id)
                        .contextMenu {
                            Button {
                                actions.newNote(folder.project)
                            } label: {
                                Label(NSLocalizedString("New Note", comment: ""), systemImage: "square.and.pencil")
                            }

                            FolderColorMenu(selected: folder.color) { color in
                                model.setColor(color, for: folder)
                            }

                            FolderIconMenu(selected: folder.icon) { icon in
                                model.setIcon(icon, for: folder)
                            }

                            Divider()

                            Button {
                                actions.folderSettings(folder.project)
                            } label: {
                                Label(NSLocalizedString("Folder Settings", comment: ""), systemImage: "gearshape")
                            }
                        }
                    }
                }
            } header: {
                HomeSectionHeader(
                    title: NSLocalizedString("Folders", comment: "Home section"),
                    count: model.folders.filter { $0.depth == 0 }.count,
                    isCollapsed: model.isCollapsed(.folders)
                ) {
                    model.toggle(section: .folders)
                }
            }

            if model.showsTags && !model.tags.isEmpty {
                Section {
                    ForEach(model.isCollapsed(.tags) ? [] : model.tags) { tag in
                        HomeOutlineRow(
                            title: tag.name,
                            systemImage: "number",
                            depth: tag.depth,
                            isExpandable: tag.isExpandable,
                            isExpanded: tag.isExpanded,
                            iconStyle: .tag,
                            open: { actions.openTag(tag.fullName) },
                            toggle: { model.toggle(tag: tag) }
                        )
                    }
                } header: {
                    HomeSectionHeader(
                        title: NSLocalizedString("Tags", comment: "Home section"),
                        count: model.tags.filter { $0.depth == 0 }.count,
                        isCollapsed: model.isCollapsed(.tags)
                    ) {
                        model.toggle(section: .tags)
                    }
                }
            }
        }
        .animation(.snappy, value: model.collapsedSections)
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color(uiColor: .systemBackground))
        .navigationTitle(NSLocalizedString("Home", comment: "Home screen title"))
        .tint(SwiftUI.Color(uiColor: .mainTheme))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(NSLocalizedString("Settings", comment: ""), systemImage: "gearshape") {
                    actions.settings()
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Button(NSLocalizedString("Daily Note", comment: ""), systemImage: "calendar") {
                    actions.dailyNote()
                }
                Spacer()
                Button(NSLocalizedString("Search", comment: ""), systemImage: "magnifyingglass") {
                    actions.search()
                }
                Spacer()
                Button(NSLocalizedString("New Note", comment: ""), systemImage: "square.and.pencil") {
                    actions.newNote(nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Rows

enum HomeIconStyle {
    case accent
    case folder
    case tag

    var foreground: AnyShapeStyle {
        switch self {
        case .accent: return AnyShapeStyle(.tint)
        case .folder: return AnyShapeStyle(SwiftUI.Color(uiColor: .systemBlue).opacity(0.9))
        case .tag: return AnyShapeStyle(.secondary)
        }
    }
}

struct HomeSearchRow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("Search or create", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(SwiftUI.Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("Search", comment: ""))
    }
}

struct HomeSectionHeader: View {
    var title: String
    var count: Int? = nil
    var isCollapsed: Bool = false
    var toggle: (() -> Void)? = nil

    var body: some View {
        Button {
            toggle?()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                if toggle != nil {
                    SwiftUI.Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                Spacer(minLength: 0)
            }
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(toggle == nil)
        .accessibilityLabel(title)
        .accessibilityHint(toggle == nil ? "" : (isCollapsed
            ? NSLocalizedString("Expands the section", comment: "Home accessibility")
            : NSLocalizedString("Collapses the section", comment: "Home accessibility")))
    }
}

struct HomeRow: View {
    var title: String
    var systemImage: String
    var iconStyle: HomeIconStyle

    var body: some View {
        HStack(spacing: 12) {
            SwiftUI.Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(iconStyle.foreground)
                .frame(width: 28, height: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            SwiftUI.Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct HomeNoteRow: View {
    var item: HomeLibraryModel.StarredNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SwiftUI.Image(systemName: item.note.isEncrypted() ? "lock.doc" : "doc.text")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(item.detail)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct HomeOutlineRow: View {
    var title: String
    var systemImage: String
    var depth: Int
    var isExpandable: Bool
    var isExpanded: Bool
    var iconStyle: HomeIconStyle
    var tint: SwiftUI.Color? = nil
    var open: () -> Void
    var toggle: () -> Void

    private var iconForeground: AnyShapeStyle {
        if let tint { return AnyShapeStyle(tint) }
        return iconStyle.foreground
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    SwiftUI.Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(iconForeground)
                        .frame(width: 28, height: 28)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpandable {
                Button(action: toggle) {
                    SwiftUI.Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded
                    ? NSLocalizedString("Collapse folder", comment: "Sidebar accessibility")
                    : NSLocalizedString("Expand folder", comment: "Sidebar accessibility"))
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, CGFloat(depth) * 24)
        .animation(.snappy, value: isExpanded)
    }
}

// MARK: - Folder appearance menus

struct FolderColorMenu: View {
    var selected: FolderColor?
    var onSelect: (FolderColor?) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                Label(NSLocalizedString("None", comment: "Folder color"), systemImage: selected == nil ? "checkmark.circle" : "circle")
            }

            ForEach(FolderColor.allCases, id: \.rawValue) { color in
                Button {
                    onSelect(color)
                } label: {
                    Label {
                        Text(color.title)
                    } icon: {
                        SwiftUI.Image(systemName: selected == color ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(SwiftUI.Color(uiColor: color.platformColor))
                    }
                }
            }
        } label: {
            Label(NSLocalizedString("Folder Color", comment: ""), systemImage: "paintpalette")
        }
    }
}

struct FolderIconMenu: View {
    var selected: String?
    var onSelect: (String?) -> Void

    var body: some View {
        Menu {
            ForEach(FolderIcon.choices, id: \.self) { name in
                Button {
                    onSelect(name)
                } label: {
                    Label {
                        Text(name == FolderIcon.defaultName
                             ? NSLocalizedString("Default", comment: "Folder icon")
                             : name.replacingOccurrences(of: ".", with: " ").capitalized)
                        if (selected ?? FolderIcon.defaultName) == name {
                            SwiftUI.Image(systemName: "checkmark")
                        }
                    } icon: {
                        SwiftUI.Image(systemName: name)
                    }
                }
            }
        } label: {
            Label(NSLocalizedString("Folder Icon", comment: ""), systemImage: "square.grid.2x2")
        }
    }
}
