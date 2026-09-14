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

        items.append(makeTextStyleMenuButton())
        fixedWidth += Self.toolbarButtonSide

        items.append(makeSeparator())
        fixedWidth += Self.separatorWidth

        items.append(makeToolbarButton(
            systemImage: "checkmark.square",
            selector: #selector(EditorViewController.todoPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("To-do", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        items.append(makeToolbarButton(
            systemImage: "list.bullet",
            selector: #selector(EditorViewController.orderedListPressed),
            tint: .label,
            accessibilityLabel: NSLocalizedString("Bulleted list", comment: "")
        ))
        fixedWidth += Self.toolbarButtonSide

        items.append(UIBarButtonItem.flexibleSpace())

        items.append(makeInsertMenuButton())
        fixedWidth += Self.toolbarButtonSide

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
        let image = UIImage(systemName: "plus", withConfiguration: config)

        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.tintColor = .label
        button.menu = makeInsertMenu()
        button.showsMenuAsPrimaryAction = true
        button.frame = CGRect(x: 0, y: 0, width: Self.toolbarButtonSide, height: Self.toolbarButtonSide)
        button.accessibilityLabel = NSLocalizedString("Insert", comment: "")

        let item = UIBarButtonItem(customView: button)
        item.accessibilityLabel = NSLocalizedString("Insert", comment: "")
        return item
    }

    private func makeInsertMenu() -> UIMenu {
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

        insertActions.append(UIAction(
            title: NSLocalizedString("Divider", comment: ""),
            image: UIImage(systemName: "minus")
        ) { [weak self] _ in self?.dividerPressed() })

        return UIMenu(
            title: NSLocalizedString("Insert", comment: ""),
            options: .displayInline,
            children: insertActions
        )
    }

    @objc func dividerPressed() {
        if nativeHost.isActive {
            nativeHost.adapter?.insertText("\n---\n")
            return
        }
        editArea.insertText("\n---\n")
    }

    // MARK: - "Aa" text-style menu

    private func makeTextStyleMenuButton() -> UIBarButtonItem {
        let button = UIButton(type: .system)
        button.setTitle(NSLocalizedString("Aa", comment: ""), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.setTitleColor(.label, for: .normal)
        button.menu = makeTextStyleMenu()
        button.showsMenuAsPrimaryAction = true
        button.frame = CGRect(x: 0, y: 0, width: Self.toolbarButtonSide, height: Self.toolbarButtonSide)
        button.accessibilityLabel = NSLocalizedString("Text style", comment: "")

        let item = UIBarButtonItem(customView: button)
        item.accessibilityLabel = NSLocalizedString("Text style", comment: "")
        return item
    }

    private func makeTextStyleMenu() -> UIMenu {
        var textActions = [UIAction]()

        textActions.append(UIAction(
            title: NSLocalizedString("Heading", comment: ""),
            image: UIImage(systemName: "textformat.size.larger")
        ) { [weak self] _ in self?.headerPressed() })

        textActions.append(UIAction(
            title: NSLocalizedString("Body", comment: ""),
            image: UIImage(systemName: "textformat")
        ) { [weak self] _ in self?.bodyPressed() })

        textActions.append(UIAction(
            title: NSLocalizedString("Quote", comment: ""),
            image: UIImage(systemName: "text.quote")
        ) { [weak self] _ in self?.quotePressed() })

        textActions.append(UIAction(
            title: NSLocalizedString("Code block", comment: ""),
            image: UIImage(systemName: "curlybraces")
        ) { [weak self] _ in self?.codeBlockButton() })

        let textMenu = UIMenu(
            title: NSLocalizedString("Text", comment: ""),
            options: .displayInline,
            children: textActions
        )

        var styleActions = [UIAction]()

        styleActions.append(UIAction(
            title: NSLocalizedString("Bold", comment: ""),
            image: UIImage(systemName: "bold")
        ) { [weak self] _ in self?.boldPressed() })

        styleActions.append(UIAction(
            title: NSLocalizedString("Italic", comment: ""),
            image: UIImage(systemName: "italic")
        ) { [weak self] _ in self?.italicPressed() })

        styleActions.append(UIAction(
            title: NSLocalizedString("Strikethrough", comment: ""),
            image: UIImage(systemName: "strikethrough")
        ) { [weak self] _ in self?.strikePressed() })

        styleActions.append(UIAction(
            title: NSLocalizedString("Underline", comment: ""),
            image: UIImage(systemName: "underline")
        ) { [weak self] _ in self?.underlinePressed() })

        let styleMenu = UIMenu(
            title: NSLocalizedString("Style", comment: ""),
            options: .displayInline,
            children: styleActions
        )

        let listMenu = UIMenu(title: NSLocalizedString("Lists and indentation", comment: ""), image: UIImage(systemName: "list.bullet"), children: [
            UIAction(title: NSLocalizedString("Numbered list", comment: ""), image: UIImage(systemName: "list.number")) { [weak self] _ in self?.numberedListPressed() },
            UIAction(title: NSLocalizedString("Indent", comment: ""), image: UIImage(systemName: "increase.indent")) { [weak self] _ in self?.indentPressed() },
            UIAction(title: NSLocalizedString("Outdent", comment: ""), image: UIImage(systemName: "decrease.indent")) { [weak self] _ in self?.unIndentPressed() }
        ])

        return UIMenu(
            title: NSLocalizedString("Aa", comment: ""),
            children: [textMenu, styleMenu, listMenu]
        )
    }

    /// Strips a leading heading (`#` … `######`) or blockquote (`>`) marker from the
    /// current paragraph, returning it to plain body text. Routed through
    /// `UITextView.replace(_:withText:)` so the change participates in undo.
    @objc func bodyPressed() {
        if nativeHost.isActive {
            nativeHost.adapter?.setHeading(nil)
            return
        }
        let storage = editArea.textStorage
        let pRange = storage.mutableString.paragraphRange(for: editArea.selectedRange)
        let paragraph = storage.mutableString.substring(with: pRange)

        guard let regex = try? NSRegularExpression(pattern: "^(#{1,6}\\s|>\\s)") else { return }
        let fullRange = NSRange(location: 0, length: (paragraph as NSString).length)
        guard let match = regex.firstMatch(in: paragraph, range: fullRange) else { return }

        let stripped = (paragraph as NSString).replacingCharacters(in: match.range, with: "")

        guard
            let start = editArea.position(from: editArea.beginningOfDocument, offset: pRange.location),
            let end = editArea.position(from: start, offset: pRange.length),
            let textRange = editArea.textRange(from: start, to: end)
        else { return }

        editArea.replace(textRange, withText: stripped)
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
