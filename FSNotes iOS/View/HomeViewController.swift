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
        actions.dailyNote = { UIApplication.getVC().openDailyNote() }
        actions.settings = { UIApplication.getVC().openSettings() }

        rootView = HomeView(model: model, actions: actions)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemBackground
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.setToolbarHidden(false, animated: animated)
        navigationController?.toolbar.tintColor = UIColor.mainTheme
        navigationController?.navigationBar.tintColor = UIColor.mainTheme

        model.reload()
    }

    // MARK: - Actions

    private func openSearch() {
        UIApplication.getVC().showSearchFromHome()
    }
}
