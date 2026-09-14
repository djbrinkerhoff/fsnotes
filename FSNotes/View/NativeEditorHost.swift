//
//  NativeEditorHost.swift
//  FSNotes
//
//  Hosts the TextKit 2 hidden-syntax Markdown editor (MarkdownEditor package) next to the
//  legacy EditTextView. Active only when UserDefaultsManagement.useNativeMarkdownEditor is on.
//

import AppKit
import MarkdownEditorCore
import MarkdownEditorTextKit
import MarkdownEditorAppKit

@MainActor
final class NativeEditorHost: NSObject {
    weak var editorViewController: EditorViewController?

    private(set) var scrollView: NSScrollView?
    private(set) var textView: MarkdownTextView?
    private(set) var adapter: AppKitEditorAdapter?
    private(set) var session: EditorSession?
    private(set) var note: Note?
    private weak var legacyScrollView: NSScrollView?
    private var rowRefreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    static var isEnabled: Bool { UserDefaultsManagement.useNativeMarkdownEditor }

    /// True while a note is shown in the native editor.
    var isActive: Bool { note != nil && scrollView?.isHidden == false }

    init(editorViewController: EditorViewController) {
        self.editorViewController = editorViewController
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: .fsnotesNoteDidReloadExternally, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.noteDidReloadExternally(notification) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .fsnotesNoteConflictDetected, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.noteConflictDetected(notification) }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Menu

    /// Adds the native editor menu items to the main menu once.
    static func installMenuItems() {
        guard let mainMenu = NSApp.mainMenu else { return }
        func submenu(_ identifier: String, fallbackTitle: String) -> NSMenu? {
            mainMenu.items.first { $0.submenu?.identifier?.rawValue == identifier }?.submenu
                ?? mainMenu.items.first { $0.title == fallbackTitle }?.submenu
        }
        if let view = submenu("viewMenu", fallbackTitle: "View"), !view.items.contains(where: { $0.identifier?.rawValue == "fsnotes.nativeEditor" }) {
            let previewIndex = view.items.firstIndex { $0.action == #selector(EditorViewController.togglePreview(_:)) } ?? -1
            let native = NSMenuItem(title: NSLocalizedString("Native Markdown Editor", comment: ""), action: #selector(EditorViewController.toggleNativeMarkdownEditor(_:)), keyEquivalent: "")
            native.identifier = NSUserInterfaceItemIdentifier("fsnotes.nativeEditor")
            let source = NSMenuItem(title: NSLocalizedString("Show Markdown Source", comment: ""), action: #selector(EditorViewController.toggleMarkdownSourceMode(_:)), keyEquivalent: "u")
            source.keyEquivalentModifierMask = [.command, .option]
            source.identifier = NSUserInterfaceItemIdentifier("fsnotes.markdownSource")
            view.insertItem(source, at: previewIndex + 1)
            view.insertItem(native, at: previewIndex + 1)
        }
        if let edit = submenu("editMenu", fallbackTitle: "Edit"), !edit.items.contains(where: { $0.identifier?.rawValue == "fsnotes.copyMarkdown" }) {
            let copyIndex = edit.items.firstIndex { $0.action == #selector(NSText.copy(_:)) } ?? -1
            let item = NSMenuItem(title: NSLocalizedString("Copy Markdown", comment: ""), action: NSSelectorFromString("copyMarkdown:"), keyEquivalent: "c")
            item.keyEquivalentModifierMask = [.command, .option]
            item.identifier = NSUserInterfaceItemIdentifier("fsnotes.copyMarkdown")
            edit.insertItem(item, at: copyIndex + 1)
        }
    }

    // MARK: Theme

    static func makeTheme() -> ResolvedTheme {
        var theme = MarkdownEditorCore.EditorTheme.default
        theme.lineHeightMultiple = max(1.0, Double(UserDefaultsManagement.lineHeightMultiple))
        theme.textInsetHorizontal = Double(UserDefaultsManagement.marginSize)
        return ResolvedTheme(theme: theme, palette: .system, bodyFont: UserDefaultsManagement.noteFont, codeFont: UserDefaultsManagement.codeFont)
    }

    // MARK: Showing notes

    /// Shows `note` in the native editor, hiding `legacy`. Returns false when the note cannot be edited natively.
    @discardableResult
    func show(note: Note, legacy: NSScrollView) -> Bool {
        guard note.isMarkdown(), note.container != .encryptedTextPack || note.isUnlocked(), let source = note.loadSource() else {
            hide()
            return false
        }
        ensureViews(legacy: legacy)
        guard let adapter else { return false }
        let theme = Self.makeTheme()
        if adapter.theme.bodyFont != theme.bodyFont || adapter.theme.codeFont != theme.codeFont { adapter.theme = theme }

        if let previous = self.note, previous !== note { previous.flushPendingSave() }
        self.note = note
        let mode: EditorMode = UserDefaultsManagement.nativeEditorSourceMode ? .source : .rich
        let session = EditorSession(source: source, parser: CommonMarkLineParser(), builder: PresentationBuilder(), mode: mode, undoManager: note.undoManager)
        self.session = session
        adapter.setSession(session)
        adapter.onEditorDidChange = { [weak self] in self?.editorDidChange() }
        adapter.onOpenLink = { url in NSWorkspace.shared.open(url) }
        adapter.onOpenWikiLink = { [weak self] target in self?.openWikiLink(target) }
        editorViewController?.editorUndoManager = note.undoManager

        legacy.isHidden = true
        scrollView?.isHidden = false
        textView?.isEditable = note.container != .encryptedTextPack || note.isUnlocked()
        if let point = Optional(note.getContentOffset()), point != .zero {
            scrollView?.contentView.scroll(to: point)
        }
        return true
    }

    /// Hides the native editor and shows the legacy one again.
    func hide() {
        note?.flushPendingSave()
        note = nil
        session = nil
        scrollView?.isHidden = true
        legacyScrollView?.isHidden = false
    }

    func makeFirstResponder() {
        if let textView { textView.window?.makeFirstResponder(textView) }
    }

    private func ensureViews(legacy: NSScrollView) {
        legacyScrollView = legacy
        if scrollView == nil {
            let (scroll, text) = MarkdownTextView.makeScrollableEditor(theme: Self.makeTheme())
            scroll.frame = legacy.frame
            scroll.autoresizingMask = legacy.autoresizingMask
            scroll.translatesAutoresizingMaskIntoConstraints = legacy.translatesAutoresizingMaskIntoConstraints
            legacy.superview?.addSubview(scroll, positioned: .above, relativeTo: legacy)
            if !scroll.translatesAutoresizingMaskIntoConstraints {
                NSLayoutConstraint.activate([
                    scroll.leadingAnchor.constraint(equalTo: legacy.leadingAnchor),
                    scroll.trailingAnchor.constraint(equalTo: legacy.trailingAnchor),
                    scroll.topAnchor.constraint(equalTo: legacy.topAnchor),
                    scroll.bottomAnchor.constraint(equalTo: legacy.bottomAnchor),
                ])
            }
            text.isContinuousSpellCheckingEnabled = UserDefaultsManagement.continuousSpellChecking
            text.isGrammarCheckingEnabled = UserDefaultsManagement.grammarChecking
            text.isAutomaticSpellingCorrectionEnabled = UserDefaultsManagement.automaticSpellingCorrection
            let session = EditorSession(source: "", parser: CommonMarkLineParser(), builder: PresentationBuilder())
            adapter = AppKitEditorAdapter(textView: text, session: session, theme: Self.makeTheme())
            scrollView = scroll
            textView = text
        }
    }

    // MARK: Changes

    private func editorDidChange() {
        guard let note, let session else { return }
        note.scheduleSave(source: session.source)
        rowRefreshTimer?.invalidate()
        rowRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let note = self?.note else { return }
                ViewController.shared()?.notesTableView.reloadRow(note: note)
                self?.editorViewController?.updateTitle(note: note)
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

    private func openWikiLink(_ target: String) {
        guard let vc = ViewController.shared() else { return }
        if let note = Storage.shared().getBy(title: target) ?? Storage.shared().getBy(titleOrName: target) {
            vc.notesTableView.setSelected(note: note)
        }
    }

    // MARK: External changes

    private func noteDidReloadExternally(_ notification: Notification) {
        guard let changed = notification.object as? Note, changed === note, let session, let source = changed.loadSource() else { return }
        session.replaceSource(with: source)
    }

    private func noteConflictDetected(_ notification: Notification) {
        guard let changed = notification.object as? Note, changed === note, let session else { return }
        if let source = changed.loadSource() { session.replaceSource(with: source) }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("This note changed outside FSNotes", comment: "")
        var info = NSLocalizedString("Your unsaved version was kept as a separate conflict note.", comment: "")
        if let url = notification.userInfo?["conflictURL"] as? URL { info += "\n" + url.lastPathComponent }
        alert.informativeText = info
        if let window = editorViewController?.view.window {
            alert.beginSheetModal(for: window)
        }
    }
}
