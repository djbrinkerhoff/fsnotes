//
//  LibraryNotifications.swift
//  FSNotes iOS
//
//  Notifications used by the Craft-style Home screen to stay in sync with
//  the note library (folders, tags, pinned notes) managed by the UIKit
//  controllers.
//

import Foundation

extension Notification.Name {
    /// Posted whenever folders, tags or notes are inserted, removed, pinned
    /// or reloaded. Observers should rebuild any derived library state.
    static let fsnotesLibraryDidChange = Notification.Name("es.fsnot.library.didChange")
}

enum LibraryNotifier {
    /// Coalesces bursts of changes into a single main-thread notification.
    private static var pending = false

    static func libraryDidChange() {
        DispatchQueue.main.async {
            guard !pending else { return }
            pending = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pending = false
                NotificationCenter.default.post(name: .fsnotesLibraryDidChange, object: nil)
            }
        }
    }
}
