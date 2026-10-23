import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String, line: Int = #line) {
    if cond { print("PASS \(name)") } else { print("FAIL \(name) (line \(line))"); failures += 1 }
}

// Markdown <-> display round trips
let md = "# Title\n- bullet\n- [ ] todo\n- [x] done\n  - [ ] nested\nplain"
let disp = MarkdownCodec.toDisplay(md)
check(disp == "# Title\n\u{2022} bullet\n\u{25CB} todo\n\u{25CF} done\n  \u{25CB} nested\nplain", "toDisplay converts markers and keeps indent")
check(MarkdownCodec.toMarkdown(disp) == md, "round trip is lossless")
check(MarkdownCodec.toMarkdown(MarkdownCodec.toDisplay("* star bullet")) == "- star bullet", "* bullet normalises to -")
check(MarkdownCodec.toDisplay("") == "", "empty document")

// Typing shortcuts
func sc(_ s: String) -> String? { MarkdownCodec.shortcut(forLinePrefix: s)?.replacement }
check(sc("- ") == "\u{2022} ", "'- ' becomes bullet")
check(sc("\u{2022} [ ] ") == "\u{25CB} ", "'• [ ] ' becomes checkbox (typed after the '- ' conversion)")
check(sc("- [ ] ") == "\u{25CB} ", "'- [ ] ' becomes checkbox when pasted/typed at once")
check(sc("[] ") == "\u{25CB} ", "'[] ' becomes checkbox")
check(sc("\u{2022} [x] ") == "\u{25CF} ", "'• [x] ' becomes checked")
check(sc("- a") == nil, "'- a' is not a shortcut")
check(sc("text - ") == nil, "dash in the middle of text is untouched")
check(sc("\u{25CB} ") == nil, "an existing marker does not convert again (no duplicate markers)")
check(MarkdownCodec.shortcut(forLinePrefix: "  - ")?.offset == 2, "indent is preserved")

// Return behaviour
check(MarkdownCodec.continuation(forLine: "\u{25CB} buy milk") == .next(prefix: "\u{25CB} ", contentStart: 2), "return after unchecked continues unchecked")
check(MarkdownCodec.continuation(forLine: "\u{25CF} done") == .next(prefix: "\u{25CB} ", contentStart: 2), "return after checked continues unchecked")
check(MarkdownCodec.continuation(forLine: "\u{2022} ") == .exit(markerEnd: 2), "return on empty item exits the list")
check(MarkdownCodec.continuation(forLine: "  \u{25CB} x") == .next(prefix: "  \u{25CB} ", contentStart: 4), "indent is carried to the next item")
check(MarkdownCodec.continuation(forLine: "plain") == .none, "plain line: default newline")

// Backspace
check(MarkdownCodec.markerOnlyPrefixLength("\u{25CB} ") == 2, "backspace removes whole marker")
check(MarkdownCodec.markerOnlyPrefixLength("\u{25CB} a") == nil, "backspace after content is normal")

// Toggles
check(MarkdownCodec.togglingChecklist("item") == "\u{25CB} item", "checklist toggle adds")
check(MarkdownCodec.togglingChecklist("\u{25CF} item") == "item", "checklist toggle removes")
check(MarkdownCodec.togglingCheck("\u{25CB} item") == "\u{25CF} item", "tick")
check(MarkdownCodec.togglingCheck("\u{25CF} item") == "\u{25CB} item", "untick")
check(MarkdownCodec.togglingHeading("x") == "# x" && MarkdownCodec.togglingHeading("# x") == "x", "heading toggle")
check(MarkdownCodec.togglingBullet("\u{25CB} x") == "\u{2022} x", "bullet replaces checkbox")
check(MarkdownCodec.headingLevel("## Hi") == 2 && MarkdownCodec.headingLevel("#Hi") == 0, "heading level")

// Summaries
check(MarkdownCodec.checklistCounts(markdown: md) == (2, 1), "checklist counts")
check(MarkdownCodec.summaryLine(markdown: "\n# Plan\nx") == "Plan", "summary strips heading marker")
check(MarkdownCodec.firstUncheckedText(markdown: md) == "todo", "first unchecked text")

if failures == 0 { print("\nALL SELFTESTS PASSED"); exit(0) } else { print("\n\(failures) FAILED"); exit(1) }
