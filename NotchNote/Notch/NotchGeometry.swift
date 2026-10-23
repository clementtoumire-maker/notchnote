import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func underMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }
}

/// Where the panel sits on one display. Everything is derived from `screen.frame` (not `visibleFrame`)
/// and the notch metrics, so the position is identical whether the menu bar is shown or hidden,
/// and does not move when displays are added/removed (clamshell) as long as the display itself is unchanged.
struct NotchGeometry: Equatable {
    let displayID: CGDirectDisplayID
    let screenFrame: NSRect
    let hasNotch: Bool
    let hardwareNotch: CGSize
    /// A notchless display drawn with a black notch-shaped tab (setting Virtual notch).
    let isVirtual: Bool

    /// Corner radius of the hardware notch's lower corners. The folded shape uses it so it is indistinguishable from the real notch.
    static let hardwareCornerRadius: CGFloat = 9
    /// Radius of the concave ears where the folded notch meets the top edge (notch displays only).
    static let earRadius: CGFloat = 9
    /// Gap between the top screen edge and the floating pill on notchless displays.
    static let pillTopGap: CGFloat = 5
    static let hotZoneMarginX: CGFloat = 10
    static let hotZoneMarginBottom: CGFloat = 6

    @MainActor
    init(screen: NSScreen) {
        displayID = screen.displayID
        screenFrame = screen.frame
        let topInset = screen.safeAreaInsets.top
        let virtual = topInset == 0 && AppSettings.shared.externalStyle == .virtualNotch
        isVirtual = virtual
        hasNotch = topInset > 0 || virtual
        if topInset > 0 {
            var width: CGFloat = 200
            if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
                width = screen.frame.width - l.width - r.width
            }
            hardwareNotch = CGSize(width: width, height: topInset)
        } else if virtual {
            hardwareNotch = CGSize(width: 188, height: 32)
        } else {
            hardwareNotch = .zero
        }
    }

    var topGap: CGFloat { hasNotch ? 0 : Self.pillTopGap }

    @MainActor func collapsedSize(_ s: AppSettings) -> CGSize {
        if hasNotch {
            return CGSize(width: hardwareNotch.width + s.notchExtraWidth, height: hardwareNotch.height + s.notchExtraHeight)
        }
        return CGSize(width: 150 + s.notchExtraWidth, height: 30 + s.notchExtraHeight)
    }

    @MainActor func expandedSize(_ s: AppSettings) -> CGSize {
        let w = min(max(s.panelWidth, AppSettings.panelWidthRange.lowerBound), min(AppSettings.panelWidthRange.upperBound, screenFrame.width - 40))
        let h = min(max(s.panelHeight, AppSettings.panelHeightRange.lowerBound), min(AppSettings.panelHeightRange.upperBound, screenFrame.height - 80))
        return CGSize(width: w, height: h)
    }

    @MainActor func expandedFrame(_ s: AppSettings) -> NSRect {
        let size = expandedSize(s)
        let ear = hasNotch ? Self.earRadius : 0
        return NSRect(x: screenFrame.midX - size.width / 2 - ear,
                      y: screenFrame.maxY - topGap - size.height,
                      width: size.width + 2 * ear, height: size.height)
    }

    /// Slightly larger than the visible pill so the target is easy to hit.
    @MainActor func hotFrame(_ s: AppSettings) -> NSRect {
        let c = collapsedSize(s)
        let w = c.width + Self.hotZoneMarginX * 2
        let h = c.height + Self.hotZoneMarginBottom
        return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - topGap - h, width: w, height: h)
    }
}
