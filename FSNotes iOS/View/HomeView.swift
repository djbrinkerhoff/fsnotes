//
//  HomeView.swift
//  FSNotes iOS
//
//  Craft-style Home: search, quick links, Starred, Folders, Tags and Trash.
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
    var openStarred: () -> Void = {}
    var openFolders: () -> Void = {}
    var openTags: () -> Void = {}
    var openTodo: () -> Void = {}
}

struct HomeView: View {
    @Bindable var model: HomeLibraryModel
    var actions: HomeActions

    var body: some View {
        List {
            searchSection
            quickLinksSection
            starredSection
            foldersSection
            tagsSection
            trashSection
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("Home", comment: "Home screen title"))
        .tint(SwiftUI.Color(uiColor: .label))
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    actions.settings()
                } label: {
                    Label(NSLocalizedString("Settings", comment: ""), systemImage: "gearshape")
                }
                Button {
                    actions.newNote(nil)
                } label: {
                    Label(NSLocalizedString("New Note", comment: ""), systemImage: "square.and.pencil")
                }
            } label: {
                Label(NSLocalizedString("More", comment: ""), systemImage: "ellipsis")
            }
        }

        ToolbarItemGroup(placement: .bottomBar) {
            Toggle(NSLocalizedString("Home", comment: ""), systemImage: "house", isOn: .constant(true))
                .toggleStyle(.button)
                .tint(.blue)
                .labelStyle(.iconOnly)
            Button(NSLocalizedString("Todo", comment: ""), systemImage: "checkmark.square") {
                actions.openTodo()
            }
            .labelStyle(.iconOnly)
            Button(NSLocalizedString("Daily Notes", comment: ""), systemImage: "calendar") {
                actions.dailyNote()
            }
            .labelStyle(.iconOnly)
        }

        if #available(iOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
        } else {
            ToolbarItem(placement: .bottomBar) { Spacer() }
        }

        ToolbarItem(placement: .bottomBar) {
            Button(NSLocalizedString("New Note", comment: ""), systemImage: "plus") {
                actions.newNote(nil)
            }
            .fontWeight(.semibold)
            .labelStyle(.iconOnly)
        }
    }

    private var searchSection: some View {
        Section {
            HomeSearchRow(action: actions.search)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
        }
        .listRowBackground(SwiftUI.Color.clear)
        .listSectionSeparator(.hidden)
    }

    private var quickLinksSection: some View {
            Section {
                ForEach(model.quickLinks) { link in
                    Button {
                        actions.openSidebarItem(link.sidebarItem)
                    } label: {
                        HomeRow(title: link.title, systemImage: link.systemImage, iconStyle: .quickLink, showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(SwiftUI.Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var starredSection: some View {
            if !model.starred.isEmpty {
                Section {
                    HomeSectionHeader(title: NSLocalizedString("Starred", comment: "Home section"), action: actions.openStarred)
                        .listRowSeparator(.hidden)
                    ForEach(model.starred) { item in
                        Button {
                            actions.openNote(item.note)
                        } label: {
                            HomeRow(title: item.title, systemImage: item.note.isEncrypted() ? "lock.doc" : "doc.text", iconStyle: .document, showsChevron: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(SwiftUI.Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listSectionSeparator(.hidden)
            }
    }

    private var foldersSection: some View {
            Section {
                HomeSectionHeader(title: NSLocalizedString("Folders", comment: "Home section"), action: actions.openFolders)
                    .listRowSeparator(.hidden)
                if model.folders.isEmpty {
                    Text(model.isLoaded
                         ? NSLocalizedString("No folders yet", comment: "Home empty state")
                         : NSLocalizedString("Loading…", comment: "Home loading state"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(model.folders) { folder in
                        Button {
                            actions.openFolder(folder.project)
                        } label: {
                            HomeRow(
                                title: folder.title,
                                systemImage: folder.systemImage,
                                iconStyle: .folder,
                                tint: folder.tint.map { SwiftUI.Color(uiColor: $0) },
                                count: folder.noteCount,
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
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
            }
            .listRowBackground(SwiftUI.Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var tagsSection: some View {
            if model.showsTags && !model.tags.isEmpty {
                Section {
                    HomeSectionHeader(title: NSLocalizedString("Tags", comment: "Home section"), action: actions.openTags)
                        .listRowSeparator(.hidden)
                    ForEach(model.tags.filter { $0.depth == 0 }) { tag in
                        Button {
                            actions.openTag(tag.fullName)
                        } label: {
                            HomeRow(title: tag.name, systemImage: "number", iconStyle: .tag, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(SwiftUI.Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listSectionSeparator(.hidden)
            }
    }

    @ViewBuilder
    private var trashSection: some View {
            if let trash = model.trashLink {
                Section {
                    Button {
                        actions.openSidebarItem(trash.sidebarItem)
                    } label: {
                        HomeRow(title: trash.title, systemImage: trash.systemImage, iconStyle: .tag, count: model.trashCount, showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(SwiftUI.Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listSectionSeparator(.hidden)
            }
    }
}

// MARK: - Rows

enum HomeIconStyle {
    case quickLink
    case document
    case folder
    case tag

    var foreground: AnyShapeStyle {
        switch self {
        case .quickLink: return AnyShapeStyle(.secondary)
        case .document: return AnyShapeStyle(.secondary)
        case .folder: return AnyShapeStyle(SwiftUI.Color(uiColor: .systemBlue))
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
                Text(NSLocalizedString("Search", comment: ""))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(SwiftUI.Color(uiColor: .tertiarySystemFill), in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("Search", comment: ""))
    }
}

/// Craft-style section header: the title is a link to the full screen ("Starred ›").
struct HomeSectionHeader: View {
    var title: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SwiftUI.Color(uiColor: .label))
                if action != nil {
                    SwiftUI.Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .textCase(nil)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(title)
        .accessibilityHint(action == nil ? "" : NSLocalizedString("Opens the full list", comment: "Home accessibility"))
    }
}

struct HomeRow: View {
    var title: String
    var systemImage: String
    var iconStyle: HomeIconStyle
    var tint: SwiftUI.Color? = nil
    var count: Int? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if iconStyle == .document && systemImage == "doc.text" {
                    DocumentGlyph(width: 18, height: 24)
                } else {
                    SwiftUI.Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? iconStyle.foreground)
                }
            }
            .frame(width: 24, height: 28)
            .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            if showsChevron {
                SwiftUI.Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Row with a disclosure control, used by the Tags screen for nested tags.
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
                    ? NSLocalizedString("Collapse", comment: "Sidebar accessibility")
                    : NSLocalizedString("Expand", comment: "Sidebar accessibility"))
            } else {
                SwiftUI.Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
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
