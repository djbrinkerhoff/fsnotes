//
//  ProjectSettingsViewController.swift
//  FSNotes iOS
//
//  Created by Oleksandr Glushchenko on 9/20/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import UIKit

class ProjectSettingsViewController: UITableViewController {
    private var dismiss: Bool = false
    private var project: Project
    private var sections = [
        NSLocalizedString("Sort By", comment: ""),
        NSLocalizedString("Sort Direction", comment: ""),
        NSLocalizedString("Visibility", comment: ""),
        NSLocalizedString("Notes List", comment: "")
    ]
    private var rowsInSections = [4, 2, 2, 1]

    /// Index of the Craft-style "Appearance" section (Color / Icon), or nil
    /// for virtual/trash projects which don't support folder appearance.
    private var appearanceSectionIndex: Int?

    init(project: Project, dismiss: Bool = false) {
        self.project = project
        self.dismiss = dismiss

        super.init(style: .grouped)

        if !project.isVirtual && !project.isTrash {
            appearanceSectionIndex = sections.count
            sections.append(NSLocalizedString("Appearance", comment: ""))
            rowsInSections.append(2)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        if dismiss {
            self.navigationItem.rightBarButtonItem = Buttons.getDone(target: self, selector: #selector(close))
        }

        self.title = project.getFullLabel()

        super.viewDidLoad()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let vc = UIApplication.getVC()

        if let appearanceSectionIndex = appearanceSectionIndex, indexPath.section == appearanceSectionIndex {
            if indexPath.row == 1 {
                let picker = FolderIconPickerViewController(project: project)
                navigationController?.pushViewController(picker, animated: true)
            }

            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        if let cell = tableView.cellForRow(at: indexPath) {
            if indexPath.section == 0x00 {
                for row in 0...rowsInSections[indexPath.section] {
                    let cell = tableView.cellForRow(at: IndexPath(row: row, section: indexPath.section))
                    cell?.accessoryType = .none
                }

                if let sort = SortBy(rawValue: cell.reuseIdentifier!) {
                    self.project.settings.sortBy = sort
                    vc.buildSearchQuery()
                    vc.reloadNotesTable()
                }

                if cell.accessoryType == .none {
                    cell.accessoryType = .checkmark
                } else {
                    cell.accessoryType = .none
                }
            }

            if indexPath.section == 0x01 {
                for row in 0...rowsInSections[indexPath.section] {
                    let cell = tableView.cellForRow(at: IndexPath(row: row, section: indexPath.section))
                    cell?.accessoryType = .none
                }

                if let sort = SortDirection(rawValue: cell.reuseIdentifier!) {
                    self.project.settings.sortDirection = sort
                    vc.buildSearchQuery()
                    vc.reloadNotesTable()
                }

                if cell.accessoryType == .none {
                    cell.accessoryType = .checkmark
                } else {
                    cell.accessoryType = .none
                }
            }
        }

        project.saveSettings()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rowsInSections[section]
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 50
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let appearanceSectionIndex = appearanceSectionIndex, indexPath.section == appearanceSectionIndex {
            return indexPath.row == 0 ? makeAppearanceColorCell() : makeAppearanceIconCell()
        }

        let uiSwitch = UISwitch()
        uiSwitch.addTarget(self, action: #selector(switchValueDidChange(_:)), for: .valueChanged)
        
        var cell = UITableViewCell()

        if indexPath.section == 0x00 {
            switch indexPath.row {
            case 0:
                cell = UITableViewCell(style: .default, reuseIdentifier: "none")
                cell.textLabel?.text = NSLocalizedString("None", comment: "")
                if project.settings.sortBy.rawValue == "none" {
                    cell.accessoryType = .checkmark
                }
                break
            case 1:
                cell = UITableViewCell(style: .default, reuseIdentifier: "modificationDate")
                cell.textLabel?.text = NSLocalizedString("Modification Date", comment: "")
                if project.settings.sortBy.rawValue == "modificationDate" {
                    cell.accessoryType = .checkmark
                }
                break
            case 2:
                cell = UITableViewCell(style: .default, reuseIdentifier: "creationDate")
                cell.textLabel?.text = NSLocalizedString("Creation Date", comment: "")

                if project.settings.sortBy.rawValue == "creationDate" {
                    cell.accessoryType = .checkmark
                }
                break
            case 3:
                cell = UITableViewCell(style: .default, reuseIdentifier: "title")
                cell.textLabel?.text = NSLocalizedString("Title", comment: "")

                if project.settings.sortBy.rawValue == "title" {
                    cell.accessoryType = .checkmark
                }
                break
            default:
                break
            }
        }

        if indexPath.section == 0x01 {
            switch indexPath.row {
            case 0:
                cell = UITableViewCell(style: .default, reuseIdentifier: "asc")
                cell.textLabel?.text = NSLocalizedString("Ascending", comment: "")
                if project.settings.sortDirection.rawValue == "asc" {
                    cell.accessoryType = .checkmark
                }
                break
            case 1:
                cell = UITableViewCell(style: .default, reuseIdentifier: "desc")
                cell.textLabel?.text = NSLocalizedString("Descending", comment: "")
                if project.settings.sortDirection.rawValue == "desc" {
                    cell.accessoryType = .checkmark
                }
                break
            default:
                break
            }
        }

        if indexPath.section == 0x02 {
            switch indexPath.row {
            case 0:
                cell.accessoryView = uiSwitch
                uiSwitch.isOn = project.settings.showInCommon
                uiSwitch.isEnabled =
                    !project.isDefault
                    && !project.isTrash
                    && !project.isVirtual

                cell.textLabel?.text = NSLocalizedString("Show Notes in \"Notes\" and \"Todo\"", comment: "")
            case 1:
                cell.accessoryView = uiSwitch
                uiSwitch.isOn = project.settings.showInSidebar
                uiSwitch.isEnabled =
                    !project.isDefault
                    && !project.isTrash
                    && !project.isVirtual

                cell.textLabel?.text = NSLocalizedString("Show Folder in Library", comment: "")
            default:
                return cell
            }
        }

        if indexPath.section == 0x03 {
            cell.accessoryView = uiSwitch
            uiSwitch.isOn = project.settings.isFirstLineAsTitle()
            uiSwitch.isEnabled = !project.isVirtual

            cell.textLabel?.text = NSLocalizedString("Use First Line as Title", comment: "")
        }

        return cell
    }

    @objc public func switchValueDidChange(_ sender: UISwitch) {
        guard let cell = sender.superview as? UITableViewCell,
            let tableView = cell.superview as? UITableView,
            let indexPath = tableView.indexPath(for: cell) else { return }

        let vc = UIApplication.getVC()

        if indexPath.section == 0x02 {
            if indexPath.row == 0x00 {
                guard let uiSwitch = cell.accessoryView as? UISwitch else { return }
                self.project.settings.showInCommon = uiSwitch.isOn

                vc.reloadNotesTable()
            } else {
                guard let uiSwitch = cell.accessoryView as? UISwitch else { return }

                self.project.settings.showInSidebar = uiSwitch.isOn

                OperationQueue.main.addOperation {
                    if !uiSwitch.isOn {
                        let at = IndexPath(row: 0, section: 0)
                        vc.sidebarTableView.tableView(vc.sidebarTableView, didSelectRowAt: at)
                        vc.sidebarTableView.removeRows(projects: [self.project])
                    } else {
                        vc.sidebarTableView.insertRows(projects: [self.project])
                    }
                }
            }
        } else if indexPath.section == 0x03 {
            guard let uiSwitch = cell.accessoryView as? UISwitch else { return }
            project.settings.firstLineAsTitle = uiSwitch.isOn

            let notes = Storage.shared().getNotesBy(project: project)
            for note in notes {
                note.invalidateCache()
            }

            vc.reloadNotesTable()
        }

        project.saveSettings()
    }

    @objc func cancel() {
        navigationController?.popViewController(animated: true)
    }

    @objc func close() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Appearance ("Color" / "Icon")

    private func makeAppearanceColorCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10)
        ])

        let currentColor = project.settings.folderColor

        // Leading "no color" swatch, tag -1.
        stack.addArrangedSubview(makeColorSwatch(color: nil, isSelected: currentColor == nil, tag: -1))

        for (index, color) in FolderColor.allCases.enumerated() {
            stack.addArrangedSubview(makeColorSwatch(color: color, isSelected: currentColor == color, tag: index))
        }

        return cell
    }

    private func makeColorSwatch(color: FolderColor?, isSelected: Bool, tag: Int) -> UIButton {
        let size: CGFloat = 28
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = tag
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(colorSwatchTapped(_:)), for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size)
        ])

        if let color = color {
            button.backgroundColor = color.platformColor
            button.accessibilityLabel = color.title
        } else {
            button.backgroundColor = .secondarySystemFill
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.separator.cgColor

            let slash = UIImageView(image: UIImage(systemName: "slash.circle"))
            slash.translatesAutoresizingMaskIntoConstraints = false
            slash.tintColor = .secondaryLabel
            slash.isUserInteractionEnabled = false
            button.addSubview(slash)
            NSLayoutConstraint.activate([
                slash.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                slash.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                slash.widthAnchor.constraint(equalToConstant: size),
                slash.heightAnchor.constraint(equalToConstant: size)
            ])

            button.accessibilityLabel = NSLocalizedString("No Color", comment: "Folder color")
        }

        if isSelected {
            let checkmarkConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            let checkmark = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: checkmarkConfig))
            checkmark.translatesAutoresizingMaskIntoConstraints = false
            checkmark.tintColor = .white
            checkmark.contentMode = .scaleAspectFit
            checkmark.isUserInteractionEnabled = false
            button.addSubview(checkmark)
            NSLayoutConstraint.activate([
                checkmark.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                checkmark.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])

            button.accessibilityValue = NSLocalizedString("Selected", comment: "Folder color")
        }

        return button
    }

    @objc private func colorSwatchTapped(_ sender: UIButton) {
        if sender.tag == -1 {
            project.settings.folderColor = nil
        } else if FolderColor.allCases.indices.contains(sender.tag) {
            project.settings.folderColor = FolderColor.allCases[sender.tag]
        }

        project.saveSettings()
        LibraryNotifier.libraryDidChange()

        if let appearanceSectionIndex = appearanceSectionIndex {
            tableView.reloadRows(at: [IndexPath(row: 0, section: appearanceSectionIndex)], with: .none)
            tableView.reloadRows(at: [IndexPath(row: 1, section: appearanceSectionIndex)], with: .none)
        }
    }

    private func makeAppearanceIconCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = NSLocalizedString("Icon", comment: "")
        cell.selectionStyle = .default

        let iconName = project.settings.folderIcon ?? FolderIcon.defaultName
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let iconImageView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: symbolConfig))
        iconImageView.tintColor = project.settings.folderColor?.platformColor ?? .tintColor
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.contentMode = .scaleAspectFit
        chevron.widthAnchor.constraint(equalToConstant: 12).isActive = true

        let stack = UIStackView(arrangedSubviews: [iconImageView, chevron])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        cell.accessoryView = stack
        cell.accessibilityLabel = NSLocalizedString("Icon", comment: "")
        cell.accessibilityValue = iconName

        return cell
    }
}

