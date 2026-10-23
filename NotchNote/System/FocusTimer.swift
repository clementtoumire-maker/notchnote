import Foundation
import UserNotifications

/// A single focus session (Pomodoro-style) with any length. Lives in the header while it runs.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    @Published private(set) var title = ""
    @Published private(set) var left = 0          // seconds
    @Published private(set) var total = 0
    @Published private(set) var paused = false
    private var timer: Timer?

    var isRunning: Bool { timer != nil }

    var clock: String {
        let m = max(left, 0) / 60, s = max(left, 0) % 60
        return String(format: "%02d:%02d", m, s)
    }

    func start(_ title: String, minutes: Int) {
        stop()
        self.title = title
        total = max(1, minutes) * 60
        left = total
        paused = false
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func togglePause() { if isRunning { paused.toggle() } }

    func add(minutes: Int) {
        guard isRunning else { return }
        left = max(60, left + minutes * 60)
        total = max(total, left)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        paused = false
        left = 0
        objectWillChange.send()
    }

    private func tick() {
        guard !paused else { return }
        left -= 1
        if left <= 0 {
            let finished = title
            stop()
            let content = UNMutableNotificationContent()
            content.title = "Focus session done"
            content.body = finished
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "focus-done", content: content, trigger: nil))
        }
    }
}
