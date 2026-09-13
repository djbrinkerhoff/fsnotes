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

        NSColor.labelColor.withAlphaComponent(isEmphasized ? 0.08 : 0.05).setFill()

        path.fill()
    }

    // The neutral selection pill retains normal text and custom folder colors.
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        return .normal
    }
}
