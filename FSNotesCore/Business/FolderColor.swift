//
//  FolderColor.swift
//  FSNotes
//
//  Craft-style per-folder accent colors. Stored in `ProjectSettings` by raw
//  value so the file-based library stays portable.
//

#if os(OSX)
import Cocoa
#else
import UIKit
#endif

public enum FolderColor: String, CaseIterable {
    case gray
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink

    public var title: String {
        switch self {
        case .gray: return NSLocalizedString("Gray", comment: "Folder color")
        case .red: return NSLocalizedString("Red", comment: "Folder color")
        case .orange: return NSLocalizedString("Orange", comment: "Folder color")
        case .yellow: return NSLocalizedString("Yellow", comment: "Folder color")
        case .green: return NSLocalizedString("Green", comment: "Folder color")
        case .teal: return NSLocalizedString("Teal", comment: "Folder color")
        case .blue: return NSLocalizedString("Blue", comment: "Folder color")
        case .indigo: return NSLocalizedString("Indigo", comment: "Folder color")
        case .purple: return NSLocalizedString("Purple", comment: "Folder color")
        case .pink: return NSLocalizedString("Pink", comment: "Folder color")
        }
    }

    /// Light-appearance reference value; platform colors below adapt to dark mode.
    public var hex: String {
        switch self {
        case .gray: return "#8E8E93"
        case .red: return "#FF3B30"
        case .orange: return "#FF9500"
        case .yellow: return "#FFCC00"
        case .green: return "#34C759"
        case .teal: return "#30B0C7"
        case .blue: return "#007AFF"
        case .indigo: return "#5856D6"
        case .purple: return "#AF52DE"
        case .pink: return "#FF2D55"
        }
    }

#if os(OSX)
    public var platformColor: NSColor {
        switch self {
        case .gray: return .systemGray
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .blue: return .systemBlue
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        }
    }
#else
    public var platformColor: UIColor {
        switch self {
        case .gray: return .systemGray
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .blue: return .systemBlue
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        }
    }
#endif
}

/// SF Symbols a folder can use instead of the default folder glyph.
public enum FolderIcon {
    public static let defaultName = "folder"

    public static let choices: [String] = [
        "folder", "folder.fill", "tray.full", "archivebox", "book.closed", "books.vertical",
        "briefcase", "graduationcap", "lightbulb", "star", "heart", "flag",
        "house", "building.2", "cart", "creditcard", "airplane", "car",
        "leaf", "pawprint", "fork.knife", "cup.and.saucer", "gamecontroller", "music.note",
        "camera", "paintpalette", "hammer", "wrench.and.screwdriver", "gearshape", "terminal",
        "doc.text", "list.bullet.clipboard", "checklist", "calendar", "clock", "bell",
        "person", "person.2", "globe", "map", "tag", "bookmark"
    ]
}
