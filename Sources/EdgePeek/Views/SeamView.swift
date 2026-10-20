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

    private var vertical: Bool { state.edge.isVertical }

    var body: some View {
        ZStack {
            Color.clear
            SeamLight(
                edge: state.edge,
                hasDue: state.hasDueNote,
                overdueCount: state.overdueCount,
                hovered: state.isHovered
            )
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

private struct SeamLight: View {
    let edge: EdgeSide
    let hasDue: Bool
    let overdueCount: Int
    let hovered: Bool

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                SeamLightBody(
                    edge: edge,
                    hasDue: hasDue,
                    overdueCount: overdueCount,
                    hovered: hovered,
                    size: geometry.size,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SeamLightBody: View {
    let edge: EdgeSide
    let hasDue: Bool
    let overdueCount: Int
    let hovered: Bool
    let size: CGSize
    let time: TimeInterval

    private var vertical: Bool { edge.isVertical }

    var body: some View {
        let length = vertical ? size.height : size.width
        let lineX: CGFloat = edge == .left ? 2.1 : (edge == .right ? size.width - 2.1 : size.width / 2)
        let lineY: CGFloat = edge == .top ? 2.1 : (edge == .bottom ? size.height - 2.1 : size.height / 2)
        let cycle: Double = hasDue ? 2.8 : 5.2
        let phase = time.truncatingRemainder(dividingBy: cycle) / cycle
        let cometLength: CGFloat = 64
        let travel = max(0, length - cometLength - 18)
        let offset = 9 + CGFloat(phase) * travel
        let fade = min(min(phase * 6, 1), min((1 - phase) * 6, 1))
        let baseOpacity = hasDue ? 0.85 : (hovered ? 0.68 : 0.48)
        let dotX: CGFloat = vertical ? lineX : offset + cometLength / 2
        let dotY: CGFloat = vertical ? offset + cometLength / 2 : lineY

        // The overdue count is not a permanent badge. It travels with the
        // glint for two passes, fades away, and returns a few seconds later.
        let displayCycles = 4
        let visibleCycles = 2
        let countCycle = cycle * Double(displayCycles)
        let countTime = time.truncatingRemainder(dividingBy: countCycle)
        let countCycleIndex = Int(floor(time / cycle))
        let countVisible = overdueCount > 0
            && countCycleIndex % displayCycles < visibleCycles
        let countShowDuration = cycle * Double(visibleCycles)
        let countOpacity: Double = countVisible
            ? min(1, max(0, countTime / 0.7), max(0, (countShowDuration - countTime) / 0.9))
            : 0
        let countOffset: CGFloat = 9
        let countPosition = CGPoint(
            x: vertical
                ? dotX + (edge == .left ? countOffset : -countOffset)
                : dotX,
            y: vertical
                ? dotY
                : dotY + (edge == .top ? countOffset : -countOffset)
        )

        ZStack {
            // The slit itself: a quiet, thin crease.
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.accent.opacity(0),
                            Theme.accent.opacity(baseOpacity * 0.55),
                            Color.white.opacity(baseOpacity * 0.42),
                            Theme.accent.opacity(baseOpacity * 0.55),
                            Theme.accent.opacity(0)
                        ],
                        startPoint: vertical ? .top : .leading,
                        endPoint: vertical ? .bottom : .trailing
                    )
                )
                .frame(
                    width: vertical ? 2.7 : length - 18,
                    height: vertical ? length - 18 : 2.7
                )
                .position(x: lineX, y: lineY)
                .blur(radius: 0.25)
                .shadow(
                    color: Theme.accent.opacity(hasDue ? 0.65 : 0.34),
                    radius: hasDue ? 7 : 3.5
                )

            // An always-moving glint; the seam is alive without revealing any
            // note. The overdue state makes it warmer and faster.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.accent.opacity(0),
                            Theme.accent.opacity(hasDue ? 0.95 : 0.6),
                            Color(hex: 0xFFF1E2).opacity(hasDue ? 1 : 0.8),
                            Theme.accent.opacity(hasDue ? 0.95 : 0.6),
                            Theme.accent.opacity(0)
                        ],
                        startPoint: vertical ? .top : .leading,
                        endPoint: vertical ? .bottom : .trailing
                    )
                )
                .frame(
                    width: vertical ? (hasDue ? 4.2 : 3.1) : cometLength,
                    height: vertical ? cometLength : (hasDue ? 4.2 : 3.1)
                )
                .opacity(fade * (hasDue ? 1 : 0.75))
                .shadow(
                    color: Theme.accent.opacity(hasDue ? 0.92 : 0.48),
                    radius: hasDue ? 7 : 4
                )
                .position(
                    x: vertical ? lineX : offset + cometLength / 2,
                    y: vertical ? offset + cometLength / 2 : lineY
                )

            Circle()
                .fill(Color(hex: 0xFFF5EB))
                .frame(width: hasDue ? 5.2 : 3.6, height: hasDue ? 5.2 : 3.6)
                .opacity(fade)
                .shadow(color: Theme.accent.opacity(hasDue ? 0.95 : 0.55), radius: hasDue ? 7 : 4)
                .position(x: dotX, y: dotY)

            // No plate, no frame: the count simply rides beside the moving
            // point during its two visible passes.
            if overdueCount > 0 {
                Text("\(overdueCount)")
                    .font(Theme.mono(8.4, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFF6EA))
                    .shadow(color: Theme.accent.opacity(0.95), radius: 2)
                    .opacity(countOpacity)
                    .position(x: countPosition.x, y: countPosition.y)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
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
