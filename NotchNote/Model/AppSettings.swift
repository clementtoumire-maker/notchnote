import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var syncFolderPath: String? { didSet { d.set(syncFolderPath, forKey: "syncFolderPath") } }
    /// 0 = reminders off
    @Published var reminderIntervalMinutes: Int { didSet { d.set(reminderIntervalMinutes, forKey: "reminderIntervalMinutes") } }
    @Published var textColorHex: String { didSet { d.set(textColorHex, forKey: "textColorHex") } }
    @Published var notchExtraWidth: Double { didSet { d.set(notchExtraWidth, forKey: "notchExtraWidth") } }
    @Published var notchExtraHeight: Double { didSet { d.set(notchExtraHeight, forKey: "notchExtraHeight") } }
    @Published var panelWidth: Double { didSet { d.set(panelWidth, forKey: "panelWidth") } }
    @Published var panelHeight: Double { didSet { d.set(panelHeight, forKey: "panelHeight") } }
    /// Optional anonymous usage data. Default OFF. Nothing is ever sent: there is no networking code
    /// in this app. The flag exists so the setting and its wording match the original app.
    @Published var usageDataEnabled: Bool { didSet { d.set(usageDataEnabled, forKey: "usageDataEnabled") } }
    @Published var hasOnboarded: Bool { didSet { d.set(hasOnboarded, forKey: "hasOnboarded") } }
    @Published var lastSelectedTaskID: String? { didSet { d.set(lastSelectedTaskID, forKey: "lastSelectedTaskID") } }

    nonisolated static let panelWidthRange: ClosedRange<Double> = 320...900
    nonisolated static let panelHeightRange: ClosedRange<Double> = 200...800

    private init() {
        let d = UserDefaults.standard
        syncFolderPath = d.string(forKey: "syncFolderPath")
        reminderIntervalMinutes = d.object(forKey: "reminderIntervalMinutes") as? Int ?? 30
        textColorHex = d.string(forKey: "textColorHex") ?? "#FFFFFF"
        notchExtraWidth = d.object(forKey: "notchExtraWidth") as? Double ?? 0
        notchExtraHeight = d.object(forKey: "notchExtraHeight") as? Double ?? 0
        panelWidth = d.object(forKey: "panelWidth") as? Double ?? 440
        panelHeight = d.object(forKey: "panelHeight") as? Double ?? 320
        usageDataEnabled = d.object(forKey: "usageDataEnabled") as? Bool ?? false
        hasOnboarded = d.object(forKey: "hasOnboarded") as? Bool ?? false
        lastSelectedTaskID = d.string(forKey: "lastSelectedTaskID")
    }

    var textColor: Color { Color(nsColor: NSColor(hex: textColorHex)) }
    var nsTextColor: NSColor { NSColor(hex: textColorHex) }

    func resetPanelSize() {
        panelWidth = 440
        panelHeight = 320
    }

    // MARK: Launch at login

    var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        objectWillChange.send()
    }
}

extension NSColor {
    convenience init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255.0,
                  green: CGFloat((v >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(v & 0xFF) / 255.0,
                  alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
