import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0

    private struct Page { let icon: String; let title: String; let lines: [String] }

    private let pages: [Page] = [
        Page(icon: "rectangle.topthird.inset.filled", title: "Your notes live in the notch",
             lines: ["Move the pointer to the notch (or the floating pill on displays without one) and the panel springs open.",
                     "Move away, press Esc, or click elsewhere and it folds back. Use the pin to keep it open.",
                     "It appears on every connected display."]),
        Page(icon: "checklist", title: "Write like Markdown",
             lines: ["# then space \u{2192} heading.   - then space \u{2192} bullet.   - [ ] then space \u{2192} checkbox.",
                     "Return continues a list; Return on an empty item ends it. Click a checkbox to tick it.",
                     "\u{2318}\u{21E7}L checklist \u{00B7} \u{2318}\u{21E7}B bullet \u{00B7} \u{2318}\u{21E7}H heading \u{00B7} \u{2318}Return tick \u{00B7} \u{2318}Z undo \u{00B7} \u{21E7}\u{2318}Z redo"]),
        Page(icon: "star", title: "Tasks, favorites and cards",
             lines: ["Each task is one note: a project, a meeting, a follow-up. Open the task window from the panel for search and drag-to-reorder.",
                     "\u{2318}\u{21E7}S adds or removes the current task from favorites.",
                     "Drag any text onto the notch to save it as a card, with copy and delete buttons."]),
        Page(icon: "bell.badge", title: "Reminders and sync",
             lines: ["If a task still has unchecked items, NotchNote reminds you at the interval you choose. Click the notification to open the task.",
                     "Reminders pause while your Mac is locked, asleep or in screen saver.",
                     "Pick a sync folder in Settings (for example in iCloud Drive) to share tasks across your Macs."])
    ]

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: pages[page].icon).font(.system(size: 44)).foregroundStyle(.tint)
            Text(pages[page].title).font(.title.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(pages[page].lines, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: 420, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 { Button("Back") { page -= 1 } }
                if page < pages.count - 1 {
                    Button("Next") { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") { onFinish() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 520, height: 420)
    }
}
