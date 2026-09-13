//
//  SidebarCellView.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 4/7/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class SidebarCellView: NSTableCellView {
    @IBOutlet weak var icon: NSImageView!
    @IBOutlet weak var label: NSTextField!

    public var type: SidebarItemType? {
        didSet { updateIconTint() }
    }
    public var storage = Storage.shared()

    /// Craft-style tint: accent for system rows, neutral for folders and tags,
    /// white while the row is drawn on the emphasized selection pill.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateIconTint() }
    }

    private func updateIconTint() {
        guard let icon = icon else { return }

        if backgroundStyle == .emphasized {
            icon.contentTintColor = .white
            return
        }

        switch type {
        case .Project, .ProjectEncryptedLocked, .ProjectEncryptedUnlocked, .Tag:
            icon.contentTintColor = .secondaryLabelColor
        case .none:
            icon.contentTintColor = .controlAccentColor
        default:
            icon.contentTintColor = .controlAccentColor
        }
    }

    @IBAction func projectName(_ sender: NSTextField) {
        let cell = sender.superview as? SidebarCellView

        guard let project = cell?.objectValue as? Project else { return }
        
        let src = project.url
        let dst = project.url.deletingLastPathComponent().appendingPathComponent(sender.stringValue, isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                sender.stringValue = project.url.lastPathComponent
                return
            }

            try FileManager.default.moveItem(at: src, to: dst)
        } catch {
            sender.stringValue = project.url.lastPathComponent
            let alert = NSAlert()
            alert.messageText = error.localizedDescription
            alert.runModal()
        }
    }
}
