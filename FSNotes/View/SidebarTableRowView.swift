//
//  SidebarTableRowView.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 4/11/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class SidebarTableRowView: NSTableRowView {

    // Craft-style rounded selection pill instead of the default edge-to-edge highlight.
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        let selectionRect = bounds.insetBy(dx: 6, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)

        if isEmphasized {
            NSColor.selectedContentBackgroundColor.setFill()
        } else {
            NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
        }

        path.fill()
    }

    // Ensures label/icon tint (which read NSTableCellView.backgroundStyle) flip to
    // their "on selected background" appearance only when the row is actually
    // selected and the window is key/emphasized — matching drawSelection above.
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        if isSelected && isEmphasized {
            return .emphasized
        }

        return .normal
    }
}
