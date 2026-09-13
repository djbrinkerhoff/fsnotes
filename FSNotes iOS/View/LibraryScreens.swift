//
//  LibraryScreens.swift
//  FSNotes iOS
//
//  Craft-style full-screen lists reached from the Home section headers:
//  Starred (date-grouped), Folders (hierarchical) and Tags.
//

import SwiftUI
import UIKit

// MARK: - Shared chrome

/// Craft's list screens keep a single "+" in the bottom bar.
struct LibraryBottomBar: ViewModifier {
    var newNote: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .bottomBar)
            } else {
                ToolbarItem(placement: .bottomBar) { Spacer() }
            }
            ToolbarItem(placement: .bottomBar) {
                Button(NSLocalizedString("New Note", comment: ""), systemImage: "plus") {
                    newNote()
                }
                .fontWeight(.semibold)
                .labelStyle(.iconOnly)
            }
        }
    }
}

extension View {
    func libraryBottomBar(newNote: @escaping () -> Void) -> some View {
        modifier(LibraryBottomBar(newNote: newNote))
    }
}

// MARK: - Starred

struct StarredScreen: View {
    @Bindable var model: HomeLibraryModel
    var open: (Note) -> Void
    var newNote: () -> Void = { UIApplication.getVC().createNoteFromHome(in: nil) }

    private var groups: [(DateBucket, [HomeLibraryModel.StarredNote])] {
        let grouped = Dictionary(grouping: model.starred) { DateBucket.bucket(for: $0.note.modifiedLocalAt) }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                LibraryHint(text: NSLocalizedString("Pin notes you want to find quickly. Pinned notes show up here and on Home.", comment: "Starred empty state"))
            }
            .listRowBackground(SwiftUI.Color.clear)
            .listSectionSeparator(.hidden)

            ForEach(groups, id: \.0) { bucket, items in
                Section {
                    ForEach(items) { item in
                        Button {
                            open(item.note)
                        } label: {
                            LibraryNoteRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    LibraryGroupHeader(title: bucket.title)
                }
                .listRowBackground(SwiftUI.Color.clear)
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("Starred", comment: ""))
        .tint(SwiftUI.Color(uiColor: .label))
        .libraryBottomBar(newNote: newNote)
    }
}

struct LibraryNoteRow: View {
    var item: HomeLibraryModel.StarredNote

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            DocumentGlyph()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if item.note.isPinned {
                        SwiftUI.Image(systemName: "star.fill")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                    }
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "folder")
                        .font(.caption)
                    Text(item.note.project.getFullLabel())
                    if !item.subtitle.isEmpty && item.subtitle != item.note.project.getFullLabel() {
                        Text("·")
                        Text(item.subtitle)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Craft's little "page" thumbnail used in list rows.
struct DocumentGlyph: View {
    var width: CGFloat = 30
    var height: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(SwiftUI.Color(uiColor: .systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(SwiftUI.Color(uiColor: .separator), lineWidth: 1)
            )
            .overlay(
                VStack(alignment: .leading, spacing: height * 0.07) {
                    Capsule().frame(width: width * 0.45, height: 1)
                    Capsule().frame(width: width * 0.65, height: 1)
                    Capsule().frame(width: width * 0.55, height: 1)
                    Capsule().frame(width: width * 0.6, height: 1)
                }
                .foregroundStyle(.tertiary)
                .padding(width * 0.15),
                alignment: .topLeading
            )
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

struct LibraryGroupHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.top, 8)
    }
}

struct LibraryHint: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(SwiftUI.Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }
}

// MARK: - Folders

struct FoldersScreen: View {
    @Bindable var model: HomeLibraryModel
    var parent: Project?
    var openNotes: (Project) -> Void
    var openChildren: (Project) -> Void
    var newNote: (Project?) -> Void
    var folderSettings: (Project) -> Void

    private var folders: [HomeLibraryModel.FolderNode] {
        model.children(of: parent).map { model.node(for: $0, depth: 0) }
    }

    var body: some View {
        List {
            if let parent {
                Section {
                    Button {
                        openNotes(parent)
                    } label: {
                        HomeRow(
                            title: String(format: NSLocalizedString("Notes in %@", comment: "Folder screen"), parent.label),
                            systemImage: "doc.text",
                            iconStyle: .document,
                            count: model.noteCount(for: parent),
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                if folders.isEmpty {
                    Text(NSLocalizedString("No folders yet", comment: "Home empty state"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(folders) { folder in
                        Button {
                            if folder.isExpandable {
                                openChildren(folder.project)
                            } else {
                                openNotes(folder.project)
                            }
                        } label: {
                            FolderRow(folder: folder)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                openNotes(folder.project)
                            } label: {
                                Label(NSLocalizedString("Show Notes", comment: ""), systemImage: "doc.text")
                            }
                            Button {
                                newNote(folder.project)
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
                                folderSettings(folder.project)
                            } label: {
                                Label(NSLocalizedString("Folder Settings", comment: ""), systemImage: "gearshape")
                            }
                        }
                    }
                }
            } header: {
                if parent != nil {
                    LibraryGroupHeader(title: NSLocalizedString("Folders", comment: "Home section"))
                }
            }
            .listRowBackground(SwiftUI.Color.clear)
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color(uiColor: .systemGroupedBackground))
        .navigationTitle(parent?.label ?? NSLocalizedString("Folders", comment: ""))
        .tint(SwiftUI.Color(uiColor: .label))
        .libraryBottomBar { newNote(parent) }
    }
}

struct FolderRow: View {
    var folder: HomeLibraryModel.FolderNode

    var body: some View {
        HStack(spacing: 14) {
            SwiftUI.Image(systemName: folder.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(folder.tint.map { AnyShapeStyle(SwiftUI.Color(uiColor: $0)) } ?? AnyShapeStyle(SwiftUI.Color(uiColor: .systemBlue)))
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(String(format: NSLocalizedString(folder.noteCount == 1 ? "%d Item" : "%d Items", comment: "Folder row"), folder.noteCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Tags

struct TagsScreen: View {
    @Bindable var model: HomeLibraryModel
    var openTag: (String) -> Void
    var newNote: () -> Void = { UIApplication.getVC().createNoteFromHome(in: nil) }

    var body: some View {
        List {
            if model.tags.isEmpty {
                Section {
                    LibraryHint(text: NSLocalizedString("Type #tags inside a note to organize it. Nested tags like #work/ideas group here.", comment: "Tags empty state"))
                }
            }

            Section {
                ForEach(model.tags) { tag in
                    HomeOutlineRow(
                        title: tag.name,
                        systemImage: "number",
                        depth: tag.depth,
                        isExpandable: tag.isExpandable,
                        isExpanded: tag.isExpanded,
                        iconStyle: .tag,
                        open: { openTag(tag.fullName) },
                        toggle: { model.toggle(tag: tag) }
                    )
                }
            }
            .listRowBackground(SwiftUI.Color.clear)
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("Tags", comment: ""))
        .tint(SwiftUI.Color(uiColor: .label))
        .libraryBottomBar(newNote: newNote)
    }
}

// MARK: - Hosting

/// Hosts one of the SwiftUI library screens in the UIKit navigation stack with
/// Craft's large title and a bottom bar holding only the "+" button.
final class LibraryScreenViewController<Content: View>: UIHostingController<Content> {
    private var onAppear: (() -> Void)?

    init(rootView: Content, onAppear: (() -> Void)? = nil) {
        self.onAppear = onAppear
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemGroupedBackground
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.setToolbarHidden(false, animated: animated)
        onAppear?()
    }
}
