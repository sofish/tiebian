import AppKit
import EdgePeekCore
import SwiftUI

@MainActor
final class NoteEditorController {
    private var panel: NSPanel?
    private var noteID: UUID?
    private var isNew = false
    private var store: NoteStore?
    private var previousApp: NSRunningApplication?
    private var onDismiss: (() -> Void)?
    private var screen: NSScreen?
    private let undoToast = UndoToastController()

    var isOpen: Bool {
        panel?.isVisible == true
    }

    var editingNoteID: UUID? {
        isOpen ? noteID : nil
    }

    func open(
        note: StickyNote,
        isNew: Bool,
        store: NoteStore,
        on screen: NSScreen,
        onDismiss: @escaping () -> Void
    ) {
        let visible = screen.visibleFrame
        let size = Layout.editorSize
        let origin = CGPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2 + 18).rounded()
        )
        let frame = CGRect(origin: origin, size: size)

        if isOpen {
            close(restoreFocus: false, callDismiss: false)
        }
        undoToast.hide(immediately: true)

        if previousApp == nil {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp = front
            }
        }

        let panel = PanelFactory.make(frame: frame, keyable: true)
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false

        let view = EditorView(
            store: store,
            note: note,
            isNew: isNew,
            onClose: { [weak self] in
                self?.close()
            },
            onDelete: { [weak self] in
                self?.deleteCurrentNote()
            },
            onDragEnded: { [weak self] in
                self?.clampPanelToScreen()
            }
        )
        let host = FirstMouseHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.alphaValue = 0

        self.panel = panel
        self.noteID = note.id
        self.isNew = isNew
        self.store = store
        self.onDismiss = onDismiss
        self.screen = screen

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self, weak panel] in
            guard let self, let panel, self.isOpen else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func focus() {
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
    }

    func close(restoreFocus: Bool = true, callDismiss: Bool = true) {
        guard let panel, let noteID else { return }

        store?.saveNow()
        if isNew {
            store?.discardIfEmptyIgnoringTags(id: noteID)
        }

        let dismiss = onDismiss
        let appToRestore = previousApp
        tearDownPanel(panel)

        if callDismiss {
            dismiss?()
        }

        if restoreFocus,
           let appToRestore,
           appToRestore.bundleIdentifier != Bundle.main.bundleIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                appToRestore.activate(options: [])
            }
        }
    }

    private func deleteCurrentNote() {
        guard let panel, let noteID, let store else { return }
        guard let note = store.note(with: noteID) else {
            close(restoreFocus: false, callDismiss: true)
            return
        }

        let screen = panel.screen ?? screen ?? NSScreen.main
        let dismiss = onDismiss
        tearDownPanel(panel)
        store.delete(id: note.id)
        store.saveNow()
        dismiss?()

        if let screen {
            undoToast.show(note: note, on: screen) { [weak store] restored in
                store?.restore(restored)
                store?.saveNow()
            }
        }
    }

    private func tearDownPanel(_ panel: NSPanel) {
        self.panel = nil
        self.noteID = nil
        self.store = nil
        self.onDismiss = nil
        self.previousApp = nil
        self.screen = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    private func clampPanelToScreen() {
        guard let panel else { return }
        guard let screen = panel.screen ?? screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        let margin: CGFloat = 10
        frame.origin.x = min(
            max(frame.origin.x, visible.minX + margin),
            visible.maxX - frame.width - margin
        )
        frame.origin.y = min(
            max(frame.origin.y, visible.minY + margin),
            visible.maxY - frame.height - margin
        )
        if frame.origin != panel.frame.origin {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
}
