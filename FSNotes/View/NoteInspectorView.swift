//
//  NoteInspectorView.swift
//  FSNotes
//
//  Craft-style "Note Info" popover: metadata, counts, tags, pin toggle,
//  encryption state and a Reveal in Finder shortcut for the note that is
//  currently open in the editor.
//

import SwiftUI

@available(macOS 12, *)
struct NoteInspectorView: View {
    let note: Note
    let folderPath: String
    let createdLabel: String?
    let modifiedLabel: String?
    let wordCount: Int
    let charCount: Int
    let tags: [String]
    let isEncrypted: Bool
    let isLocked: Bool
    let fileName: String

    let onToggle: (Note) -> Void
    let onReveal: () -> Void

    @State private var isPinned: Bool

    init(
        note: Note,
        folderPath: String,
        createdLabel: String?,
        modifiedLabel: String?,
        wordCount: Int,
        charCount: Int,
        tags: [String],
        isEncrypted: Bool,
        isLocked: Bool,
        fileName: String,
        onToggle: @escaping (Note) -> Void,
        onReveal: @escaping () -> Void
    ) {
        self.note = note
        self.folderPath = folderPath
        self.createdLabel = createdLabel
        self.modifiedLabel = modifiedLabel
        self.wordCount = wordCount
        self.charCount = charCount
        self.tags = tags
        self.isEncrypted = isEncrypted
        self.isLocked = isLocked
        self.fileName = fileName
        self.onToggle = onToggle
        self.onReveal = onReveal
        _isPinned = State(initialValue: note.isPinned)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(note.getTitle() ?? note.getFileName())
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                labeledRow(NSLocalizedString("Folder", comment: "Note Info"), folderPath)

                if let createdLabel = createdLabel {
                    labeledRow(NSLocalizedString("Created", comment: "Note Info"), createdLabel)
                }

                if let modifiedLabel = modifiedLabel {
                    labeledRow(NSLocalizedString("Modified", comment: "Note Info"), modifiedLabel)
                }

                labeledRow(NSLocalizedString("Words", comment: "Note Info"), "\(wordCount)")
                labeledRow(NSLocalizedString("Characters", comment: "Note Info"), "\(charCount)")
            }

            if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("Tags", comment: "Note Info"))
                        .font(.system(size: 11))
                        .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(SwiftUI.Color(NSColor.controlAccentColor).opacity(0.15))
                                    )
                            }
                        }
                    }
                }
            }

            Toggle(NSLocalizedString("Pinned", comment: "Note Info"), isOn: Binding(
                get: { isPinned },
                set: { newValue in
                    isPinned = newValue
                    onToggle(note)
                }
            ))

            if isEncrypted {
                HStack(spacing: 6) {
                    SwiftUI.Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    Text(isLocked ? NSLocalizedString("Locked", comment: "Note Info") : NSLocalizedString("Encrypted", comment: "Note Info"))
                }
                .font(.system(size: 12))
                .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
            }

            Divider()

            HStack {
                Text(fileName)
                    .font(.system(size: 11))
                    .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(NSLocalizedString("Reveal in Finder", comment: "Note Info"), action: onReveal)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(SwiftUI.Color(NSColor.secondaryLabelColor))
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12))
    }
}
