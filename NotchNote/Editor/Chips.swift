import AppKit

/// Inline chips (date, reminder, priority, tag, person, time estimate, repeat).
/// Stored in the Markdown file as `[[kind:value]]`; shown in the editor as one rounded attachment.
enum ChipKind: String, CaseIterable {
    case date, rem, prio, tag, person, est, rep

    var fill: NSColor {
        switch self {
        case .date:   return NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.38)
        case .rem:    return NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 0.38)
        case .prio:   return NSColor(srgbRed: 1.0, green: 0.27, blue: 0.23, alpha: 0.38)
        case .tag:    return NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 0.32)
        case .person: return NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 0.38)
        case .est:    return NSColor(white: 1.0, alpha: 0.18)
        case .rep:    return NSColor(srgbRed: 0.25, green: 0.78, blue: 0.88, alpha: 0.34)
        }
    }
}

struct ChipToken: Equatable {
    var kind: ChipKind
    var value: String

    var token: String { "[[\(kind.rawValue):\(value)]]" }

    static let isoFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()
    static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let shortDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
    private static let timeOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var label: String {
        switch kind {
        case .date:
            switch value {
            case "today": return "Today"
            case "tomorrow": return "Tomorrow"
            case "nextweek": return "Next week"
            default:
                if let d = Self.dayFormat.date(from: value) { return Self.shortDay.string(from: d) }
                return value
            }
        case .rem:
            if let d = Self.isoFormat.date(from: value) {
                let cal = Calendar.current
                if cal.isDateInToday(d) { return "\u{23F0} " + Self.timeOnly.string(from: d) }
                if cal.isDateInTomorrow(d) { return "\u{23F0} Tomorrow " + Self.timeOnly.string(from: d) }
                return "\u{23F0} " + Self.shortDay.string(from: d) + " " + Self.timeOnly.string(from: d)
            }
            return "\u{23F0} " + value
        case .prio:
            switch value { case "h": return "\u{2691} High"; case "m": return "\u{2691} Medium"; default: return "\u{2691} Low" }
        case .tag: return "#" + value
        case .person: return "@" + value
        case .est:
            let m = Int(value) ?? 0
            if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
            return "\(m)m"
        case .rep: return "\u{21BB} " + value
        }
    }

    /// Parse the word typed before a space ("today", "p1", "#work", "@sam", "30m").
    static func parseQuick(_ word: String) -> ChipToken? {
        let w = word.lowercased()
        if w == "today" || w == "tomorrow" { return ChipToken(kind: .date, value: w) }
        if w == "p1" { return ChipToken(kind: .prio, value: "h") }
        if w == "p2" { return ChipToken(kind: .prio, value: "m") }
        if w == "p3" { return ChipToken(kind: .prio, value: "l") }
        if w.count > 1, w.hasPrefix("#"), w.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
            return ChipToken(kind: .tag, value: String(w.dropFirst()))
        }
        if w.count > 1, w.hasPrefix("@"), w.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
            return ChipToken(kind: .person, value: String(w.dropFirst()))
        }
        if let r = w.range(of: "^[0-9]{1,3}(m|min|h)$", options: .regularExpression), r.lowerBound == w.startIndex {
            let digits = Int(w.prefix(while: { $0.isNumber })) ?? 0
            let minutes = w.hasSuffix("h") ? digits * 60 : digits
            if minutes > 0 { return ChipToken(kind: .est, value: String(minutes)) }
        }
        return nil
    }

    static let regex = try! NSRegularExpression(pattern: "\\[\\[(date|rem|prio|tag|person|est|rep):([^\\]\\n]+)\\]\\]")

    /// Distinct values of one kind found in a Markdown string (used to offer existing tags and people).
    static func values(of kind: ChipKind, in markdown: String) -> [String] {
        let ns = markdown as NSString
        var out: [String] = []
        for m in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            guard ChipKind(rawValue: ns.substring(with: m.range(at: 1))) == kind else { continue }
            let v = ns.substring(with: m.range(at: 2))
            if !out.contains(v) { out.append(v) }
        }
        return out
    }

    /// Plain text with `[[kind:value]]` tokens turned into chip attachments.
    static func attributed(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text)
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            guard let kind = ChipKind(rawValue: ns.substring(with: m.range(at: 1))) else { continue }
            let chip = ChipToken(kind: kind, value: ns.substring(with: m.range(at: 2)))
            out.replaceCharacters(in: m.range, with: NSAttributedString(attachment: ChipAttachment(chip, fontSize: fontSize)))
        }
        return out
    }
}

final class ChipAttachment: NSTextAttachment {
    let chip: ChipToken

    init(_ chip: ChipToken, fontSize: CGFloat) {
        self.chip = chip
        super.init(data: nil, ofType: nil)
        let img = ChipAttachment.render(chip, fontSize: fontSize)
        image = img
        bounds = CGRect(x: 0, y: -fontSize * 0.26, width: img.size.width, height: img.size.height)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func render(_ chip: ChipToken, fontSize: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: max(10, fontSize - 2.5), weight: .semibold)
        let text = NSAttributedString(string: chip.label, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = text.size()
        let h = ceil(fontSize + 3)
        let w = ceil(size.width) + 14
        let fill = chip.kind.fill
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
            text.draw(at: NSPoint(x: 7, y: (h - size.height) / 2))
            return true
        }
    }
}
