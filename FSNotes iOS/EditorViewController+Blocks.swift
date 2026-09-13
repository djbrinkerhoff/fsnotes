//
//  EditorViewController+Blocks.swift
//  FSNotes iOS
//
//  Craft-style keyboard accessory toolbar for the note editor.
//

import UIKit

extension EditorViewController {

    private static let toolbarButtonSide: CGFloat = 44
    private static let toolbarHeight: CGFloat = 50
    private static let separatorWidth: CGFloat = 16

    /// Builds the single accessory toolbar used above the keyboard while editing a note.
    /// Replaces the old per-iOS-version (`getModernToolbar` / `getLegacyToolbar`) toolbars.
    public func makeAccessoryToolbar() -> UIToolbar {
        var items = [UIBarButtonItem]()
        var fixedWidth: CGFloat = 0

        items.append(makeInsertMenuButton())
        fixedWidth += Self.toolbarButtonSide

        items.append(makeSeparator())
        fixedWidth += Self.separatorWidth

        items.append(makeToolbarButton(
            systemImage: "bold",
            selector: #selector(EditorViewController.boldPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Bold", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        items.append(makeToolbarButton(
            systemImage: "italic",
            selector: #selector(EditorViewController.italicPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Italic", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        items.append(makeToolbarButton(
            systemImage: "strikethrough",
            selector: #selector(EditorViewController.strikePressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Strikethrough", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        items.append(makeToolbarButton(
            systemImage: "checkmark.square",
            selector: #selector(EditorViewController.todoPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("To-do", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        items.append(makeToolbarButton(
            systemImage: "increase.indent",
            selector: #selector(EditorViewController.indentPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Indent", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        items.append(makeToolbarButton(
            systemImage: "decrease.indent",
            selector: #selector(EditorViewController.unIndentPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Outdent", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        items.append(UIBarButtonItem.flexibleSpace())

        let undoItem = makeToolbarButton(
            systemImage: "arrow.uturn.backward",
            selector: #selector(EditorViewController.undoPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Undo", comment: "")
        )
        self.undoBarButton = undoItem
        items.append(undoItem)
        fixedWidth += Self.toolbarButtonSide

        let redoItem = makeToolbarButton(
            systemImage: "arrow.uturn.forward",
            selector: #selector(EditorViewController.redoPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Redo", comment: "")
        )
        self.redoBarButton = redoItem
        items.append(redoItem)
        fixedWidth += Self.toolbarButtonSide

        items.append(makeToolbarButton(
            systemImage: "keyboard.chevron.compact.down",
            selector: #selector(EditorViewController.dismissKeyboard),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Dismiss keyboard", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        let screenWidth = UIScreen.main.bounds.width
        let stretches = fixedWidth <= screenWidth
        let toolbarWidth = stretches ? screenWidth : fixedWidth

        let toolBar = UIToolbar(frame: CGRect(x: 0, y: 0, width: toolbarWidth, height: Self.toolbarHeight))
        toolBar.setItems(items, animated: false)
        toolBar.isUserInteractionEnabled = true

        if stretches {
            toolBar.autoresizingMask = [.flexibleWidth]
        }

        let appearance = UIToolbarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = .clear
        toolBar.standardAppearance = appearance
        toolBar.scrollEdgeAppearance = appearance

        return toolBar
    }

    @objc func dismissKeyboard() {
        editArea.resignFirstResponder()
    }

    // MARK: - Insert ("+") menu

    private func makeInsertMenuButton() -> UIBarButtonItem {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        let image = UIImage(systemName: "plus.circle.fill", withConfiguration: config)

        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.tintColor = .mainTheme
        button.menu = makeInsertMenu()
        button.showsMenuAsPrimaryAction = true
        button.frame = CGRect(x: 0, y: 0, width: Self.toolbarButtonSide, height: Self.toolbarButtonSide)
        button.accessibilityLabel = NSLocalizedString("Insert", comment: "")

        let item = UIBarButtonItem(customView: button)
        item.accessibilityLabel = NSLocalizedString("Insert", comment: "")
        return item
    }

    private func makeInsertMenu() -> UIMenu {
        var blockActions = [UIAction]()

        blockActions.append(UIAction(
            title: NSLocalizedString("Heading", comment: ""),
            image: UIImage(systemName: "textformat.size")
        ) { [weak self] _ in self?.headerPressed() })

        blockActions.append(UIAction(
            title: NSLocalizedString("To-do", comment: ""),
            image: UIImage(systemName: "checkmark.square")
        ) { [weak self] _ in self?.todoPressed() })

        blockActions.append(UIAction(
            title: NSLocalizedString("Bulleted list", comment: ""),
            image: UIImage(systemName: "list.bullet")
        ) { [weak self] _ in self?.orderedListPressed() })

        blockActions.append(UIAction(
            title: NSLocalizedString("Numbered list", comment: ""),
            image: UIImage(systemName: "list.number")
        ) { [weak self] _ in self?.numberedListPressed() })

        blockActions.append(UIAction(
            title: NSLocalizedString("Quote", comment: ""),
            image: UIImage(systemName: "text.quote")
        ) { [weak self] _ in self?.quotePressed() })

        blockActions.append(UIAction(
            title: NSLocalizedString("Code block", comment: ""),
            image: UIImage(systemName: "curlybraces")
        ) { [weak self] _ in self?.codeBlockButton() })

        let blocksMenu = UIMenu(
            title: NSLocalizedString("Blocks", comment: ""),
            options: .displayInline,
            children: blockActions
        )

        var insertActions = [UIAction]()

        insertActions.append(UIAction(
            title: NSLocalizedString("Link to note", comment: ""),
            image: UIImage(systemName: "link")
        ) { [weak self] _ in self?.wikilink() })

        insertActions.append(UIAction(
            title: NSLocalizedString("Attachment", comment: ""),
            image: UIImage(systemName: "paperclip")
        ) { [weak self] _ in self?.insertFile() })

        if UserDefaultsManagement.inlineTags {
            insertActions.append(UIAction(
                title: NSLocalizedString("Tag", comment: ""),
                image: UIImage(systemName: "number")
            ) { [weak self] _ in self?.tagPressed() })
        }

        let insertMenu = UIMenu(
            title: NSLocalizedString("Insert", comment: ""),
            options: .displayInline,
            children: insertActions
        )

        return UIMenu(
            title: NSLocalizedString("Insert", comment: ""),
            children: [blocksMenu, insertMenu]
        )
    }

    // MARK: - Helpers

    private func makeSeparator() -> UIBarButtonItem {
        let item = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        item.width = Self.separatorWidth
        return item
    }

    private func makeToolbarButton(
        systemImage: String,
        selector: Selector,
        tint: UIColor,
        accessibilityLabel: String
    ) -> UIBarButtonItem {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let image = UIImage(systemName: systemImage, withConfiguration: config)

        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.tintColor = tint
        button.addTarget(self, action: selector, for: .touchUpInside)
        button.frame = CGRect(x: 0, y: 0, width: Self.toolbarButtonSide, height: Self.toolbarButtonSide)
        button.accessibilityLabel = accessibilityLabel

        let item = UIBarButtonItem(customView: button)
        item.accessibilityLabel = accessibilityLabel
        return item
    }
}
