import Foundation

/// Visual list markers used inside the editor. On disk the note is plain Markdown
/// ("- ", "- [ ] ", "- [x] "); in the editor these become single glyphs so a checkbox
/// is one character that can be clicked, deleted and undone as a unit.
enum ListMarker: String, CaseIterable {
    case bullet = "\u{2022} "      // "• "
    case unchecked = "\u{25CB} "   // "○ "
    case checked = "\u{25CF} "     // "● "

    var markdownPrefix: String {
        switch self {
        case .bullet: return "- "
        case .unchecked: return "- [ ] "
        case .checked: return "- [x] "
        }
    }
}

struct ParsedLine {
    var indent: String
    var marker: ListMarker?
    var content: String
}

enum LineContinuation: Equatable {
    case none
    /// Empty list item: remove [0, markerEnd) of the line instead of adding a new item.
    case exit(markerEnd: Int)
    /// Non-empty list item: start the next line with `prefix`; caret must be >= contentStart.
    case next(prefix: String, contentStart: Int)
}

/// Pure string logic for the editor. No AppKit, so it can be unit-tested with plain `swiftc`
/// (see scripts/selftest.sh).
enum MarkdownCodec {

    // MARK: Markdown <-> display

    static func toDisplay(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n").map(displayLine).joined(separator: "\n")
    }

    static func toMarkdown(_ display: String) -> String {
        display.components(separatedBy: "\n").map(markdownLine).joined(separator: "\n")
    }

    static func displayLine(_ line: String) -> String {
        let indent = leadingWhitespace(line)
        let rest = String(line.dropFirst(indent.count))
        if rest.hasPrefix("- [ ] ") { return indent + ListMarker.unchecked.rawValue + String(rest.dropFirst(6)) }
        if rest == "- [ ]" { return indent + ListMarker.unchecked.rawValue }
        if rest.hasPrefix("- [x] ") || rest.hasPrefix("- [X] ") { return indent + ListMarker.checked.rawValue + String(rest.dropFirst(6)) }
        if rest == "- [x]" || rest == "- [X]" { return indent + ListMarker.checked.rawValue }
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") { return indent + ListMarker.bullet.rawValue + String(rest.dropFirst(2)) }
        return line
    }

    static func markdownLine(_ line: String) -> String {
        let p = parse(line)
        guard let m = p.marker else { return line }
        return p.indent + m.markdownPrefix + p.content
    }

    // MARK: Parsing

    static func leadingWhitespace(_ line: String) -> String {
        String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    static func parse(_ line: String) -> ParsedLine {
        let indent = leadingWhitespace(line)
        let rest = String(line.dropFirst(indent.count))
        for m in ListMarker.allCases where rest.hasPrefix(m.rawValue) {
            return ParsedLine(indent: indent, marker: m, content: String(rest.dropFirst(m.rawValue.count)))
        }
        return ParsedLine(indent: indent, marker: nil, content: rest)
    }

    /// 0 = not a heading, 1...3 = "# ", "## ", "### "
    static func headingLevel(_ line: String) -> Int {
        let p = parse(line)
        guard p.marker == nil else { return 0 }
        for level in 1...3 where p.content.hasPrefix(String(repeating: "#", count: level) + " ") { return level }
        return 0
    }

    // MARK: Typing shortcuts

    /// `prefix` is the text from the start of the line to the caret. Returns the edit to apply
    /// (offset/length are UTF-16 units relative to the line start), or nil.
    static func shortcut(forLinePrefix prefix: String) -> (offset: Int, length: Int, replacement: String)? {
        let indent = String(prefix.prefix(while: { $0 == " " }))
        let rest = String(prefix.dropFirst(indent.count))
        let offset = (indent as NSString).length
        let length = (rest as NSString).length
        switch rest {
        case "- ", "* ":
            return (offset, length, ListMarker.bullet.rawValue)
        case "- [ ] ", "- [] ", "[ ] ", "[] ", "\u{2022} [ ] ", "\u{2022} [] ", "* [ ] ":
            return (offset, length, ListMarker.unchecked.rawValue)
        case "- [x] ", "- [X] ", "[x] ", "[X] ", "\u{2022} [x] ", "\u{2022} [X] ", "* [x] ":
            return (offset, length, ListMarker.checked.rawValue)
        default:
            return nil
        }
    }

    static func continuation(forLine line: String) -> LineContinuation {
        let p = parse(line)
        guard let m = p.marker else { return .none }
        let contentStart = (p.indent as NSString).length + (m.rawValue as NSString).length
        if p.content.trimmingCharacters(in: .whitespaces).isEmpty { return .exit(markerEnd: contentStart) }
        let next: ListMarker = (m == .checked) ? .unchecked : m
        return .next(prefix: p.indent + next.rawValue, contentStart: contentStart)
    }

    /// If `prefix` (line start to caret) is exactly indent + marker, returns the marker length in
    /// UTF-16 units so Backspace can remove the whole marker at once.
    static func markerOnlyPrefixLength(_ prefix: String) -> Int? {
        let p = parse(prefix)
        guard let m = p.marker, p.content.isEmpty else { return nil }
        return (m.rawValue as NSString).length
    }

    // MARK: Line toggles (keyboard shortcuts)

    static func togglingBullet(_ line: String) -> String { toggling(line, to: .bullet) }

    static func togglingChecklist(_ line: String) -> String {
        let p = parse(line)
        if p.marker == .unchecked || p.marker == .checked { return p.indent + p.content }
        return toggling(line, to: .unchecked)
    }

    static func togglingCheck(_ line: String) -> String {
        let p = parse(line)
        switch p.marker {
        case .unchecked?: return p.indent + ListMarker.checked.rawValue + p.content
        case .checked?: return p.indent + ListMarker.unchecked.rawValue + p.content
        default: return line
        }
    }

    static func togglingHeading(_ line: String) -> String {
        let p = parse(line)
        if p.marker == nil {
            for level in 1...3 {
                let hashes = String(repeating: "#", count: level) + " "
                if p.content.hasPrefix(hashes) { return p.indent + String(p.content.dropFirst(hashes.count)) }
            }
        }
        return p.indent + "# " + p.content
    }

    private static func toggling(_ line: String, to kind: ListMarker) -> String {
        let p = parse(line)
        if p.marker == kind { return p.indent + p.content }
        return p.indent + kind.rawValue + p.content
    }

    // MARK: Summaries (used by NoteTask)

    static func checklistCounts(markdown: String) -> (unchecked: Int, checked: Int) {
        var u = 0, c = 0
        for raw in markdown.components(separatedBy: "\n") {
            let rest = raw.drop(while: { $0 == " " || $0 == "\t" })
            if rest.hasPrefix("- [ ]") { u += 1 }
            else if rest.hasPrefix("- [x]") || rest.hasPrefix("- [X]") { c += 1 }
        }
        return (u, c)
    }

    static func firstUncheckedText(markdown: String) -> String? {
        for raw in markdown.components(separatedBy: "\n") {
            let rest = String(raw.drop(while: { $0 == " " || $0 == "\t" }))
            if rest.hasPrefix("- [ ]") {
                let t = String(rest.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let clean = stripInline(t)
                if !clean.isEmpty { return clean }
            }
        }
        return nil
    }

    static func summaryLine(markdown: String) -> String {
        for raw in markdown.components(separatedBy: "\n") {
            var s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "### ", "## ", "# "] where s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)); break
            }
            return stripInline(s)
        }
        return ""
    }

    /// Removes chip tokens and inline-style markers so summaries and notifications read as plain text.
    static func stripInline(_ s: String) -> String {
        var t = s
        let patterns = ["\\[\\[[a-z]+:[^\\]\\n]+\\]\\]", "</?(u|book|mono|round)>", "\\*\\*", "~~", "=="]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
