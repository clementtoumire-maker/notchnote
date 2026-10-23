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
        textStorage?.setAttributedString(ChipToken.attributed(display, fontSize: baseFontSize))
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
            applyQuickToken()
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

    func replaceAttributed(_ range: NSRange, with att: NSAttributedString) {
        let wasProgrammatic = isProgrammaticEdit
        isProgrammaticEdit = true
        defer { isProgrammaticEdit = wasProgrammatic }
        if shouldChangeText(in: range, replacementString: att.string) {
            textStorage?.replaceCharacters(in: range, with: att)
            didChangeText()
        }
    }

    /// Typing "today ", "p1 ", "#work ", "@sam " or "30m " turns the word into a chip.
    private func applyQuickToken() {
        guard selectedRange().length == 0 else { return }
        let ns = string as NSString
        let caret = selectedRange().location
        guard caret >= 2, caret <= ns.length, ns.character(at: caret - 1) == 32 else { return }
        var start = caret - 1
        while start > 0 {
            let c = ns.character(at: start - 1)
            if c == 32 || c == 10 { break }
            start -= 1
        }
        guard caret - 1 > start else { return }
        let word = ns.substring(with: NSRange(location: start, length: caret - 1 - start))
        guard let chip = ChipToken.parseQuick(word) else { return }
        let att = NSMutableAttributedString(attributedString: NSAttributedString(attachment: ChipAttachment(chip, fontSize: baseFontSize)))
        att.append(NSAttributedString(string: " "))
        replaceAttributed(NSRange(location: start, length: caret - start), with: att)
        setSelectedRange(NSRange(location: start + 2, length: 0))
    }

    func insertChip(_ chip: ChipToken) {
        let att = NSMutableAttributedString(attributedString: NSAttributedString(attachment: ChipAttachment(chip, fontSize: baseFontSize)))
        att.append(NSAttributedString(string: " "))
        let r = selectedRange()
        replaceAttributed(r, with: att)
        setSelectedRange(NSRange(location: r.location + 2, length: 0))
        window?.makeFirstResponder(self)
    }

    // MARK: Serialising (chips back to tokens, glyphs back to Markdown)

    func serialize(_ range: NSRange) -> String {
        guard let st = textStorage, range.length > 0 else { return "" }
        let ns = st.string as NSString
        var out = ""
        st.enumerateAttribute(.attachment, in: range, options: []) { v, r, _ in
            if let a = v as? ChipAttachment { out += a.chip.token } else { out += ns.substring(with: r) }
        }
        return MarkdownCodec.toMarkdown(out)
    }

    func markdownText() -> String { serialize(NSRange(location: 0, length: (string as NSString).length)) }

    // MARK: Inline formatting (Markdown-style markers, styled live in restyle)

    /// Wrap the selection in `open`/`close`, or remove them when it is already wrapped.
    func toggleInline(_ open: String, _ close: String) {
        let ns = string as NSString
        let sel = selectedRange()
        let o = (open as NSString).length, c = (close as NSString).length
        if sel.length > 0 {
            let inner = ns.substring(with: sel)
            if inner.hasPrefix(open), inner.hasSuffix(close), sel.length >= o + c {
                let stripped = String(inner.dropFirst(open.count).dropLast(close.count))
                replace(sel, with: stripped)
                setSelectedRange(NSRange(location: sel.location, length: (stripped as NSString).length))
                return
            }
            if sel.location >= o, sel.location + sel.length + c <= ns.length,
               ns.substring(with: NSRange(location: sel.location - o, length: o)) == open,
               ns.substring(with: NSRange(location: sel.location + sel.length, length: c)) == close {
                replace(NSRange(location: sel.location + sel.length, length: c), with: "")
                replace(NSRange(location: sel.location - o, length: o), with: "")
                setSelectedRange(NSRange(location: sel.location - o, length: sel.length))
                return
            }
            replace(sel, with: open + inner + close)
            setSelectedRange(NSRange(location: sel.location + o, length: sel.length))
        } else {
            replace(sel, with: open + close)
            setSelectedRange(NSRange(location: sel.location + o, length: 0))
        }
        window?.makeFirstResponder(self)
    }

    /// Choose a font family for the selection (Sans removes any family tag).
    func setFontTag(_ tag: String?) {
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        var text = (string as NSString).substring(with: sel)
        for t in ["book", "mono", "round"] {
            text = text.replacingOccurrences(of: "<\(t)>", with: "").replacingOccurrences(of: "</\(t)>", with: "")
        }
        if let tag { text = "<\(tag)>" + text + "</\(tag)>" }
        replace(sel, with: text)
        setSelectedRange(NSRange(location: sel.location, length: (text as NSString).length))
        window?.makeFirstResponder(self)
    }

    func clearFormatting() {
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        let text = MarkdownCodec.stripInline((string as NSString).substring(with: sel))
        replace(sel, with: text)
        setSelectedRange(NSRange(location: sel.location, length: (text as NSString).length))
    }

    func toggleLineKind(_ f: @escaping (String) -> String) {
        transformSelectedLines(f)
        window?.makeFirstResponder(self)
    }

    // MARK: Checking an item moves it to the bottom of its list

    /// Toggle the checkbox on the line containing `location`. A checked item drops to the end of its list;
    /// an unchecked one goes back above the checked items. One undo step.
    func toggleCheckAndSort(at location: Int) {
        let ns = string as NSString
        let lines = ns.components(separatedBy: "\n")
        var offsets: [Int] = []
        var pos = 0
        for l in lines { offsets.append(pos); pos += (l as NSString).length + 1 }
        var idx = 0
        for (i, o) in offsets.enumerated() where o <= location { idx = i }
        func isItem(_ i: Int) -> Bool {
            let m = MarkdownCodec.parse(lines[i]).marker
            return m == .unchecked || m == .checked
        }
        guard isItem(idx) else { return }
        var a = idx, b = idx
        while a > 0, isItem(a - 1) { a -= 1 }
        while b < lines.count - 1, isItem(b + 1) { b += 1 }
        var block = Array(lines[a...b])
        let k = idx - a
        let toggled = MarkdownCodec.togglingCheck(block[k])
        let nowChecked = MarkdownCodec.parse(toggled).marker == .checked
        block.remove(at: k)
        if !AppSettings.shared.sortCheckedToBottom {
            block.insert(toggled, at: k)
        } else if nowChecked {
            block.append(toggled)
        } else {
            let firstChecked = block.firstIndex { MarkdownCodec.parse($0).marker == .checked } ?? block.count
            block.insert(toggled, at: firstChecked)
        }
        let start = offsets[a]
        let end = offsets[b] + (lines[b] as NSString).length
        let saved = selectedRange()
        replace(NSRange(location: start, length: end - start), with: block.joined(separator: "\n"))
        setSelectedRange(NSRange(location: min(saved.location, (string as NSString).length), length: 0))
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
            case "\r": toggleCheckAndSort(at: selectedRange().location); return true
            case "b": toggleInline("**", "**"); return true
            case "i": toggleInline("*", "*"); return true
            case "u": toggleInline("<u>", "</u>"); return true
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
        let md = serialize(r)
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
        insertText(ChipToken.attributed(converted, fontSize: baseFontSize), replacementRange: range)
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
        toggleCheckAndSort(at: lr.location)
        return true
    }

    private func transformSelectedLinesAt(_ lineRange: NSRange, _ f: (String) -> String) {
        let saved = selectedRange()
        setSelectedRange(NSRange(location: lineRange.location, length: 0))
        transformSelectedLines(f)
        setSelectedRange(NSRange(location: min(saved.location, (string as NSString).length), length: 0))
    }

    // MARK: Styling

    private static let yellow = NSColor(srgbRed: 1.0, green: 0.84, blue: 0.04, alpha: 1)

    func restyle() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        let full = NSRange(location: 0, length: storage.length)
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: baseFontSize),
            .foregroundColor: baseColor
        ]
        storage.beginEditing()
        for key in [NSAttributedString.Key.font, .foregroundColor, .strikethroughStyle, .underlineStyle, .backgroundColor, .paragraphStyle] {
            storage.removeAttribute(key, range: full)
        }
        storage.addAttributes(base, range: full)
        let ns = storage.string as NSString
        ns.enumerateSubstrings(in: full, options: [.byParagraphs]) { sub, range, _, _ in
            guard let line = sub, !line.isEmpty else { return }
            let parsed = MarkdownCodec.parse(line)
            let ps = NSMutableParagraphStyle()
            ps.lineSpacing = 3
            let indentWidth = CGFloat(parsed.indent.count) * self.baseFontSize * 0.28
            if let marker = parsed.marker {
                let markerLen = (marker.rawValue as NSString).length
                let indentLen = (parsed.indent as NSString).length
                let markerRange = NSRange(location: range.location + indentLen, length: markerLen)
                ps.firstLineHeadIndent = 0
                ps.headIndent = indentWidth + self.baseFontSize * 1.7
                switch marker {
                case .unchecked:
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: self.baseFontSize + 3),
                                           .foregroundColor: self.baseColor.withAlphaComponent(0.65)], range: markerRange)
                case .checked:
                    let contentStart = range.location + indentLen + markerLen
                    let contentLen = range.length - indentLen - markerLen
                    if contentLen > 0 {
                        storage.addAttributes([
                            .foregroundColor: self.baseColor.withAlphaComponent(0.42),
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: self.baseColor.withAlphaComponent(0.35)
                        ], range: NSRange(location: contentStart, length: contentLen))
                    }
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: self.baseFontSize + 3),
                                           .foregroundColor: EditorTextView.yellow], range: markerRange)
                case .bullet:
                    break
                }
            } else {
                let level = MarkdownCodec.headingLevel(line)
                if level > 0 {
                    let size = self.baseFontSize + CGFloat(5 - level) * 2.5
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: range)
                    ps.paragraphSpacingBefore = 4
                }
            }
            storage.addAttribute(.paragraphStyle, value: ps, range: range)
        }
        applyInlineStyles(storage, full)
        storage.endEditing()
        typingAttributes = base
    }

    private func applyInlineStyles(_ storage: NSTextStorage, _ full: NSRange) {
        func design(_ d: NSFontDescriptor.SystemDesign) -> (NSFont) -> NSFont {
            return { f in
                let desc = f.fontDescriptor.withDesign(d) ?? f.fontDescriptor
                return NSFont(descriptor: desc, size: f.pointSize) ?? f
            }
        }
        func trait(_ t: NSFontTraitMask) -> (NSFont) -> NSFont {
            return { NSFontManager.shared.convert($0, toHaveTrait: t) }
        }
        let fallback = NSFont.systemFont(ofSize: baseFontSize)
        func mapFont(_ range: NSRange, _ f: (NSFont) -> NSFont) {
            var runs: [(NSRange, NSFont)] = []
            storage.enumerateAttribute(.font, in: range, options: []) { v, r, _ in
                runs.append((r, (v as? NSFont) ?? fallback))
            }
            for (r, font) in runs { storage.addAttribute(.font, value: f(font), range: r) }
        }
        let dim = baseColor.withAlphaComponent(0.28)
        func style(_ pattern: String, _ apply: (NSRange) -> Void) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            let text = storage.string
            re.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
                guard let m, m.numberOfRanges > 1 else { return }
                let inner = m.range(at: 1)
                guard inner.length > 0 else { return }
                apply(inner)
                let end = m.range.location + m.range.length
                storage.addAttribute(.foregroundColor, value: dim,
                                     range: NSRange(location: m.range.location, length: inner.location - m.range.location))
                storage.addAttribute(.foregroundColor, value: dim,
                                     range: NSRange(location: inner.location + inner.length, length: end - inner.location - inner.length))
            }
        }
        style("<book>(.+?)</book>") { mapFont($0, design(.serif)) }
        style("<mono>(.+?)</mono>") { mapFont($0, design(.monospaced)) }
        style("<round>(.+?)</round>") { mapFont($0, design(.rounded)) }
        style("\\*\\*(.+?)\\*\\*") { mapFont($0, trait(.boldFontMask)) }
        style("(?<![\\*\\w])\\*(?![\\*\\s])(.+?)(?<![\\*\\s])\\*(?![\\*\\w])") { mapFont($0, trait(.italicFontMask)) }
        style("<u>(.+?)</u>") { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: $0) }
        style("~~(.+?)~~") { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: $0) }
        style("==(.+?)==") { storage.addAttribute(.backgroundColor, value: NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 0.38), range: $0) }
    }
}
