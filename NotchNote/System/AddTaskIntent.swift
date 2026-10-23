import AppIntents

/// Shortcuts / Siri / Spotlight action: "Add task".
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add task"
    static let description = IntentDescription("Create a new task (note) in NotchNote.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Title")
    var taskTitle: String

    @Parameter(title: "Notes", default: "")
    var notes: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = taskTitle
        let body = notes
        await MainActor.run {
            let store = TaskStore.shared
            store.loadAll()
            store.createTask(title: name, body: body, select: false)
            store.flush()
        }
        return .result(dialog: "Added \(name) to NotchNote.")
    }
}

struct NotchNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: ["Add a task in \(.applicationName)", "New \(.applicationName) task"],
            shortTitle: "Add task",
            systemImageName: "plus.circle"
        )
    }
}
