import SwiftUI
import AppKit

/// SwiftUI wrapper around `EditorTextView`. `markdown` is the stored Markdown; the text view
/// shows the glyph form (see MarkdownCodec).
struct MarkdownEditor: NSViewRepresentable {
    var documentID: UUID
    @Binding var markdown: String
    var textColor: NSColor
    var fontSize: CGFloat = 14
    var onActivate: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay

        let size = scroll.contentSize
        let tv = EditorTextView(frame: NSRect(origin: .zero, size: size))
        tv.configure()
        tv.minSize = NSSize(width: 0, height: size.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        tv.baseColor = textColor
        tv.baseFontSize = fontSize
        tv.insertionPointColor = textColor
        tv.onActivate = onActivate
        tv.delegate = context.coordinator
        scroll.documentView = tv

        context.coordinator.documentID = documentID
        context.coordinator.lastMarkdown = markdown
        tv.load(display: MarkdownCodec.toDisplay(markdown), clearUndo: true)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? EditorTextView else { return }
        let c = context.coordinator
        c.parent = self
        tv.onActivate = onActivate

        if tv.baseColor != textColor || tv.baseFontSize != fontSize {
            tv.baseColor = textColor
            tv.baseFontSize = fontSize
            tv.insertionPointColor = textColor
            tv.restyle()
        }

        if c.documentID != documentID {
            // Switched to another task: new text, fresh undo history.
            c.documentID = documentID
            c.lastMarkdown = markdown
            tv.load(display: MarkdownCodec.toDisplay(markdown), clearUndo: true)
        } else if markdown != c.lastMarkdown, !tv.hasMarkedText() {
            // Changed from outside (sync folder, another window). Keep the caret where it was.
            c.lastMarkdown = markdown
            tv.load(display: MarkdownCodec.toDisplay(markdown), clearUndo: false, selection: tv.selectedRange())
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var documentID: UUID?
        var lastMarkdown = ""

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? EditorTextView, !tv.hasMarkedText() else { return }
            let md = tv.markdownText()
            guard md != lastMarkdown else { return }
            lastMarkdown = md
            parent.markdown = md
        }
    }
}

extension NSView {
    /// Depth-first search for the first editor in a view tree.
    func findEditor() -> EditorTextView? {
        if let e = self as? EditorTextView { return e }
        for v in subviews { if let e = v.findEditor() { return e } }
        return nil
    }
}
