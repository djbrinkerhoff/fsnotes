//
//  OverviewView.swift
//  FSNotes
//
//  Craft-style overview canvas shown in the editor pane whenever there is no
//  note actually open: the Home dashboard (Starred / Recent / Folders) or a
//  simple card grid for whatever folder/tag/search is currently selected.
//

import SwiftUI

/// A single note rendered as a card in the overview grid.
@available(macOS 12, *)
struct OverviewNoteItem: Identifiable {
    let id: String
    let title: String
    let preview: String
    let dateLabel: String
    let isPinned: Bool
    let note: Note
}

/// A single folder rendered as a card in the Home "Folders" section.
@available(macOS 12, *)
struct OverviewFolderItem: Identifiable {
    let id: String
    let title: String
    let noteCount: Int
    let tintColor: NSColor
    let iconName: String
    let project: Project
}

@available(macOS 12, *)
final class OverviewModel: ObservableObject {
    enum Mode: Equatable {
        case hidden
        case home
        case folder
    }

    @Published var mode: Mode = .hidden

    // Home
    @Published var pinnedNotes: [OverviewNoteItem] = []
    @Published var recentNotes: [OverviewNoteItem] = []
    @Published var folders: [OverviewFolderItem] = []

    // Folder / generic selection
    @Published var folderTitle: String = ""
    @Published var folderNotes: [OverviewNoteItem] = []

    var onSelectNote: ((Note) -> Void)?
    var onSelectProject: ((Project) -> Void)?
}

@available(macOS 12, *)
struct OverviewView: View {
    @ObservedObject var model: OverviewModel

    private let columns = [SwiftUI.GridItem(.adaptive(minimum: 200), spacing: 14)]

    var body: some View {
        ScrollView {
            switch model.mode {
            case .hidden:
                EmptyView()
            case .home:
                homeBody
            case .folder:
                folderBody
            }
        }
        .background(SwiftUI.Color(NSColor.textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Home

    private var homeBody: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !model.pinnedNotes.isEmpty {
                section(title: NSLocalizedString("Starred", comment: "Overview section")) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(model.pinnedNotes) { item in
                            NoteCard(item: item) { model.onSelectNote?(item.note) }
                        }
                    }
                }
            }

            if !model.recentNotes.isEmpty {
                section(title: NSLocalizedString("Recent", comment: "Overview section")) {
                    LazyVGrid(columns: [SwiftUI.GridItem(.adaptive(minimum: 260), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(model.recentNotes) { item in
                            NoteRow(item: item) { model.onSelectNote?(item.note) }
                        }
                    }
                }
            }

            if !model.folders.isEmpty {
                section(title: NSLocalizedString("Folders", comment: "Overview section")) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(model.folders) { folder in
                            FolderCard(item: folder) { model.onSelectProject?(folder.project) }
                        }
                    }
                }
            }

            if model.pinnedNotes.isEmpty && model.recentNotes.isEmpty && model.folders.isEmpty {
                emptyState(text: NSLocalizedString("No notes yet", comment: "Overview empty state"))
            }
        }
        .padding(24)
    }

    // MARK: Folder / selection

    private var folderBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.folderTitle)
                    .font(.title2.weight(.semibold))
                Text("\(model.folderNotes.count)")
                    .font(.title3)
                    .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
            }

            if model.folderNotes.isEmpty {
                emptyState(text: NSLocalizedString("No notes", comment: "Overview empty state"))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(model.folderNotes) { item in
                        NoteCard(item: item) { model.onSelectNote?(item.note) }
                    }
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
            content()
        }
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

// MARK: - Cards

@available(macOS 12, *)
private struct CardBackground: View {
    var isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(SwiftUI.Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SwiftUI.Color(NSColor.separatorColor), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SwiftUI.Color(NSColor.controlAccentColor).opacity(isHovering ? 0.08 : 0))
            )
    }
}

@available(macOS 12, *)
private struct NoteCard: View {
    let item: OverviewNoteItem
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    if item.isPinned {
                        SwiftUI.Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                    }
                }

                Text(item.preview)
                    .font(.system(size: 12))
                    .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text(item.dateLabel)
                    .font(.system(size: 11))
                    .foregroundColor(SwiftUI.Color(NSColor.tertiaryLabelColor))
            }
            .padding(12)
            .frame(minHeight: 100, maxHeight: 120, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(isHovering: isHovering))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

@available(macOS 12, *)
private struct NoteRow: View {
    let item: OverviewNoteItem
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if item.isPinned {
                    SwiftUI.Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                }

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text(item.dateLabel)
                    .font(.system(size: 11))
                    .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(isHovering: isHovering))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

@available(macOS 12, *)
private struct FolderCard: View {
    let item: OverviewFolderItem
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                SwiftUI.Image(systemName: item.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(SwiftUI.Color(item.tintColor))

                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(String(format: NSLocalizedString("%d notes", comment: "Overview folder count"), item.noteCount))
                    .font(.system(size: 11))
                    .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
            }
            .padding(12)
            .frame(minHeight: 90, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(isHovering: isHovering))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
