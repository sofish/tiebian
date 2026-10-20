import AppKit
import EdgePeekCore
import SwiftUI

struct SeamView: View {
    @ObservedObject var state: SeamState

    var onTap: () -> Void
    var onDragBegan: () -> Void
    var onDragMoved: () -> Void
    var onDragEnded: () -> Void
    var onHoverChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.clear
            SeamLight(configuration: .init(edge: state.edge, width: state.width,
                                            hasDue: state.hasDueNote, overdueCount: state.overdueCount,
                                            animation: state.animation), hovered: state.isHovered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            SeamMouseLayer(
                onTap: onTap,
                onDragBegan: onDragBegan,
                onDragMoved: onDragMoved,
                onDragEnded: onDragEnded,
                onHoverChanged: onHoverChanged
            )
        )
    }
}

private struct SeamMouseLayer: NSViewRepresentable {
    var onTap: () -> Void
    var onDragBegan: () -> Void
    var onDragMoved: () -> Void
    var onDragEnded: () -> Void
    var onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> SeamMouseView {
        let view = SeamMouseView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: SeamMouseView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: SeamMouseView) {
        view.onTap = onTap
        view.onDragBegan = onDragBegan
        view.onDragMoved = onDragMoved
        view.onDragEnded = onDragEnded
        view.onHoverChanged = onHoverChanged
    }
}

private final class SeamMouseView: NSView {
    var onTap: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var initialMouse: NSPoint?
    private var initialOrigin: NSPoint?
    private var didDrag = false
    private var pushedCursor = false
    private var trackingAreaRef: NSTrackingArea?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouse = NSEvent.mouseLocation
        initialOrigin = window?.frame.origin
        didDrag = false
        if !pushedCursor {
            NSCursor.closedHand.push()
            pushedCursor = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialMouse,
              let initialOrigin,
              let window else { return }
        let current = NSEvent.mouseLocation
        let deltaX = current.x - initialMouse.x
        let deltaY = current.y - initialMouse.y
        if !didDrag, hypot(deltaX, deltaY) > 3 {
            didDrag = true
            onDragBegan?()
        }
        guard didDrag else { return }
        window.setFrameOrigin(
            NSPoint(x: initialOrigin.x + deltaX, y: initialOrigin.y + deltaY)
        )
        onDragMoved?()
    }

    override func mouseUp(with event: NSEvent) {
        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }
        if didDrag {
            onDragEnded?()
        } else {
            onTap?()
        }
        initialMouse = nil
        initialOrigin = nil
        didDrag = false
    }
}
