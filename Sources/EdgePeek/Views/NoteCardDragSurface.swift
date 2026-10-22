import AppKit
import SwiftUI

struct NoteCardDragSurface: NSViewRepresentable {
    let noteID: UUID
    let image: () -> NSImage?
    let onOpen: () -> Void
    let onDragBegan: () -> Void
    let onDragMoved: (CGPoint) -> Void
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
    var image: () -> NSImage? = { nil }
    var onOpen: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDragMoved: (CGPoint) -> Void = { _ in }
    var onDragEnded: (CGPoint, Bool) -> Void = { _, _ in }
    private var mouseDownPoint: CGPoint?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 6,
              let image = image() else { return }
        dragging = true
        let item = NSPasteboardItem()
        item.setString(noteID.uuidString, forType: NSPasteboard.PasteboardType("com.sofish.edgepeek.card"))
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: image)
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
        onDragBegan()
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        onDragMoved(screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownPoint = nil
        dragging = false
        // AppKit reports a cancelled drag as .none too. Escape must never delete.
        let cancelled = NSEvent.pressedMouseButtons & 1 != 0
            || (NSApp.currentEvent?.type == .keyDown && NSApp.currentEvent?.keyCode == 53)
        onDragEnded(screenPoint, cancelled)
    }
}
