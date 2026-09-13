//
//  DailyNotesViewController.swift
//  FSNotes iOS
//
//  Hosts the SwiftUI daily notes screen in the UIKit navigation stack.
//

import UIKit
import SwiftUI

final class DailyNotesViewController: UIHostingController<DailyNotesView> {
    private let model = DailyNotesModel()

    init() {
        super.init(rootView: DailyNotesView(model: model) { date in
            UIApplication.getVC().openDailyNote(for: date)
        })
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setToolbarHidden(true, animated: animated)
        model.reload()
    }
}
