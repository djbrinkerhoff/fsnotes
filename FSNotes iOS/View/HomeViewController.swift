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
        actions.dailyNote = { UIApplication.getVC().showDailyNotes() }
        actions.settings = { UIApplication.getVC().openSettings() }
        actions.openStarred = { [weak self] in self?.pushStarred() }
        actions.openFolders = { [weak self] in self?.pushFolders(parent: nil) }
        actions.openTags = { [weak self] in self?.pushTags() }
        actions.openTodo = { [weak self] in
            if let todo = self?.model.quickLinks.first(where: { $0.sidebarItem.type == .Todo }) {
                UIApplication.getVC().showLibrary(item: todo.sidebarItem)
            }
        }
        actions.openFolder = { [weak self] project in
            guard let self else { return }
            if self.model.hasChildren(project) {
                self.pushFolders(parent: project)
            } else {
                UIApplication.getVC().showLibrary(project: project)
            }
        }

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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Give the window a moment to become key after launch before presenting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.presentOnboardingIfNeeded()
        }
    }

    // MARK: - Onboarding

    private func presentOnboardingIfNeeded() {
        guard !UserDefaultsManagement.didShowOnboarding,
              presentedViewController == nil,
              navigationController?.topViewController === self,
              view.window != nil else { return }

        let onboarding = UIHostingController(rootView: OnboardingView { [weak self] in
            UserDefaultsManagement.didShowOnboarding = true
            self?.dismiss(animated: true)
        })
        onboarding.isModalInPresentation = true
        onboarding.modalPresentationStyle = .pageSheet

        present(onboarding, animated: true)
    }

    // MARK: - Library screens

    private func pushStarred() {
        let screen = StarredScreen(model: model) { note in
            UIApplication.getVC().openFromHome(note: note)
        }
        push(LibraryScreenViewController(rootView: screen) { [weak self] in self?.model.reload() })
    }

    private func pushFolders(parent: Project?) {
        let screen = FoldersScreen(
            model: model,
            parent: parent,
            openNotes: { project in UIApplication.getVC().showLibrary(project: project) },
            openChildren: { [weak self] project in self?.pushFolders(parent: project) },
            newNote: { project in UIApplication.getVC().createNoteFromHome(in: project) },
            folderSettings: { project in UIApplication.getVC().openFolderSettingsFromHome(project: project) }
        )
        push(LibraryScreenViewController(rootView: screen) { [weak self] in self?.model.reload() })
    }

    private func pushTags() {
        let screen = TagsScreen(model: model) { tag in
            UIApplication.getVC().showLibrary(tag: tag)
        }
        push(LibraryScreenViewController(rootView: screen) { [weak self] in self?.model.reload() })
    }

    private func push(_ controller: UIViewController) {
        (navigationController ?? UIApplication.getNC())?.pushViewController(controller, animated: true)
    }

    // MARK: - Actions

    private func openSearch() {
        UIApplication.getVC().showSearchFromHome()
    }
}
