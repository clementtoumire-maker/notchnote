import AppKit
import SwiftUI

/// Owns the ordinary windows (tasks, settings, getting started). The app is an accessory
/// (LSUIElement) app, so each of these activates the app explicitly.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    private var tasksWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func showTasks() {
        if tasksWindow == nil {
            let w = makeWindow(title: "NotchNote \u{2013} Tasks", size: NSSize(width: 860, height: 560),
                               style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               content: TaskWindowView())
            w.setFrameAutosaveName("NotchNoteTasksWindow")
            tasksWindow = w
        }
        present(tasksWindow)
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "NotchNote Settings", size: NSSize(width: 520, height: 640),
                                        style: [.titled, .closable], content: SettingsView())
        }
        present(settingsWindow)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(title: "Welcome to NotchNote", size: NSSize(width: 520, height: 420),
                                          style: [.titled, .closable],
                                          content: OnboardingView(onFinish: { [weak self] in
                                              AppSettings.shared.hasOnboarded = true
                                              self?.onboardingWindow?.close()
                                          }))
        }
        present(onboardingWindow)
    }

    private func makeWindow<V: View>(title: String, size: NSSize, style: NSWindow.StyleMask, content: V) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: content)
        w.center()
        w.delegate = self
        return w
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        TaskStore.shared.flush()
        if let w = notification.object as? NSWindow, w === onboardingWindow {
            AppSettings.shared.hasOnboarded = true
            onboardingWindow = nil
        }
    }
}
