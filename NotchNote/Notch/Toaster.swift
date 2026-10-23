import Foundation

/// A short message at the bottom of the panel, with an optional Undo. Replaces confirmation dialogs.
@MainActor
final class Toaster: ObservableObject {
    static let shared = Toaster()
    @Published private(set) var message: String?
    @Published private(set) var hasUndo = false
    private var undoAction: (() -> Void)?
    private var work: DispatchWorkItem?

    func show(_ text: String, undo: (() -> Void)? = nil) {
        work?.cancel()
        message = text
        undoAction = undo
        hasUndo = undo != nil
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.dismiss() } }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
    }

    func undo() {
        let a = undoAction
        dismiss()
        a?()
    }

    func dismiss() {
        work?.cancel()
        message = nil
        undoAction = nil
        hasUndo = false
    }
}
