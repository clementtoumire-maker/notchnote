import AppKit

/// NSTextView subclass implementing the Markdown-style editing behaviour.
///
/// Design notes
/// - The text shown in the editor uses single-glyph markers ("•", "☐", "☑"); `MarkdownCodec` maps them
///   to/from Markdown on load/save.
/// - Every programmatic change goes through `shouldChangeText` / `didChangeText`, so NSTextView's own
///   undo manager records it: Undo/Redo stay reliable, and undoing a "- " → "•" conversion gives "- " back.
/// - Shortcut conversions never run while an input method has marked (uncommitted) text, and never run
///   during undo/redo. That is what prevents duplicated list markers with Korean/Japanese/Chinese IME.
final class EditorTextView: NSTextView {
    var onActivate: (() -> Void)?
    var baseFontSize: CGFloat = 14
    var baseColor: NSColor = .white

    private var isProgrammaticEdit = false
    private var lastEditWasInsertion = false

    func configure() {
        isRichText = true                 // styling needs attributes; paste is forced to plain text below
        importsGraphics = false
        usesFontPanel = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        drawsBackground = false
        textContainerInset = NSSize(width: 6, height: 8)
        insertionPointColor = baseColor
    }

    // MARK: Loading

    func load(display: String, clearUndo: Bool, selection: NSRange? = nil) {
        undoManager?.disableUndoRegistration()
        string = display
        restyle()
        undoManager?.enableUndoRegistration()
        if clearUndo { undoManager?.removeAllActions() }
        let len = (string as NSString).length
        if let s = selection {
            let loc = min(s.location, len)
            setSelectedRange(NSRange(location: loc, length: min(s.length, len - loc)))
        }
    }

    // MARK: Change hooks

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        lastEditWasInsertion = !(replacementString ?? "").isEmpty
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func didChangeText() {
        let undoing = (undoManager?.isUndoing ?? false) || (undoManager?.isRedoing ?? false)
        if !isProgrammaticEdit, !undoing, !hasMarkedText(), lastEditWasInsertion {
            applyLineShortcut()
        }
        restyle()
        super.didChangeText()
    }

    /// Replace a range through the normal edit pipeline so it is undoable and delegate-visible.
    func replace(_ range: NSRange, with text: String) {
        let wasProgrammatic = isProgrammaticEdit
        isProgrammaticEdit = true
        defer { isProgrammaticEdit = wasProgrammatic }
        if shouldChangeText(in: range, replacementString: text) {
            textStorage?.replaceCharacters(in: range, with: text)
            didChangeText()
        }
    }

    private func applyLineShortcut() {
        guard selectedRange().length == 0 else { return }
        let ns = string as NSString
        let caret = selectedRange().location
        guard caret > 0, caret <= ns.length else { return }
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let prefix = ns.substring(with: NSRange(location: lineRange.location, length: caret - lineRange.location))
        guard let edit = MarkdownCodec.shortcut(forLinePrefix: prefix) else { return }
        let start = lineRange.location + edit.offset
        replace(NSRange(location: start, length: edit.length), with: edit.replacement)
        setSelectedRange(NSRange(location: start + (edit.replacement as NSString).length, length: 0))
    }

    // MARK: Return / Backspace / Tab

    override func insertNewline(_ sender: Any?) {
        // While an IME is composing, Return belongs to the IME (commit). Never touch it.
        if hasMarkedText() { super.insertNewline(sender); return }
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        let caretInLine = sel.location - lineRange.location

        switch MarkdownCodec.continuation(forLine: line) {
        case .none:
            super.insertNewline(sender)
        case .exit(let markerEnd):
            guard sel.length == 0, caretInLine >= markerEnd else { super.insertNewline(sender); return }
            replace(NSRange(location: lineRange.location, length: markerEnd), with: "")
            setSelectedRange(NSRange(location: lineRange.location, length: 0))
        case .next(let prefix, let contentStart):
            guard caretInLine >= contentStart else { super.insertNewline(sender); return }
            insertText("\n" + prefix, replacementRange: sel)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        if !hasMarkedText(), selectedRange().length == 0 {
            let ns = string as NSString
            let caret = selectedRange().location
            if caret > 0 {
                let lr = ns.lineRange(for: NSRange(location: caret, length: 0))
                let prefix = ns.substring(with: NSRange(location: lr.location, length: caret - lr.location))
                if let n = MarkdownCodec.markerOnlyPrefixLength(prefix) {
                    replace(NSRange(location: caret - n, length: n), with: "")
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    override func insertTab(_ sender: Any?) {
        if !hasMarkedText(), let lr = currentLineIfListItem() {
            replace(NSRange(location: lr.location, length: 0), with: "  ")
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if !hasMarkedText(), let lr = currentLineIfListItem() {
            let ns = string as NSString
            var n = 0
            while n < 2, lr.location + n < ns.length, ns.character(at: lr.location + n) == 32 { n += 1 }
            if n > 0 { replace(NSRange(location: lr.location, length: n), with: "") }
            return
        }
        super.insertBacktab(sender)
    }

    private func currentLineIfListItem() -> NSRange? {
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        var line = ns.substring(with: lr)
        if line.hasSuffix("\n") { line.removeLast() }
        return MarkdownCodec.parse(line).marker == nil ? nil : lr
    }

    // MARK: Line transforms (keyboard shortcuts)

    func transformSelectedLines(_ f: (String) -> String) {
        let ns = string as NSString
        let sel = selectedRange()
        var span = ns.lineRange(for: sel)
        if span.length > 0, ns.character(at: span.location + span.length - 1) == 10 { span.length -= 1 }
        let original = ns.substring(with: span)
        let transformed = original.components(separatedBy: "\n").map(f).joined(separator: "\n")
        guard transformed != original else { return }
        replace(span, with: transformed)
        let newLen = (transformed as NSString).length
        if sel.length == 0 {
            setSelectedRange(NSRange(location: span.location + newLen, length: 0))
        } else {
            setSelectedRange(NSRange(location: span.location, length: newLen))
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // The notch panel is a non-activating panel, so the app's main menu may not see these.
        // Handle the standard editing shortcuts here so they always work in the right window.
        if flags == .command {
            switch key {
            case "z": undoManager?.undo(); return true
            case "x": cut(nil); return true
            case "c": copy(nil); return true
            case "v": paste(nil); return true
            case "a": selectAll(nil); return true
            case "\r": transformSelectedLines(MarkdownCodec.togglingCheck); return true
            default: break
            }
        } else if flags == [.command, .shift] {
            switch key {
            case "z": undoManager?.redo(); return true
            case "l": transformSelectedLines(MarkdownCodec.togglingChecklist); return true
            case "b": transformSelectedLines(MarkdownCodec.togglingBullet); return true
            case "h": transformSelectedLines(MarkdownCodec.togglingHeading); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        // Esc: let the owning panel (if any) collapse. Does nothing in the task window.
        if let panel = window as? NotchPanel { panel.onEscape?() }
    }

    // MARK: Copy / paste in Markdown

    override func copy(_ sender: Any?) {
        let r = selectedRange()
        guard r.length > 0 else { return }
        let md = MarkdownCodec.toMarkdown((string as NSString).substring(with: r))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        let r = selectedRange()
        if r.length > 0 { replace(r, with: "") }
    }

    override func paste(_ sender: Any?) {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        let converted = MarkdownCodec.toDisplay(s.replacingOccurrences(of: "\r\n", with: "\n"))
        let range = selectedRange()
        isProgrammaticEdit = true
        insertText(converted, replacementRange: range)
        isProgrammaticEdit = false
    }

    // MARK: Checkbox clicks

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        let p = convert(event.locationInWindow, from: nil)
        if toggleCheckboxIfHit(at: p) { return }
        super.mouseDown(with: event)
    }

    private func toggleCheckboxIfHit(at point: NSPoint) -> Bool {
        let ns = string as NSString
        guard ns.length > 0 else { return false }
        let idx = min(characterIndexForInsertion(at: point), ns.length)
        let lr = ns.lineRange(for: NSRange(location: idx, length: 0))
        var line = ns.substring(with: lr)
        if line.hasSuffix("\n") { line.removeLast() }
        let parsed = MarkdownCodec.parse(line)
        guard parsed.marker == .unchecked || parsed.marker == .checked else { return false }
        let x = point.x - textContainerOrigin.x
        let indentWidth = CGFloat(parsed.indent.count) * baseFontSize * 0.28
        guard x >= 0, x < indentWidth + baseFontSize * 1.7 else { return false }
        transformSelectedLinesAt(lr, MarkdownCodec.togglingCheck)
        return true
    }

    private func transformSelectedLinesAt(_ lineRange: NSRange, _ f: (String) -> String) {
        let saved = selectedRange()
        setSelectedRange(NSRange(location: lineRange.location, length: 0))
        transformSelectedLines(f)
        setSelectedRange(NSRange(location: min(saved.location, (string as NSString).length), length: 0))
    }

    // MARK: Styling

    func restyle() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        let full = NSRange(location: 0, length: storage.length)
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: baseColor
        ]
        storage.beginEditing()
        storage.setAttributes(base, range: full)
        let ns = storage.string as NSString
        ns.enumerateSubstrings(in: full, options: [.byParagraphs]) { sub, range, _, _ in
            guard let line = sub, !line.isEmpty else { return }
            let parsed = MarkdownCodec.parse(line)
            let ps = NSMutableParagraphStyle()
            ps.lineSpacing = 2
            let indentWidth = CGFloat(parsed.indent.count) * self.baseFontSize * 0.28
            if let marker = parsed.marker {
                let markerLen = (marker.rawValue as NSString).length
                let indentLen = (parsed.indent as NSString).length
                ps.firstLineHeadIndent = 0
                ps.headIndent = indentWidth + self.baseFontSize * 1.6
                if marker == .checked {
                    let contentStart = range.location + indentLen + markerLen
                    let contentLen = range.length - indentLen - markerLen
                    if contentLen > 0 {
                        storage.addAttributes([
                            .foregroundColor: self.baseColor.withAlphaComponent(0.5),
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue
                        ], range: NSRange(location: contentStart, length: contentLen))
                    }
                    storage.addAttribute(.foregroundColor, value: NSColor.systemGreen,
                                         range: NSRange(location: range.location + indentLen, length: markerLen))
                }
            } else {
                let level = MarkdownCodec.headingLevel(line)
                if level > 0 {
                    let size = self.baseFontSize + CGFloat(5 - level) * 2.5
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .semibold), range: range)
                    ps.paragraphSpacingBefore = 4
                }
            }
            storage.addAttribute(.paragraphStyle, value: ps, range: range)
        }
        storage.endEditing()
        typingAttributes = base
    }
}
