import SwiftUI

/// The separate task window: searchable, collapsible sidebar; drag-to-reorder; favorites; task summaries.
struct TaskWindowView: View {
    @ObservedObject private var store = TaskStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var search = ""
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            detail
        }
        .frame(minWidth: 620, minHeight: 380)
        .alert("NotchNote", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
    }

    // MARK: Sidebar

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private var filtered: [NoteTask] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.tasks }
        return store.tasks.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tasks", text: $search).textFieldStyle(.plain)
                if isSearching {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding([.horizontal, .top], 10)
            .padding(.bottom, 6)

            List(selection: $store.selectedID) {
                if !isSearching, !store.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(store.favorites) { t in row(t).tag(t.id) }
                            .onMove { store.moveFavorites(fromOffsets: $0, toOffset: $1) }
                    }
                }
                Section(isSearching ? "Results" : "All tasks") {
                    ForEach(filtered) { t in row(t).tag(t.id) }
                        .onMove { from, to in
                            if !isSearching { store.moveTasks(fromOffsets: from, toOffset: to) }
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()
            bottomBar
        }
    }

    private func row(_ t: NoteTask) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(t.title.isEmpty ? "Untitled" : t.title).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                if t.location == .sync { Image(systemName: "icloud").font(.caption).foregroundStyle(.secondary).help("Stored in the sync folder") }
                if t.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
            }
            HStack(spacing: 6) {
                let total = t.uncheckedCount + t.checkedCount
                if total > 0 {
                    Label("\(t.checkedCount)/\(total)", systemImage: "checklist")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(t.uncheckedCount == 0 ? Color.green : Color.secondary)
                }
                Text(t.summary.isEmpty ? "No content" : t.summary)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(t.isFavorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(t.id) }
            if t.location == .local {
                Button("Move to Sync Folder") { store.move(t.id, to: .sync) }
            } else {
                Button("Move to Local Storage") { store.move(t.id, to: .local) }
            }
            Divider()
            Button("Move to Trash", role: .destructive) { store.deleteTask(t.id) }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { store.createTask() } label: { Label("New Task", systemImage: "plus") }
                .help("New task (\u{2318}N)")
            Spacer()
            Button {
                if let id = store.selectedID { store.toggleFavorite(id) }
            } label: {
                Label(store.selectedTask?.isFavorite == true ? "Unfavorite" : "Favorite",
                      systemImage: store.selectedTask?.isFavorite == true ? "star.fill" : "star")
            }
            .help("Add or remove from favorites (\u{2318}\u{21E7}S)")
            .disabled(store.selectedTask == nil)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(10)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let t = store.selectedTask {
            VStack(spacing: 0) {
                HStack {
                    TextField("Title", text: Binding(get: { store.task(t.id)?.title ?? "" },
                                                     set: { store.setTitle(t.id, $0) }))
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Menu {
                        Toggle("Reminders for this task", isOn: Binding(get: { store.task(t.id)?.remindersEnabled ?? true },
                                                                        set: { v in store.update(t.id) { $0.remindersEnabled = v } }))
                        Divider()
                        if t.location == .local {
                            Button("Move to Sync Folder") { store.move(t.id, to: .sync) }
                        } else {
                            Button("Move to Local Storage") { store.move(t.id, to: .local) }
                        }
                        Button("Move to Trash", role: .destructive) { store.deleteTask(t.id) }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).frame(width: 30)
                }
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 6)

                Divider()

                MarkdownEditor(documentID: t.id,
                               markdown: Binding(get: { store.task(t.id)?.body ?? "" },
                                                 set: { store.setBody(t.id, $0) }),
                               textColor: .labelColor,
                               fontSize: 15)
                    .padding(.horizontal, 10)

                Divider()
                HStack {
                    Text(t.location == .sync ? "Sync folder" : "Local")
                    Text("\u{00B7}")
                    Text("Edited \(t.updatedAt.formatted(.relative(presentation: .named)))")
                    Spacer()
                    Text("# heading  \u{00B7}  - bullet  \u{00B7}  - [ ] checkbox  \u{00B7}  \u{2318}\u{21E7}L checklist")
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.secondary)
                Text("Select or create a task").foregroundStyle(.secondary)
            }
        }
    }
}
