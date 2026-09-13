//
//  NoteCellView.swift
//  FSNotes iOS
//
//  Created by Oleksandr Glushchenko on 1/29/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import UIKit
import SwipeCellKit

class NoteCellView: SwipeTableViewCell {
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var date: UILabel!
    @IBOutlet weak var preview: UILabel!
    @IBOutlet weak var pin: UIImageView!

    @IBOutlet weak var imagePreview: UIImageView!
    @IBOutlet weak var imagePreviewSecond: UIImageView!
    @IBOutlet weak var imagePreviewThird: UIImageView!

    public var note: Note?
    public var contentLength: Int = 0
    public var timestamp: Int64?

    public var imageKeys = [String]()

    /// Craft-style "Display as" mode this cell is currently laid out for.
    /// Set by `NotesTableView.cellForRowAt` before `configure`/`fill` runs.
    public var displayMode: NoteListDisplayMode = .list

    public var tableView: NotesTableView? {
        get {
            return self.superview as? NotesTableView
        }
    }

    /// Craft-like card background shown behind the labels in `.cards` mode.
    /// Created once and toggled via `isHidden` rather than added/removed.
    private var cardView: UIView!

    private var didConfigureSelectionBackground = false
    private var didConfigureCardView = false

    override func awakeFromNib() {
        super.awakeFromNib()

        configureSelectionBackground()
        configureCardViewIfNeeded()
        backgroundColor = .clear
        title.adjustsFontForContentSizeCategory = true
        preview.adjustsFontForContentSizeCategory = true
        date.adjustsFontForContentSizeCategory = true

        // Keep the text column aligned with the page thumbnails in the library.
        for constraint in pin.constraints {
            if constraint.firstAttribute == .width { constraint.constant = 30 }
            if constraint.firstAttribute == .height { constraint.constant = 38 }
        }
        for constraint in contentView.constraints {
            if (constraint.firstItem as? UIView) === title,
               (constraint.secondItem as? UIView) === pin {
                constraint.constant = 12
            }
            if (constraint.firstItem as? UIView) === preview,
               constraint.firstAttribute == .top,
               (constraint.secondItem as? UIView) === pin {
                constraint.isActive = false
            }
        }
        preview.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3).isActive = true
        pin.contentMode = .center
        pin.layer.cornerRadius = 3
        pin.layer.borderWidth = 0.5
        pin.backgroundColor = .secondarySystemGroupedBackground
        pin.layer.borderColor = UIColor.separator.cgColor
        pin.isAccessibilityElement = false
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateCardAppearance()
            pin.layer.borderColor = UIColor.separator.cgColor
        }
    }

    private func configureCardViewIfNeeded() {
        guard !didConfigureCardView else { return }
        didConfigureCardView = true

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 14
        card.layer.masksToBounds = true
        card.isHidden = true
        card.isUserInteractionEnabled = false

        contentView.insertSubview(card, at: 0)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])

        cardView = card
        updateCardAppearance()
    }

    private func updateCardAppearance() {
        guard let cardView = cardView else { return }

        if traitCollection.userInterfaceStyle == .dark {
            cardView.backgroundColor = .secondarySystemGroupedBackground
            cardView.layer.borderWidth = 0
            cardView.layer.borderColor = nil
        } else {
            cardView.backgroundColor = .systemBackground
            cardView.layer.borderWidth = 1.0 / max(UIScreen.main.scale, 1)
            cardView.layer.borderColor = UIColor.separator.cgColor
        }
    }

    /// Lays the cell out for the given "Display as" mode. Call after
    /// `configure`/`attachHeaders` so the correct content is already set.
    public func applyDisplayMode(_ mode: NoteListDisplayMode) {
        displayMode = mode
        configureCardViewIfNeeded()

        switch mode {
        case .list:
            cardView.isHidden = true
            preview.isHidden = false
            preview.numberOfLines = 1
        case .compact:
            cardView.isHidden = true
            preview.isHidden = true
            preview.numberOfLines = 1
            hideAllImagePreviews()
        case .cards:
            cardView.isHidden = false
            preview.isHidden = false
            preview.numberOfLines = 3
        }

        applyHorizontalInsets(cards: mode == .cards)
    }

    /// The storyboard lays the text column out 30pt from the cell edge (with the
    /// glyph at 7pt). Inside a card that column has to move in so the glyph and
    /// text sit within the 16pt card inset.
    private func applyHorizontalInsets(cards: Bool) {
        let leading: CGFloat = cards ? 74 : 62
        let trailing: CGFloat = cards ? 30 : 20

        for constraint in contentView.constraints {
            guard let first = constraint.firstItem as? UIView else { continue }

            let isTextColumnLeading = constraint.firstAttribute == .leading
                && constraint.secondAttribute == .leading
                && (constraint.secondItem as? UIView) === contentView
                && (first === title || first === preview || first === imagePreview)

            if isTextColumnLeading {
                constraint.constant = leading
                continue
            }

            let isPreviewTrailing = constraint.firstAttribute == .trailing
                && (constraint.firstItem as? UIView) === contentView
                && (constraint.secondItem as? UIView) === preview

            if isPreviewTrailing {
                constraint.constant = trailing
            }
        }
    }

    /// Forces every image preview thumbnail hidden, used for `.compact` mode
    /// where images are never shown regardless of note content.
    public func hideAllImagePreviews() {
        imagePreview.image = nil
        imagePreview.isHidden = true

        imagePreviewSecond.image = nil
        imagePreviewSecond.isHidden = true

        imagePreviewThird.image = nil
        imagePreviewThird.isHidden = true

        imageKeys = []
    }

    private func configureSelectionBackground() {
        guard !didConfigureSelectionBackground else { return }
        didConfigureSelectionBackground = true

        let background = UIView()
        background.backgroundColor = UIColor.secondarySystemFill
        background.layer.cornerRadius = 10
        background.layer.masksToBounds = true

        let container = UIView()
        container.backgroundColor = .clear
        container.addSubview(background)
        background.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8)
        ])

        selectedBackgroundView = container
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imagePreview.image = nil
        imagePreviewSecond.image = nil
        imagePreviewThird.image = nil

        imagePreview.isHidden = true
        imagePreviewSecond.isHidden = true
        imagePreviewThird.isHidden = true
        
        contentLength = 0
        timestamp = nil

        note = nil
    }

    public func reLoad() {
        if let note = self.note {
            configure(note: note)
            applyDisplayMode(displayMode)
        }
    }

    func configure(note: Note) {
        self.note = note

        configureSelectionBackground()

        date.attributedText = NSAttributedString(string: getDate())

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        pin.contentMode = .scaleAspectFit
        pin.isHidden = false

        if note.isPublished() {
            pin.image = UIImage(systemName: "globe", withConfiguration: symbolConfig)
            pin.tintColor = UIColor.mainTheme
        } else if note.isEncrypted() {
            let name = note.isUnlocked() ? "lock.open" : "lock"
            pin.image = UIImage(systemName: name, withConfiguration: symbolConfig)
            pin.tintColor = UIColor.mainTheme
        } else if note.isPinned {
            pin.image = UIImage(systemName: "star.fill", withConfiguration: symbolConfig)
            pin.tintColor = UIColor.systemYellow
        } else {
            pin.image = UIImage(systemName: "doc.text", withConfiguration: symbolConfig)
            pin.tintColor = .secondaryLabel
        }

        let font = UIFont.systemFont(ofSize: 17, weight: .regular)
        let fontMetrics = UIFontMetrics(forTextStyle: .headline)
        let scaledFont = fontMetrics.scaledFont(for: font)
        title.font = scaledFont

        let dateFont = UIFont.systemFont(ofSize: 13, weight: .regular)
        let dateFontMetrics = UIFontMetrics(forTextStyle: .footnote)
        let dateScaledFont = dateFontMetrics.scaledFont(for: dateFont)
        date.font = dateScaledFont
        date.textColor = .tertiaryLabel

        let previewFont = UIFont.systemFont(ofSize: 15, weight: .regular)
        let previewFontMetrics = UIFontMetrics(forTextStyle: .subheadline)
        let previewScaledFont = previewFontMetrics.scaledFont(for: previewFont)
        preview.font = previewScaledFont
        preview.textColor = .secondaryLabel
    }

    public func getDate() -> String {
        if let sort = note?.project.settings.sortBy,
            sort == .creationDate,
            let date = note?.getCreationDateForLabel()
        {
            return date
        }

        if let date = note?.getDateForLabel() {
            return date
        }

        return String()
    }

    public func reloadDate() {
        date.text = getDate()
    }

    public func updateView() {
        if displayMode == .compact {
            hideAllImagePreviews()
        } else {
            loadImagesPreview()
        }

        if let note = self.note {
            attachHeaders(note: note)
        }

        reloadDate()
    }

    public func styleImageView(imageView: ImageView) {
        imageView.isHidden = false
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = Color.darkGray.cgColor
        imageView.layer.cornerRadius = 4
        imageView.clipsToBounds = true
    }

    public func attachHeaders(note: Note) {
        guard let title = note.getTitle() else {
            self.title.text = String()
            self.preview.text = String()
            return
        }

        self.title.text = title

        let showsFolder = tableView?.showsFolderInSubtitle ?? false
        let folder = note.project.getFullLabel()
        let snippet = note.preview.trimmingCharacters(in: .whitespacesAndNewlines)

        if showsFolder && !folder.isEmpty {
            self.preview.text = snippet.isEmpty ? folder : "\(folder) · \(snippet)"
        } else {
            self.preview.text = snippet
        }
    }

    public func getPreviewImage(imageUrl: URL, note: Note) -> Image? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MainNotesList")

        if !FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: false, attributes: nil)
        }

        if let cacheName = imageUrl.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)?.md5 {

            let file = tempURL.appendingPathComponent(cacheName)
            if FileManager.default.fileExists(atPath: file.path) {
                if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                    return image
                }
            }

            do {
                let data = try Data(contentsOf: imageUrl)
                if let image = UIImage(data: data) {
                    let size = CGRect(x: 0, y: 0, width: 70, height: 70)
                    if let resized = image.resize(height: 70)?.croppedInRect(rect: size) {
                        let jpegImageData = resized.jpegData(compressionQuality: 1)
                        try? jpegImageData?.write(to: file, options: .atomic)
                        return resized
                    }
                }
            } catch {
                print(error.localizedDescription)
            }
        }

        return nil
    }

    public func fixTopConstraint(position: Int?, note: Note) {
        for constraint in self.contentView.constraints {
            if ["firstImageTop", "secondImageTop", "thirdImageTop"].contains(constraint.identifier) {
                let ident = constraint.identifier
                self.contentView.removeConstraint(constraint)

                let isPreviewExist = note.preview.trim().count > 0
                var imageLink: UIImageView?

                switch constraint.identifier {
                case "firstImageTop":
                    imageLink = self.imagePreview
                case "secondImageTop":
                    imageLink = self.imagePreviewSecond
                case "thirdImageTop":
                    imageLink = self.imagePreviewThird
                default:
                    imageLink = self.imagePreview
                }

                guard let firstItem = imageLink else { continue }

                let secondItem = isPreviewExist ? self.preview : self.title
                let constr = NSLayoutConstraint(item: firstItem, attribute: .top, relatedBy: .equal, toItem: secondItem, attribute: .bottom, multiplier: 1, constant: 12)

                constr.identifier = ident
                self.contentView.addConstraint(constr)
            }
        }
    }
}
