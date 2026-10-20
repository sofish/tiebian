import AppKit
import EdgePeekCore
import SwiftUI

@MainActor
final class EdgeGlowWindow {
    private let panel: NSPanel
    private let host: NSHostingView<AnyView>
    private var visible = false

    init() {
        panel = PanelFactory.make(frame: NSRect(x: 0, y: 0, width: 10, height: 10), keyable: false)
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.alphaValue = 0

        host = NSHostingView(
            rootView: AnyView(EdgeGlowView(edge: .left, fraction: 0.5))
        )
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func present(in rect: CGRect, edge: EdgeSide, fraction: CGFloat) {
        if panel.frame != rect {
            panel.setFrame(rect, display: true)
        }
        host.rootView = AnyView(EdgeGlowView(edge: edge, fraction: fraction))
        host.frame = NSRect(origin: .zero, size: rect.size)

        if !visible {
            visible = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide(immediately: Bool = false) {
        guard visible else { return }
        visible = false
        if immediately {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.visible else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

struct EdgeGlowView: View {
    let edge: EdgeSide
    let fraction: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let isVertical = edge.isVertical
            let lineLength = isVertical ? max(0, size.height - 60) : max(0, size.width - 60)
            let centreAlong = isVertical
                ? size.height * min(max(fraction, 0), 1)
                : size.width * min(max(fraction, 0), 1)
            let centre = isVertical
                ? CGPoint(
                    x: edge == .left ? 1.5 : size.width - 1.5,
                    y: min(max(centreAlong, 34), size.height - 34)
                  )
                : CGPoint(
                    x: min(max(centreAlong, 34), size.width - 34),
                    y: edge == .top ? size.height - 1.5 : 1.5
                  )

            ZStack {
                // A quiet full-edge breath.
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(
                        gradient(opacity: 0.16, vertical: isVertical)
                    )
                    .frame(
                        width: isVertical ? 1 : lineLength,
                        height: isVertical ? lineLength : 1
                    )
                    .position(
                        x: isVertical ? centre.x : size.width / 2,
                        y: isVertical ? size.height / 2 : centre.y
                    )

                // The bright resting place.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        gradient(opacity: 0.9, vertical: isVertical)
                    )
                    .frame(
                        width: isVertical ? 2.4 : 150,
                        height: isVertical ? 150 : 2.4
                    )
                    .position(centre)
                    .blur(radius: 0.2)
                    .shadow(color: Theme.accent.opacity(0.55), radius: 7)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 3.2, height: 3.2)
                    .position(centre)
                    .shadow(color: Theme.accent.opacity(0.8), radius: 6)
            }
        }
        .allowsHitTesting(false)
        .background(Color.clear)
    }

    private func gradient(opacity: Double, vertical: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                Theme.accent.opacity(0),
                Theme.accent.opacity(opacity),
                Theme.accent.opacity(0)
            ],
            startPoint: vertical ? .top : .leading,
            endPoint: vertical ? .bottom : .trailing
        )
    }
}
