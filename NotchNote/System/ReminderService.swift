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
        let idString = response.notification.request.content.userInfo["taskID"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let s = idString, let id = UUID(uuidString: s) { NotchController.shared.openTask(id) }
            }
        }
        completionHandler()
    }
}
