//
//  FolderIconPickerViewController.swift
//  FSNotes iOS
//
//  Craft-style folder icon picker pushed from Folder Settings' Appearance
//  section. Presents `FolderIcon.choices` (plus a leading "Default" entry)
//  in a 6-column grid; tapping an icon saves it on the folder and pops back.
//

import UIKit

class FolderIconPickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let project: Project
    private let icons: [String]

    private var collectionView: UICollectionView!

    private static let reuseIdentifier = "folderIconCell"
    private static let columns = 6

    init(project: Project) {
        self.project = project
        self.icons = FolderIcon.choices

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Icon", comment: "Folder settings")
        view.backgroundColor = .systemGroupedBackground

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.dataSource = self
        cv.delegate = self
        cv.register(FolderIconCell.self, forCellWithReuseIdentifier: Self.reuseIdentifier)

        view.addSubview(cv)
        NSLayoutConstraint.activate([
            cv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        collectionView = cv
    }

    // "Default" is a synthetic first entry that maps to `FolderIcon.defaultName`,
    // not a member of `FolderIcon.choices`... unless it already is (it's also
    // the first item in `choices`), in which case we simply reuse it.
    private func iconName(at indexPath: IndexPath) -> String {
        return indexPath.item == 0 ? FolderIcon.defaultName : icons[indexPath.item - 1]
    }

    private func isSelected(at indexPath: IndexPath) -> Bool {
        let current = project.settings.folderIcon ?? FolderIcon.defaultName
        return iconName(at: indexPath) == current
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return icons.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseIdentifier, for: indexPath) as! FolderIconCell

        let name = iconName(at: indexPath)
        let tint = project.settings.folderColor?.platformColor ?? .tintColor

        cell.configure(symbolName: name, isSelected: isSelected(at: indexPath), tintColor: tint)
        cell.accessibilityLabel = indexPath.item == 0
            ? NSLocalizedString("Default", comment: "Folder icon")
            : name

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let name = iconName(at: indexPath)
        project.settings.folderIcon = (name == FolderIcon.defaultName) ? nil : name
        project.saveSettings()
        LibraryNotifier.libraryDidChange()

        navigationController?.popViewController(animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout
        let insets = flowLayout?.sectionInset ?? .zero
        let spacing = flowLayout?.minimumInteritemSpacing ?? 0

        let availableWidth = collectionView.bounds.width - insets.left - insets.right - spacing * CGFloat(Self.columns - 1)
        let side = floor(availableWidth / CGFloat(Self.columns))

        return CGSize(width: max(side, 44), height: max(side, 44))
    }
}

private class FolderIconCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let background = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isAccessibilityElement = true

        background.translatesAutoresizingMaskIntoConstraints = false
        background.layer.cornerRadius = 10

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit

        contentView.addSubview(background)
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            background.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),

            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(symbolName: String, isSelected: Bool, tintColor: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        imageView.image = UIImage(systemName: symbolName, withConfiguration: config)

        if isSelected {
            background.backgroundColor = tintColor.withAlphaComponent(0.16)
            imageView.tintColor = tintColor
        } else {
            background.backgroundColor = .clear
            imageView.tintColor = .label
        }
    }
}
