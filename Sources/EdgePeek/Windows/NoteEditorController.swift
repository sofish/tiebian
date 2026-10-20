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
    private var dragMonitor: Any?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var dragSamples: [(point: NSPoint, time: TimeInterval)] = []
    private var dragVelocity: CGSize = .zero
    private var dragPeakVelocity: CGSize = .zero
    private var dragCursorPushed = false
    private var dragWatchTimer: Timer?

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
                self?.deleteCurrentNote(flingVelocity: nil)
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

        installDragMonitor()
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

    private func deleteCurrentNote(flingVelocity: CGSize?) {
        guard let panel, let noteID, let store else { return }
        guard let note = store.note(with: noteID) else {
            close(restoreFocus: false, callDismiss: true)
            return
        }

        store.saveNow()
        let shouldShowUndo = !note.isEmptyIgnoringTags

        if let flingVelocity {
            let direction = Self.normalizedDirection(flingVelocity)
            var target = panel.frame.origin
            target.x += direction.x * 980
            target.y += direction.y * 980

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrameOrigin(target)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finishDeletion(
                        panel: panel,
                        note: note,
                        store: store,
                        screen: panel.screen ?? self.screen ?? NSScreen.main,
                        showUndo: shouldShowUndo
                    )
                }
            }
        } else {
            finishDeletion(
                panel: panel,
                note: note,
                store: store,
                screen: panel.screen ?? screen ?? NSScreen.main,
                showUndo: shouldShowUndo,
                animated: true
            )
        }
    }

    private func finishDeletion(
        panel: NSPanel,
        note: StickyNote,
        store: NoteStore,
        screen: NSScreen?,
        showUndo: Bool,
        animated: Bool = false
    ) {
        let dismiss = onDismiss
        panel.alphaValue = 1
        panel.orderOut(nil)
        tearDownPanel(panel)
        store.delete(id: note.id)
        dismiss?()

        if showUndo, let screen {
            undoToast.show(note: note, on: screen) { [weak store] restored in
                store?.restore(restored)
            }
        }
    }

    private func tearDownPanel(_ panel: NSPanel) {
        removeDragMonitor()
        self.panel = nil
        self.noteID = nil
        self.store = nil
        self.onDismiss = nil
        self.previousApp = nil
        self.screen = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    // MARK: - Note dragging and flinging

    private func installDragMonitor() {
        removeDragMonitor()
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self, let panel = self.panel, self.isOpen else {
                return event
            }
            let location = NSEvent.mouseLocation

            switch event.type {
            case .leftMouseDown:
                guard self.isInsideDragHandle(location, panel: panel) else {
                    return event
                }
                self.dragStartMouse = location
                self.dragStartOrigin = panel.frame.origin
                self.dragSamples = [(location, event.timestamp)]
                self.dragVelocity = .zero
                self.dragPeakVelocity = .zero
                if !self.dragCursorPushed {
                    NSCursor.closedHand.push()
                    self.dragCursorPushed = true
                }
                self.startDragWatchTimer()
                return nil

            case .leftMouseDragged:
                guard let startMouse = self.dragStartMouse,
                      let startOrigin = self.dragStartOrigin else {
                    return event
                }
                panel.setFrameOrigin(
                    NSPoint(
                        x: startOrigin.x + location.x - startMouse.x,
                        y: startOrigin.y + location.y - startMouse.y
                    )
                )
                if let previous = self.dragSamples.last {
                    let dt = max(0.008, event.timestamp - previous.time)
                    let velocity = CGSize(
                        width: (location.x - previous.point.x) / dt,
                        height: (location.y - previous.point.y) / dt
                    )
                    self.dragVelocity = velocity
                    if hypot(velocity.width, velocity.height)
                        > hypot(self.dragPeakVelocity.width, self.dragPeakVelocity.height) {
                        self.dragPeakVelocity = velocity
                    }
                }
                self.dragSamples.append((location, event.timestamp))
                if self.dragSamples.count > 10 {
                    self.dragSamples.removeFirst(self.dragSamples.count - 10)
                }
                return nil

            case .leftMouseUp:
                self.finishDrag(panel: panel)
                return nil

            default:
                return event
            }
        }
    }

    private func startDragWatchTimer() {
        dragWatchTimer?.invalidate()
        let timer = Timer(
            timeInterval: 0.02,
            target: self,
            selector: #selector(dragWatchTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        dragWatchTimer = timer
    }

    @objc private func dragWatchTick() {
        guard dragStartMouse != nil else {
            dragWatchTimer?.invalidate()
            dragWatchTimer = nil
            return
        }
        if NSEvent.pressedMouseButtons & 0x1 == 0 {
            if let panel {
                finishDrag(panel: panel)
            } else {
                endDrag()
            }
        }
    }

    private func finishDrag(panel: NSPanel) {
        guard let startMouse = dragStartMouse else { return }
        let location = NSEvent.mouseLocation
        let distance = hypot(location.x - startMouse.x, location.y - startMouse.y)
        let gestureSpeed = max(
            hypot(dragVelocity.width, dragVelocity.height),
            hypot(dragPeakVelocity.width, dragPeakVelocity.height)
        )
        let visible = panel.screen?.visibleFrame ?? screen?.visibleFrame
        let mostlyOut = visible.map { visibleFrame in
            let intersection = panel.frame.intersection(visibleFrame)
            return intersection.isNull
                || intersection.width < 40
                || intersection.height < 40
        } ?? false

        let flingVelocity = hypot(dragPeakVelocity.width, dragPeakVelocity.height)
            >= hypot(dragVelocity.width, dragVelocity.height)
            ? dragPeakVelocity
            : dragVelocity
        endDrag()
        if (gestureSpeed > 700 && distance > 70) || mostlyOut {
            deleteCurrentNote(flingVelocity: flingVelocity)
        } else {
            clampPanelToScreen()
        }
    }

    private func removeDragMonitor() {
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
        if dragCursorPushed {
            NSCursor.pop()
            dragCursorPushed = false
        }
        endDrag()
    }

    private func endDrag() {
        dragWatchTimer?.invalidate()
        dragWatchTimer = nil
        dragStartMouse = nil
        dragStartOrigin = nil
        dragSamples = []
        dragVelocity = .zero
        dragPeakVelocity = .zero
    }

    private func isInsideDragHandle(_ location: NSPoint, panel: NSPanel) -> Bool {
        let frame = panel.frame
        let inStrip = location.y >= frame.maxY - 112
            && location.y <= frame.maxY - 56
        let centered = abs(location.x - frame.midX) <= 92
        return inStrip && centered
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

    private static func normalizedDirection(_ velocity: CGSize) -> CGPoint {
        let length = hypot(velocity.width, velocity.height)
        guard length > 0.01 else { return CGPoint(x: 0, y: 1) }
        return CGPoint(x: velocity.width / length, y: velocity.height / length)
    }
}
