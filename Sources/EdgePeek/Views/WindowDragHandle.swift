import AppKit
import SwiftUI

struct WindowDragHandle: NSViewRepresentable {
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> WindowDragHandleView {
        let view = WindowDragHandleView()
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: WindowDragHandleView, context: Context) {
        view.onDragEnded = onDragEnded
    }
}

final class WindowDragHandleView: NSView {
    var onDragEnded: () -> Void = {}
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        endDrag()
        dragStart = (window.convertPoint(toScreen: event.locationInWindow), window.frame.origin)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let window else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(
            x: dragStart.origin.x + mouse.x - dragStart.mouse.x,
            y: dragStart.origin.y + mouse.y - dragStart.mouse.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        endDrag()
        onDragEnded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endDrag() }
    }

    private func endDrag() {
        guard dragStart != nil else { return }
        dragStart = nil
        NSCursor.pop()
    }
}
