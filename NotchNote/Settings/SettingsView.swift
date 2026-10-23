import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = TaskStore.shared
    @State private var loginError: String?

    private let intervals: [(String, Int)] = [("Off", 0), ("Every 5 minutes", 5), ("Every 15 minutes", 15), ("Every 30 minutes", 30),
                                              ("Every hour", 60), ("Every 2 hours", 120), ("Every 4 hours", 240)]

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLoginEnabled },
                    set: { on in
                        do { try settings.setLaunchAtLogin(on); loginError = nil }
                        catch { loginError = error.localizedDescription }
                    }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Text("NotchNote runs in the background with no Dock icon and starts at login. Quit it from the menu bar icon. Launch at login works best once it is in /Applications.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show Getting Started\u{2026}") { WindowManager.shared.showOnboarding() }
            }

            Section("Reminders") {
                Picker("Remind me about unchecked items", selection: $settings.reminderIntervalMinutes) {
                    ForEach(intervals, id: \.1) { Text($0.0).tag($0.1) }
                }
                Text("Reminders pause while your Mac is locked, asleep or in screen saver, and restart when it is ready.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Send a test reminder now") { ReminderService.shared.sendNow() }
            }

            Section("Sync folder") {
                HStack {
                    Text(settings.syncFolderPath ?? "Not set (tasks stay on this Mac)")
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(settings.syncFolderPath == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose\u{2026}") { chooseFolder() }
                    if settings.syncFolderPath != nil {
                        Button("Clear") { settings.syncFolderPath = nil }
                    }
                }
                Text("Pick a folder inside iCloud Drive (or Dropbox, Syncthing\u{2026}) to sync tasks across your Macs. Move individual tasks in or out from the task window\u{2019}s context menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                ColorPicker("Text color", selection: Binding(
                    get: { settings.textColor },
                    set: { settings.textColorHex = NSColor($0).hexString }))
                HStack {
                    Text("Notch width")
                    Slider(value: $settings.notchExtraWidth, in: -40...160)
                    Text("\(Int(settings.notchExtraWidth)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                HStack {
                    Text("Notch height")
                    Slider(value: $settings.notchExtraHeight, in: -4...30)
                    Text("\(Int(settings.notchExtraHeight)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                HStack {
                    Text("Panel width")
                    Slider(value: $settings.panelWidth, in: AppSettings.panelWidthRange)
                    Text("\(Int(settings.panelWidth)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                HStack {
                    Text("Panel height")
                    Slider(value: $settings.panelHeight, in: AppSettings.panelHeightRange)
                    Text("\(Int(settings.panelHeight)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                HStack {
                    Spacer()
                    Button("Reset size") {
                        settings.resetPanelSize()
                        settings.notchExtraWidth = 0
                        settings.notchExtraHeight = 0
                    }
                }
                Text("You can also resize the panel by dragging the handle in its bottom-right corner.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Share anonymous usage data", isOn: $settings.usageDataEnabled)
                Text("Off by default. NotchNote contains no networking code, so no data is sent whether this is on or off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder NotchNote should sync tasks into (for example a folder in iCloud Drive)."
        if panel.runModal() == .OK, let url = panel.url { settings.syncFolderPath = url.path }
    }
}
