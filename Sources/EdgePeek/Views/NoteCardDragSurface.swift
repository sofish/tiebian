import AppKit
import EdgePeekCore
import SwiftUI

struct NoteCardDragSurface: NSViewRepresentable {
    let noteID: UUID
    let image: (Bool) -> NSImage?
    let onOpen: () -> Void
    let onDragBegan: () -> Void
    let onDragMoved: (CGPoint) -> CardDropTarget
    let onDragEnded: (CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> NoteCardDragView {
        let view = NoteCardDragView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NoteCardDragView, context: Context) {
        view.noteID = noteID
        view.image = image
        view.onOpen = onOpen
        view.onDragBegan = onDragBegan
        view.onDragMoved = onDragMoved
        view.onDragEnded = onDragEnded
    }
}

final class NoteCardDragView: NSView, NSDraggingSource {
    var noteID = UUID()
    var image: (Bool) -> NSImage? = { _ in nil }
    var onOpen: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDragMoved: (CGPoint) -> CardDropTarget = { _ in .none }
    var onDragEnded: (CGPoint, Bool) -> Void = { _, _ in }
    private var mouseDownPoint: CGPoint?
    private var dragging = false
    private var dragItem: NSDraggingItem?
    private var isArmed = false
    /// Where the pointer sits inside the card, kept in screen space while the
    /// rest of the board stays put, so the drop hint can follow the ghost.
    private var grabOffset = CGPoint.zero
    private var renderedImages: [Bool: NSImage] = [:]
    private var hintPanel: NSPanel?
    private var hintHost: NSHostingView<CardDropHint>?
    private var hintTarget: CardDropTarget?
    private var hintSize = CGSize.zero
    private var cachedScreen: NSScreen?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 6,
              let image = renderedImage(armed: false) else { return }
        dragging = true
        cachedScreen = nil
        // Build the hint window now, off the hover path, so reaching a drop
        // target never has to lay out and order a window mid-drag.
        hintPanel = makeHintPanel()
        let item = NSPasteboardItem()
        item.setString(noteID.uuidString, forType: NSPasteboard.PasteboardType("com.sofish.edgepeek.card"))
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: image)
        self.dragItem = dragItem
        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !dragging, mouseDownPoint != nil,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onOpen()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // A private pasteboard type prevents another app from consuming a note drop.
        .delete
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        grabOffset = pointerOffset(at: screenPoint)
        onDragBegan()
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let target = onDragMoved(screenPoint)
        let armed = target == .delete
        if armed != isArmed {
            isArmed = armed
            if let image = renderedImage(armed: armed) {
                dragItem?.setDraggingFrame(bounds, contents: image)
            }
        }
        if target == .none {
            hideHint()
        } else {
            updateHint(for: target, at: screenPoint)
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownPoint = nil
        dragging = false
        dragItem = nil
        isArmed = false
        grabOffset = .zero
        renderedImages.removeAll()
        teardownHint()
        // AppKit reports a cancelled drag as .none too. Escape must never delete.
        let cancelled = NSEvent.pressedMouseButtons & 1 != 0
            || (NSApp.currentEvent?.type == .keyDown && NSApp.currentEvent?.keyCode == 53)
        onDragEnded(screenPoint, cancelled)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { teardownHint() }
    }

    /// Rendering the card is not free, and the drag can cross the delete
    /// boundary repeatedly, so each variant is rasterised at most once per
    /// session.
    private func renderedImage(armed: Bool) -> NSImage? {
        if let image = renderedImages[armed] {
            return image
        }
        guard let image = image(armed) else { return nil }
        renderedImages[armed] = image
        return image
    }

    // MARK: - Drop hint

    private func pointerOffset(at screenPoint: CGPoint) -> CGPoint {
        guard let window else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        let local = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        return CGPoint(x: local.x - bounds.minX, y: local.y - bounds.minY)
    }

    private func cardFrame(at screenPoint: CGPoint) -> CGRect {
        CGRect(
            x: screenPoint.x - grabOffset.x,
            y: screenPoint.y - grabOffset.y,
            width: bounds.width,
            height: bounds.height
        )
    }

    private func updateHint(for target: CardDropTarget, at screenPoint: CGPoint) {
        guard let panel = hintPanel, let host = hintHost, let screen = screen(at: screenPoint) else {
            return
        }
        if target != hintTarget {
            hintTarget = target
            host.rootView = CardDropHint(target: target)
            hintSize = host.fittingSize
            panel.setContentSize(hintSize)
        }
        let frame = CardDropHintLayout.placement(
            cardFrame: cardFrame(at: screenPoint),
            hintSize: hintSize,
            screenFrame: screen.visibleFrame
        )
        if panel.frame.origin != frame.origin {
            panel.setFrameOrigin(frame.origin)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func hideHint() {
        guard let panel = hintPanel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func teardownHint() {
        hintPanel?.orderOut(nil)
        hintPanel = nil
        hintHost = nil
        hintTarget = nil
        hintSize = .zero
    }

    private func screen(at point: CGPoint) -> NSScreen? {
        if let cachedScreen, cachedScreen.frame.contains(point) {
            return cachedScreen
        }
        let screens = NSScreen.screens
        guard let index = EdgeGeometry.screenIndex(for: point, among: screens.map(\.frame)) else {
            return nil
        }
        let screen = screens[index]
        cachedScreen = screen
        return screen
    }

    private func makeHintPanel() -> NSPanel {
        let host = NSHostingView(rootView: CardDropHint(target: .delete))
        let size = host.fittingSize
        let panel = PanelFactory.make(frame: NSRect(origin: .zero, size: size), keyable: false)
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.contentView = host
        hintHost = host
        hintSize = size
        return panel
    }
}
