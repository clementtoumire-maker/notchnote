import AppKit
import Combine
import UserNotifications

/// Periodic "you still have unchecked items" notifications.
///
/// One repeating timer; it is invalidated (not just ignored) while the Mac is asleep, the screens
/// are asleep, the session is locked/inactive or the screen saver runs, so there is no background
/// work then. When the Mac is ready again the interval starts fresh instead of firing a burst.
@MainActor
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()

    private var timer: Timer?
    private var pauseReasons = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    func start() {
        guard !started, Bundle.main.bundleIdentifier != nil else { return }
        started = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let actions = [
            UNNotificationAction(identifier: "snooze15", title: "Snooze 15 min", options: []),
            UNNotificationAction(identifier: "snooze60", title: "Snooze 1 hour", options: []),
            UNNotificationAction(identifier: "tomorrow", title: "Tomorrow", options: []),
            UNNotificationAction(identifier: "done", title: "Done", options: [])
        ]
        center.setNotificationCategories([UNNotificationCategory(identifier: "reminder", actions: actions, intentIdentifiers: [], options: [])])

        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.willSleepNotification, pause: "sleep")
        observe(ws, NSWorkspace.didWakeNotification, resume: "sleep")
        observe(ws, NSWorkspace.screensDidSleepNotification, pause: "screens")
        observe(ws, NSWorkspace.screensDidWakeNotification, resume: "screens")
        observe(ws, NSWorkspace.sessionDidResignActiveNotification, pause: "session")
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification, resume: "session")

        let dc = DistributedNotificationCenter.default()
        observe(dc, Notification.Name("com.apple.screenIsLocked"), pause: "locked")
        observe(dc, Notification.Name("com.apple.screenIsUnlocked"), resume: "locked")
        observe(dc, Notification.Name("com.apple.screensaver.didstart"), pause: "screensaver")
        observe(dc, Notification.Name("com.apple.screensaver.didstop"), resume: "screensaver")

        AppSettings.shared.$reminderIntervalMinutes.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reschedule() } }
        }.store(in: &cancellables)

        reschedule()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, pause reason: String) {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseReasons.insert(reason); self?.reschedule() }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, resume reason: String) {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseReasons.remove(reason); self?.reschedule() }
        }
    }

    var isPaused: Bool { !pauseReasons.isEmpty }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        let minutes = AppSettings.shared.reminderIntervalMinutes
        guard minutes > 0, pauseReasons.isEmpty else { return }
        let interval = TimeInterval(minutes * 60)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = interval * 0.1      // let the system coalesce wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard pauseReasons.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        for task in TaskStore.shared.tasks where task.remindersEnabled && task.uncheckedCount > 0 {
            let content = UNMutableNotificationContent()
            content.title = task.title
            let n = task.uncheckedCount
            var body = n == 1 ? "1 unchecked item" : "\(n) unchecked items"
            if let first = MarkdownCodec.firstUncheckedText(markdown: task.body) { body += " \u{2013} \(first)" }
            content.body = body
            content.sound = .default
            content.categoryIdentifier = "reminder"
            content.userInfo = ["taskID": task.id.uuidString]
            let req = UNNotificationRequest(identifier: "reminder-\(task.id.uuidString)", content: content, trigger: nil)
            center.add(req)
        }
    }

    /// Fires the reminder logic immediately (used by the "Send test reminder" button in Settings).
    func sendNow() { tick() }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let idString = content.userInfo["taskID"] as? String
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let s = idString, let id = UUID(uuidString: s) else { return }
                switch action {
                case "snooze15": ReminderService.shared.snooze(id: id, title: content.title, body: content.body, seconds: 15 * 60)
                case "snooze60": ReminderService.shared.snooze(id: id, title: content.title, body: content.body, seconds: 60 * 60)
                case "tomorrow":
                    let cal = Calendar.current
                    let tomorrow9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date()
                    ReminderService.shared.snooze(id: id, title: content.title, body: content.body, seconds: max(60, tomorrow9.timeIntervalSinceNow))
                case "done": ReminderService.shared.markFirstUncheckedDone(id)
                default: NotchController.shared.openTask(id)
                }
            }
        }
        completionHandler()
    }

    /// Show the same reminder again later.
    func snooze(id: UUID, title: String, body: String, seconds: TimeInterval) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.categoryIdentifier = "reminder"
        c.userInfo = ["taskID": id.uuidString]
        let req = UNNotificationRequest(identifier: "snooze-\(id.uuidString)", content: c,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    func markFirstUncheckedDone(_ id: UUID) {
        TaskStore.shared.update(id) { t in
            var lines = t.body.components(separatedBy: "\n")
            if let i = lines.firstIndex(where: { $0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("- [ ]") }) {
                lines[i] = lines[i].replacingOccurrences(of: "- [ ]", with: "- [x]")
                t.body = lines.joined(separator: "\n")
            }
        }
    }

    // MARK: Reminder chips

    /// Schedules a notification for every reminder chip (`[[rem:yyyy-MM-dd'T'HH:mm]]`) that is still in the future
    /// on an unchecked item. Called after notes are saved; replaces what it scheduled before.
    func syncChipReminders(_ tasks: [NoteTask]) {
        guard started else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix("chip-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for t in tasks {
                for (i, line) in t.body.components(separatedBy: "\n").enumerated() {
                    let r = line.drop(while: { $0 == " " || $0 == "\t" })
                    guard r.hasPrefix("- [ ]") else { continue }
                    let ns = line as NSString
                    for m in ChipToken.regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                        guard ns.substring(with: m.range(at: 1)) == "rem",
                              let when = ChipToken.isoFormat.date(from: ns.substring(with: m.range(at: 2))),
                              when > Date() else { continue }
                        let c = UNMutableNotificationContent()
                        c.title = t.title
                        c.body = MarkdownCodec.stripInline(String(r.dropFirst(5)))
                        c.sound = .default
                        c.categoryIdentifier = "reminder"
                        c.userInfo = ["taskID": t.id.uuidString]
                        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
                        center.add(UNNotificationRequest(identifier: "chip-\(t.id.uuidString)-\(i)", content: c,
                                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                    }
                }
            }
        }
    }
}
