import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes tasks in Spotlight (CoreSpotlight). Selecting a result launches the app with an
/// NSUserActivity of type CSSearchableItemActionType, handled in AppDelegate.
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    static let domain = "com.clement.NotchNote.tasks"

    private var pending: [UUID: NoteTask] = [:]
    private var work: DispatchWorkItem?

    func index(_ tasks: [NoteTask]) {
        let items = tasks.map(Self.item(for:))
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error { NSLog("NotchNote: Spotlight index failed: %@", error.localizedDescription) }
        }
    }

    /// Debounced: typing in a note flushes every 0.5 s, so coalesce Spotlight updates to every 3 s.
    func indexSoon(_ tasks: [NoteTask]) {
        for t in tasks { pending[t.id] = t }
        work?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let batch = Array(self.pending.values)
            self.pending.removeAll()
            self.index(batch)
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    func remove(_ ids: [UUID]) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map { $0.uuidString }) { _ in }
    }

    private static func item(for t: NoteTask) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = t.title
        attrs.contentDescription = t.summary
        attrs.textContent = t.body
        attrs.contentModificationDate = t.updatedAt
        let item = CSSearchableItem(uniqueIdentifier: t.id.uuidString, domainIdentifier: domain, attributeSet: attrs)
        item.expirationDate = .distantFuture
        return item
    }
}
