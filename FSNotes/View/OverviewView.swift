//
//  OverviewView.swift
//  FSNotes
//
//  Craft-style overview canvas shown in the editor pane whenever there is no
//  note actually open: the Home dashboard (Starred / Recent / Folders) or a
//  simple card grid for whatever folder/tag/search is currently selected.
//

import SwiftUI
import Foundation

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
    @Published var displayMode: NoteListDisplayMode = .list
    @Published var showsFolderPath: Bool = false

    var onSelectNote: ((Note) -> Void)?
    var onSelectProject: ((Project) -> Void)?
    var onDisplayModeChange: ((NoteListDisplayMode) -> Void)?
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
                    VStack(alignment: .leading, spacing: 0) {
                        NoteTableColumnHeader()

                        ForEach(groupedByDate(model.recentNotes)) { group in
                            NoteTableGroupView(group: group, showsFolderPath: true) { model.onSelectNote?($0) }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    // MARK: Folder / selection

    private var folderBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.folderTitle)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                displayModeSwitcher
            }

            if model.folderNotes.isEmpty {
                emptyState(text: NSLocalizedString("No notes", comment: "Overview empty state"))
            } else if model.displayMode == .cards {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(model.folderNotes) { item in
                        NoteCard(item: item) { model.onSelectNote?(item.note) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    NoteTableColumnHeader()

                    ForEach(groupedByDate(model.folderNotes)) { group in
                        NoteTableGroupView(group: group, showsFolderPath: model.showsFolderPath) { model.onSelectNote?($0) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    /// Craft-style segmented control in the folder header: grid ↔ table,
    /// bound to `ProjectSettings.displayMode` for the selected folder.
    private var displayModeSwitcher: some View {
        Picker(NSLocalizedString("View as", comment: "Overview display mode"), selection: Binding(
            get: { model.displayMode == .cards ? NoteListDisplayMode.cards : .list },
            set: { model.onDisplayModeChange?($0) }
        )) {
            Label(NSLocalizedString("Cards", comment: "Overview display mode"), systemImage: "rectangle.grid.2x2")
                .tag(NoteListDisplayMode.cards)
            Label(NSLocalizedString("List", comment: "Overview display mode"), systemImage: "list.bullet")
                .tag(NoteListDisplayMode.list)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SwiftUI.Color(NSColor.labelColor))
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
                        SwiftUI.Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(SwiftUI.Color(NSColor.systemYellow))
                            .accessibilityLabel(NSLocalizedString("Starred", comment: "Note status"))
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
            .frame(height: 120, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(isHovering: isHovering))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Craft-style table (grouped by date bucket)

/// Buckets a note list the way Craft's "All Docs"/folder table groups rows:
/// Today, Yesterday, Last 7 days, Last 30 days, then one group per calendar
/// year (descending), each newest-modified-first.
@available(macOS 12, *)
private enum OverviewDateBucket: Hashable, Comparable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case year(Int)

    private var rank: Int {
        switch self {
        case .today: return 0
        case .yesterday: return 1
        case .last7Days: return 2
        case .last30Days: return 3
        case .year: return 4
        }
    }

    static func < (lhs: OverviewDateBucket, rhs: OverviewDateBucket) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        if case let .year(lY) = lhs, case let .year(rY) = rhs { return lY > rY }
        return false
    }

    var label: String {
        switch self {
        case .today: return NSLocalizedString("Today", comment: "Overview date bucket")
        case .yesterday: return NSLocalizedString("Yesterday", comment: "Overview date bucket")
        case .last7Days: return NSLocalizedString("Last 7 days", comment: "Overview date bucket")
        case .last30Days: return NSLocalizedString("Last 30 days", comment: "Overview date bucket")
        case .year(let year): return String(year)
        }
    }

    static func bucket(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> OverviewDateBucket {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0

        if days <= 7 { return .last7Days }
        if days <= 30 { return .last30Days }

        return .year(calendar.component(.year, from: date))
    }
}

@available(macOS 12, *)
private struct OverviewDateGroup: Identifiable {
    let id: String
    let label: String
    let items: [OverviewNoteItem]
}

@available(macOS 12, *)
private func groupedByDate(_ items: [OverviewNoteItem]) -> [OverviewDateGroup] {
    var buckets: [OverviewDateBucket: [OverviewNoteItem]] = [:]

    for item in items {
        let bucket = OverviewDateBucket.bucket(for: item.note.modifiedLocalAt)
        buckets[bucket, default: []].append(item)
    }

    return buckets.keys.sorted().map { bucket in
        let sorted = (buckets[bucket] ?? []).sorted { $0.note.modifiedLocalAt > $1.note.modifiedLocalAt }
        return OverviewDateGroup(id: bucket.label, label: bucket.label, items: sorted)
    }
}

@available(macOS 12, *)
private let overviewRelativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.dateTimeStyle = .named
    return formatter
}()

@available(macOS 12, *)
private func overviewRelativeString(for date: Date?) -> String {
    guard let date = date else { return "" }
    return overviewRelativeDateFormatter.localizedString(for: date, relativeTo: Date())
}

@available(macOS 12, *)
private struct NoteTableColumnHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text(NSLocalizedString("Name", comment: "Overview table column"))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 3) {
                Text(NSLocalizedString("Updated", comment: "Overview table column"))
                SwiftUI.Image(systemName: "arrow.down")
                    .accessibilityLabel(NSLocalizedString("Newest first", comment: "Overview sort order"))
            }
                .foregroundColor(SwiftUI.Color(NSColor.labelColor))
                .frame(width: 110, alignment: .leading)
            Text(NSLocalizedString("Created", comment: "Overview table column"))
                .frame(width: 110, alignment: .leading)
        }
        .font(.system(size: 11))
        .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SwiftUI.Color(NSColor.separatorColor).opacity(0.5))
                .frame(height: 1)
        }
    }
}

@available(macOS 12, *)
private struct NoteTableGroupView: View {
    let group: OverviewDateGroup
    let showsFolderPath: Bool
    let action: (Note) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.label)
                .font(.system(size: 12))
                .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                .padding(.top, 14)
                .padding(.bottom, 8)
                .padding(.horizontal, 12)

            ForEach(group.items) { item in
                NoteTableRow(item: item, showsFolderPath: showsFolderPath) { action(item.note) }
            }
        }
    }
}

@available(macOS 12, *)
private struct NoteTableRow: View {
    let item: OverviewNoteItem
    let showsFolderPath: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var subtitle: String {
        let folder = item.note.project.getNestedLabel()
        if showsFolderPath, !folder.isEmpty {
            return "\(folder) · \(item.preview)"
        }
        return item.preview
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(SwiftUI.Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(SwiftUI.Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .overlay(
                        SwiftUI.Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                    )
                    .frame(width: 28, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if item.isPinned {
                            SwiftUI.Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(SwiftUI.Color(NSColor.systemYellow))
                                .accessibilityLabel(NSLocalizedString("Starred", comment: "Note status"))
                        }

                        Text(item.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(overviewRelativeString(for: item.note.modifiedLocalAt))
                    .font(.system(size: 11))
                    .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)

                Text(overviewRelativeString(for: item.note.creationDate))
                    .font(.system(size: 11))
                    .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? SwiftUI.Color(NSColor.controlAccentColor).opacity(0.08) : SwiftUI.Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SwiftUI.Color(NSColor.separatorColor).opacity(0.5))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
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
