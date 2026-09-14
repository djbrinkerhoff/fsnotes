import SwiftUI
import MarkdownEditorCore
import MarkdownEditorTextKit
#if canImport(UIKit)
import UIKit
import MarkdownEditorUIKit
#elseif canImport(AppKit)
import AppKit
import MarkdownEditorAppKit
#endif

/// Configuration shared by both platform representables.
public struct MarkdownEditorConfiguration {
    public var theme: ResolvedTheme
    public var onOpenLink: ((URL) -> Void)?
    public var onOpenWikiLink: ((String) -> Void)?
    public var onEditorDidChange: (() -> Void)?

    public init(theme: ResolvedTheme, onOpenLink: ((URL) -> Void)? = nil, onOpenWikiLink: ((String) -> Void)? = nil, onEditorDidChange: (() -> Void)? = nil) {
        self.theme = theme
        self.onOpenLink = onOpenLink
        self.onOpenWikiLink = onOpenWikiLink
        self.onEditorDidChange = onEditorDidChange
    }
}

/// SwiftUI host for the native Markdown editor. The view is created once and kept stable;
/// changing `session` swaps documents, changing `configuration.theme` restyles in place.
public struct MarkdownEditorView {
    public var session: EditorSession
    public var configuration: MarkdownEditorConfiguration

    public init(session: EditorSession, configuration: MarkdownEditorConfiguration) {
        self.session = session
        self.configuration = configuration
    }

    @MainActor
    public final class Coordinator {
        #if canImport(UIKit)
        var adapter: UIKitEditorAdapter?
        #elseif canImport(AppKit)
        var adapter: AppKitEditorAdapter?
        #endif
    }

    @MainActor
    private func configure(_ coordinator: Coordinator) {
        guard let adapter = coordinator.adapter else { return }
        adapter.onOpenLink = configuration.onOpenLink
        adapter.onOpenWikiLink = configuration.onOpenWikiLink
        adapter.onEditorDidChange = configuration.onEditorDidChange
    }
}

#if canImport(UIKit)
extension MarkdownEditorView: UIViewRepresentable {
    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView(frame: .zero, theme: configuration.theme)
        let adapter = UIKitEditorAdapter(textView: textView, session: session, theme: configuration.theme)
        context.coordinator.adapter = adapter
        configure(context.coordinator)
        return textView
    }

    public func updateUIView(_ uiView: MarkdownTextView, context: Context) {
        guard let adapter = context.coordinator.adapter else { return }
        if adapter.session !== session { adapter.setSession(session) }
        if adapter.theme.bodyFont != configuration.theme.bodyFont || adapter.theme.codeFont != configuration.theme.codeFont {
            adapter.theme = configuration.theme
        }
        configure(context.coordinator)
    }
}
#elseif canImport(AppKit)
extension MarkdownEditorView: NSViewRepresentable {
    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = MarkdownTextView.makeScrollableEditor(theme: configuration.theme)
        let adapter = AppKitEditorAdapter(textView: textView, session: session, theme: configuration.theme)
        context.coordinator.adapter = adapter
        configure(context.coordinator)
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let adapter = context.coordinator.adapter else { return }
        if adapter.session !== session { adapter.setSession(session) }
        if adapter.theme.bodyFont != configuration.theme.bodyFont || adapter.theme.codeFont != configuration.theme.codeFont {
            adapter.theme = configuration.theme
        }
        configure(context.coordinator)
    }
}
#endif
