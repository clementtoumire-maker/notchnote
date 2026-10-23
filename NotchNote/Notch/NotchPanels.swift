import AppKit
import SwiftUI

private let notchWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

/// The expanded panel. Borderless, non-activating (hovering does not steal focus from the frontmost app),
/// but it can become key so typing works once you click into it.
final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onToggleFavorite: (() -> Void)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = notchWindowLevel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Keep the frame exactly where we put it, even over the menu bar / notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "s" {
                onToggleFavorite?()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Small always-present window over the notch / pill. It owns hover, click and text-drag detection.
final class HotZonePanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = notchWindowLevel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class HotZoneView: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var onDragEnter: (() -> Void)?
    var onDropText: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter?()
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let s = sender.draggingPasteboard.string(forType: .string) else { return false }
        onDropText?(s)
        return true
    }
}

/// Hosting view that lets mouse events fall through to its superview (the HotZoneView).
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Container for the expanded panel that reports the pointer leaving / entering.
final class PanelContainerView: NSView {
    var onExit: (() -> Void)?
    var onEnter: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
