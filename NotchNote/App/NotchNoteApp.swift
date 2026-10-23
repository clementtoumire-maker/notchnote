import SwiftUI
import AppKit
import CoreSpotlight

@main
struct NotchNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All UI is AppKit-managed windows; this empty scene only satisfies the App protocol.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Only one copy may run (a second launch, e.g. from the login item plus a manual open, just exits).
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != NSRunningApplication.current }) {
            NSApp.terminate(nil)
            return
        }
        enableLaunchAtLoginOnFirstRun()
        TaskStore.shared.loadAll()
        buildMainMenu()
        buildStatusItem()
        NotchController.shared.start()
        ReminderService.shared.start()
        if !AppSettings.shared.hasOnboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { WindowManager.shared.showOnboarding() }
            }
        }
    }

    /// NotchNote is meant to live in the background, so the first launch turns "Launch at login" on once.
    /// The user can turn it off in Settings; we never re-enable it afterwards.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "loginDefaultApplied"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? AppSettings.shared.setLaunchAtLogin(true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        TaskStore.shared.flushAndWait()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidResignActive(_ notification: Notification) {
        TaskStore.shared.flush()
    }

    // Spotlight result → open that task.
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let idString = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let id = UUID(uuidString: idString) else { return false }
        NotchController.shared.openTask(id)
        return true
    }

    // MARK: Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NotchNote")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Panel", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Task", action: #selector(newTask), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Tasks Window\u{2026}", action: #selector(showTasks), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Getting Started\u{2026}", action: #selector(showOnboarding), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showPanel() { NotchController.shared.toggleOnActiveScreen() }
    @objc private func newTask() { TaskStore.shared.createTask(); NotchController.shared.showPinnedOnActiveScreen() }
    @objc private func showTasks() { WindowManager.shared.showTasks() }
    @objc private func showSettings() { WindowManager.shared.showSettings() }
    @objc private func showOnboarding() { WindowManager.shared.showOnboarding() }

    @objc func toggleFavorite(_ sender: Any?) {
        if let id = TaskStore.shared.selectedID { TaskStore.shared.toggleFavorite(id) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }

    // MARK: Main menu
    // An accessory app has no visible menu bar until it is active, but the menu still has to exist so that
    // Edit commands and key equivalents work in the task window and settings.

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit NotchNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let taskItem = NSMenuItem(); main.addItem(taskItem)
        let task = NSMenu(title: "Task"); taskItem.submenu = task
        let n = task.addItem(withTitle: "New Task", action: #selector(newTask), keyEquivalent: "n"); n.target = self
        let fav = task.addItem(withTitle: "Toggle Favorite", action: #selector(toggleFavorite(_:)), keyEquivalent: "s")
        fav.keyEquivalentModifierMask = [.command, .shift]
        fav.target = self
        let w = task.addItem(withTitle: "Tasks Window", action: #selector(showTasks), keyEquivalent: "t")
        w.keyEquivalentModifierMask = [.command, .shift]
        w.target = self

        NSApp.mainMenu = main
    }
}
