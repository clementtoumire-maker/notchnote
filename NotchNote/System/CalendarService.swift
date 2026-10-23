import AppKit
import EventKit

/// Read-only calendar integration (EventKit). Shows the rest of today's events and creates / reopens one
/// meeting note per event. Nothing is written to the calendar and nothing leaves the Mac.
/// No entitlement is needed because the app is not sandboxed; the usage string lives in Info.plist.
@MainActor
final class CalendarService: NSObject, ObservableObject {
    static let shared = CalendarService()

    enum Access { case unknown, granted, denied }

    struct CalEvent: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let attendees: [String]
        let calendarTitle: String

        var subtitle: String {
            [calendarTitle, location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }
    }

    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var access: Access = .unknown

    private let store = EKEventStore()
    private let mapKey = "eventNoteMap"      // [eventID: taskUUID]
    private var observing = false

    private override init() { super.init() }

    func refreshAuthorization() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            startObserving()
            reload()
        case .denied, .restricted:
            access = .denied
        default:
            access = .unknown
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] ok, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.access = ok ? .granted : .denied
                    if ok { self.startObserving(); self.reload() }
                }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: .EKEventStoreChanged, object: store)
    }

    @objc private func storeChanged() { reload() }

    /// Events from now until the end of today (timed events that already ended are hidden).
    func reload() {
        guard access == .granted else { return }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? now.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.isAllDay || $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map { ev in
                CalEvent(id: ev.eventIdentifier ?? UUID().uuidString,
                         title: ev.title ?? "Untitled",
                         start: ev.startDate, end: ev.endDate, isAllDay: ev.isAllDay,
                         location: ev.location,
                         attendees: (ev.attendees ?? []).compactMap { $0.name },
                         calendarTitle: ev.calendar.title)
            }
    }

    // MARK: Meeting notes

    private var map: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: mapKey) }
    }

    func hasNote(for ev: CalEvent) -> Bool {
        guard let s = map[ev.id], let id = UUID(uuidString: s) else { return false }
        return TaskStore.shared.task(id) != nil
    }

    /// Returns the existing note for the event, or creates one.
    @discardableResult
    func noteTask(for ev: CalEvent) -> NoteTask {
        let store = TaskStore.shared
        if let s = map[ev.id], let id = UUID(uuidString: s), let existing = store.task(id) { return existing }

        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
        var body = "# \(ev.title)\n"
        body += ev.isAllDay ? "All day\n" : "\(f.string(from: ev.start)) \u{2013} \(f.string(from: ev.end))\n"
        if !ev.attendees.isEmpty { body += "With: \(ev.attendees.prefix(8).joined(separator: ", "))\n" }
        body += "\n- [ ] Agenda\n- [ ] Notes\n- [ ] Follow-ups\n"
        let t = store.createTask(title: ev.title, body: body, select: false)
        var m = map; m[ev.id] = t.id.uuidString; map = m
        return t
    }
}
