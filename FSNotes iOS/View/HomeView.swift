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
                    ForEach(model.starred) { item in
                        Button {
                            actions.openNote(item.note)
                        } label: {
                            HomeNoteRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HomeSectionHeader(title: NSLocalizedString("Starred", comment: "Home section"))
                }
            }

            Section {
                if model.folders.isEmpty {
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
                            open: { actions.openFolder(folder.project) },
                            toggle: { model.toggle(folder: folder) }
                        )
                        .contextMenu {
                            Button {
                                actions.newNote(folder.project)
                            } label: {
                                Label(NSLocalizedString("New Note", comment: ""), systemImage: "square.and.pencil")
                            }
                            Button {
                                actions.folderSettings(folder.project)
                            } label: {
                                Label(NSLocalizedString("Folder Settings", comment: ""), systemImage: "gearshape")
                            }
                        }
                    }
                }
            } header: {
                HomeSectionHeader(title: NSLocalizedString("Folders", comment: "Home section"))
            }

            if model.showsTags && !model.tags.isEmpty {
                Section {
                    ForEach(model.tags) { tag in
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
                    HomeSectionHeader(title: NSLocalizedString("Tags", comment: "Home section"))
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color(uiColor: .systemBackground))
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
            .background(SwiftUI.Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("Search", comment: ""))
    }
}

struct HomeSectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.bottom, 2)
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
        .padding(.vertical, 4)
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
        .padding(.vertical, 4)
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
    var open: () -> Void
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
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
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(depth) * 24)
        .animation(.snappy, value: isExpanded)
    }
}
