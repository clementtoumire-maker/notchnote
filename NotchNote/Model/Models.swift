import Foundation

enum StorageLocation: String, Codable, CaseIterable {
    case local
    case sync
}

/// One note ("task"): a project, a meeting, a follow-up. `body` is Markdown source.
struct NoteTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = "Untitled"
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isFavorite: Bool = false
    var favoriteOrder: Int = 0
    var remindersEnabled: Bool = true

    /// Where the file lives. Derived from the folder it was loaded from, never written into the file.
    var location: StorageLocation = .local

    enum CodingKeys: String, CodingKey {
        case id, title, body, createdAt, updatedAt, isFavorite, favoriteOrder, remindersEnabled
    }

    var uncheckedCount: Int { MarkdownCodec.checklistCounts(markdown: body).unchecked }
    var checkedCount: Int { MarkdownCodec.checklistCounts(markdown: body).checked }
    var summary: String { MarkdownCodec.summaryLine(markdown: body) }
}

/// A snippet dragged onto the notch.
struct Card: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
}
