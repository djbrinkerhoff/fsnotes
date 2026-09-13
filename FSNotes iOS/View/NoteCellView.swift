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

    public var tableView: NotesTableView? {
        get {
            return self.superview as? NotesTableView
        }
    }

    private var didConfigureSelectionBackground = false

    override func awakeFromNib() {
        super.awakeFromNib()

        configureSelectionBackground()
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
            pin.image = UIImage(systemName: "pin.fill", withConfiguration: symbolConfig)
            pin.tintColor = UIColor.mainTheme
        } else {
            pin.image = UIImage(systemName: "doc.text", withConfiguration: symbolConfig)
            pin.tintColor = .secondaryLabel
        }

        let font = UIFont.systemFont(ofSize: 16, weight: .semibold)
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
        loadImagesPreview()

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
        if let title = note.getTitle() {
            self.title.text = title
            self.preview.text = note.preview
        } else {
            self.title.text = String()
            self.preview.text = String()
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
