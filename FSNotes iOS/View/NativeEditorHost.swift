//
//  NativeEditorHost.swift
//  FSNotes iOS
//
//  Hosts the TextKit 2 hidden-syntax Markdown editor (MarkdownEditor package) over the legacy
//  EditTextView. Active only when UserDefaultsManagement.useNativeMarkdownEditor is on.
//

import UIKit
import MarkdownEditorCore
import MarkdownEditorTextKit
import MarkdownEditorUIKit

@MainActor
final class NativeEditorHost {
    weak var controller: EditorViewController?

    private(set) var textView: MarkdownTextView?
    private(set) var adapter: UIKitEditorAdapter?
    private(set) var session: EditorSession?
    private(set) var note: Note?
    private weak var legacy: UITextView?
    private var rowRefreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    static var isEnabled: Bool { UserDefaultsManagement.useNativeMarkdownEditor }

    var isActive: Bool { note != nil && textView?.isHidden == false }

    init(controller: EditorViewController) {
        self.controller = controller
        observers.append(NotificationCenter.default.addObserver(forName: .fsnotesNoteDidReloadExternally, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.noteDidReloadExternally(notification) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .fsnotesNoteConflictDetected, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.noteConflictDetected(notification) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    static func makeTheme() -> ResolvedTheme {
        var theme = MarkdownEditorCore.EditorTheme.default
        theme.lineHeightMultiple = 1.25
        theme.textInsetHorizontal = 16
        theme.textInsetVertical = 28
        return ResolvedTheme(theme: theme, palette: .system, bodyFont: UserDefaultsManagement.noteFont, codeFont: UserDefaultsManagement.codeFont)
    }

    // MARK: Showing notes

    @discardableResult
    func show(note: Note, legacy: UITextView) -> Bool {
        guard note.isMarkdown(), note.container != .encryptedTextPack || note.isUnlocked(), let source = note.loadSource() else {
            hide()
            return false
        }
        ensureViews(legacy: legacy)
        guard let adapter, let textView else { return false }

        if let previous = self.note, previous !== note { previous.flushPendingSave() }
        self.note = note
        let mode: EditorMode = UserDefaultsManagement.nativeEditorSourceMode ? .source : .rich
        let session = EditorSession(source: source, parser: CommonMarkLineParser(), builder: PresentationBuilder(), mode: mode, undoManager: note.undoManager)
        self.session = session
        adapter.setSession(session)
        adapter.onEditorDidChange = { [weak self] in self?.editorDidChange() }
        adapter.onOpenLink = { url in UIApplication.shared.open(url) }
        adapter.onOpenWikiLink = { [weak self] target in self?.controller?.openWikiLink(query: target) }

        legacy.isHidden = true
        textView.isHidden = false
        textView.isEditable = note.container != .encryptedTextPack || note.isUnlocked()
        textView.inputAccessoryView = legacy.inputAccessoryView
        textView.backgroundColor = legacy.backgroundColor
        return true
    }

    func hide() {
        note?.flushPendingSave()
        note = nil
        session = nil
        textView?.isHidden = true
        legacy?.isHidden = false
    }

    private func ensureViews(legacy: UITextView) {
        self.legacy = legacy
        guard textView == nil, let container = legacy.superview else { return }
        let text = MarkdownTextView(frame: legacy.frame, theme: Self.makeTheme())
        text.translatesAutoresizingMaskIntoConstraints = false
        container.insertSubview(text, aboveSubview: legacy)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: legacy.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: legacy.trailingAnchor),
            text.topAnchor.constraint(equalTo: legacy.topAnchor),
            text.bottomAnchor.constraint(equalTo: legacy.bottomAnchor),
        ])
        text.autocorrectionType = UserDefaultsManagement.editorAutocorrection ? .yes : .no
        text.spellCheckingType = UserDefaultsManagement.editorSpellChecking ? .yes : .no
        let session = EditorSession(source: "", parser: CommonMarkLineParser(), builder: PresentationBuilder())
        adapter = UIKitEditorAdapter(textView: text, session: session, theme: Self.makeTheme())
        textView = text
    }

    // MARK: Changes

    private func editorDidChange() {
        guard let note, let session else { return }
        note.scheduleSave(source: session.source)
        rowRefreshTimer?.invalidate()
        rowRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let note = self?.note else { return }
                UIApplication.getVC().notesTable.reloadRowForce(note: note)
            }
        }
    }

    func applyTheme() {
        adapter?.theme = Self.makeTheme()
    }

    func toggleSourceMode() {
        guard let session else { return }
        session.toggleMode()
        UserDefaultsManagement.nativeEditorSourceMode = session.mode == .source
    }

    var isSourceMode: Bool { session?.mode == .source }

    // MARK: External changes

    private func noteDidReloadExternally(_ notification: Notification) {
        guard let changed = notification.object as? Note, changed === note, let session, let source = changed.loadSource() else { return }
        session.replaceSource(with: source)
    }

    private func noteConflictDetected(_ notification: Notification) {
        guard let changed = notification.object as? Note, changed === note, let session else { return }
        if let source = changed.loadSource() { session.replaceSource(with: source) }
        var message = NSLocalizedString("Your unsaved version was kept as a separate conflict note.", comment: "")
        if let url = notification.userInfo?["conflictURL"] as? URL { message += "\n" + url.lastPathComponent }
        let alert = UIAlertController(title: NSLocalizedString("This note changed outside FSNotes", comment: ""), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        controller?.present(alert, animated: true)
    }
}
