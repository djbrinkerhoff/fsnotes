//
//  HomeViewController.swift
//  FSNotes iOS
//
//  Hosts the SwiftUI Home screen inside the existing UIKit navigation stack
//  and forwards user actions to the notes list controller.
//

import UIKit
import SwiftUI

final class HomeViewController: UIHostingController<HomeView> {
    private let model = HomeLibraryModel()

    init() {
        var actions = HomeActions()
        super.init(rootView: HomeView(model: model, actions: actions))

        actions.search = { [weak self] in self?.openSearch() }
        actions.openSidebarItem = { item in UIApplication.getVC().showLibrary(item: item) }
        actions.openFolder = { project in UIApplication.getVC().showLibrary(project: project) }
        actions.openTag = { tag in UIApplication.getVC().showLibrary(tag: tag) }
        actions.openNote = { note in UIApplication.getVC().openFromHome(note: note) }
        actions.newNote = { project in UIApplication.getVC().createNoteFromHome(in: project) }
        actions.folderSettings = { project in UIApplication.getVC().openFolderSettingsFromHome(project: project) }

        rootView = HomeView(model: model, actions: actions)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Home", comment: "Home screen title")
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = NSLocalizedString("Settings", comment: "")

        configureToolbar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.setToolbarHidden(false, animated: animated)
        navigationController?.toolbar.tintColor = UIColor.mainTheme
        navigationController?.navigationBar.tintColor = UIColor.mainTheme

        model.reload()
    }

    private func configureToolbar() {
        let daily = UIBarButtonItem(
            image: UIImage(systemName: "calendar"),
            style: .plain,
            target: self,
            action: #selector(openDailyNote)
        )
        daily.accessibilityLabel = NSLocalizedString("Daily Note", comment: "")

        let search = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(openSearchAction)
        )
        search.accessibilityLabel = NSLocalizedString("Search", comment: "")

        let newNote = Buttons.getNewNote(target: self, selector: #selector(createNote))
        newNote.accessibilityLabel = NSLocalizedString("New Note", comment: "")

        toolbarItems = [daily, .flexibleSpace(), search, .flexibleSpace(), newNote]
    }

    // MARK: - Actions

    private func openSearch() {
        UIApplication.getVC().showSearchFromHome()
    }

    @objc private func openSearchAction() {
        openSearch()
    }

    @objc private func openSettings() {
        UIApplication.getVC().openSettings()
    }

    @objc private func openDailyNote() {
        UIApplication.getVC().openDailyNote()
    }

    @objc private func createNote() {
        UIApplication.getVC().createNoteFromHome(in: nil)
    }
}
