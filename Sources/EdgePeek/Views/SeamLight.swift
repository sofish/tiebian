import AppKit
import EdgePeekCore
import SwiftUI

struct SeamLightConfiguration: Equatable {
    var edge: EdgeSide
    var width: CGFloat
    var hasDue: Bool
    var overdueCount: Int
    var animation: SeamAnimation
}

struct SeamLight: NSViewRepresentable {
    let configuration: SeamLightConfiguration
    let hovered: Bool

    func makeNSView(context: Context) -> SeamLightLayerView { SeamLightLayerView() }

    func updateNSView(_ view: SeamLightLayerView, context: Context) {
        view.configure(configuration, hovered: hovered)
    }
}

final class SeamLightLayerView: NSView {
    private let base = CAGradientLayer()
    private let pulse = CAGradientLayer()
    private let motion = CALayer()
    private let comet = CAGradientLayer()
    private let dot = CALayer()
    private let count = CATextLayer()
    private var configuration: SeamLightConfiguration?
    private var hovered = false
    private var renderedSize = CGSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.isGeometryFlipped = true
        layer?.addSublayer(base)
        layer?.addSublayer(pulse)
        layer?.addSublayer(motion)
        motion.addSublayer(comet)
        motion.addSublayer(dot)
        motion.addSublayer(count)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ value: SeamLightConfiguration, hovered: Bool) {
        if configuration != value {
            configuration = value
            renderedSize = .zero
            needsLayout = true
        }
        self.hovered = hovered
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.opacity = Float(value.hasDue ? 0.85 : (hovered ? 0.68 : 0.48))
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        guard let style = configuration, bounds.width > 0, bounds.height > 0,
              renderedSize != bounds.size else { return }
        renderedSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for layer in [base, pulse, motion, count] { layer.removeAllAnimations() }

        let vertical = style.edge.isVertical
        let length = max(19, vertical ? bounds.height : bounds.width)
        let center = SeamMetrics.lineCenter(edge: style.edge, size: bounds.size, width: style.width)
        let baseSize = vertical ? CGSize(width: style.width, height: length - 18)
            : CGSize(width: length - 18, height: style.width)
        let baseFrame = CGRect(x: center.x - baseSize.width / 2, y: center.y - baseSize.height / 2,
                               width: baseSize.width, height: baseSize.height)
        let accent = NSColor(Theme.accent)
        for light in [base, pulse, comet] {
            light.colors = [accent.withAlphaComponent(0).cgColor, accent.withAlphaComponent(0.7).cgColor,
                            NSColor(red: 1, green: 0.95, blue: 0.89, alpha: 0.95).cgColor,
                            accent.withAlphaComponent(0.7).cgColor, accent.withAlphaComponent(0).cgColor]
            light.startPoint = vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
            light.endPoint = vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
            light.shadowColor = accent.cgColor
            light.shadowOpacity = style.hasDue ? 0.9 : 0.5
            light.shadowRadius = style.hasDue ? 7 : 4
        }
        base.frame = baseFrame
        pulse.frame = baseFrame
        for light in [base, pulse] {
            let mask = CAShapeLayer()
            mask.path = Self.taperedPath(size: baseSize, edge: style.edge)
            light.mask = mask
        }
        base.opacity = Float(style.hasDue ? 0.85 : (hovered ? 0.68 : 0.48))
        pulse.isHidden = style.animation != .ripple
        motion.isHidden = style.animation != .flow

        switch style.animation {
        case .breathe:
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = style.hasDue ? 0.45 : 0.18
            breathe.toValue = style.hasDue ? 1 : 0.75
            breathe.duration = style.hasDue ? 1.7 : 2.6
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            base.add(breathe, forKey: "breathe")
        case .ripple:
            let expand = CABasicAnimation(keyPath: vertical ? "transform.scale.y" : "transform.scale.x")
            expand.fromValue = 0.04
            expand.toValue = 1
            expand.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let wave = CAAnimationGroup()
            wave.duration = style.hasDue ? 2.6 : 4.4
            wave.repeatCount = .infinity
            wave.animations = [expand, Self.fade(values: [0, 0.9, 0], times: [0, 0.3, 1])]
            wave.animations?.forEach { $0.duration = wave.duration }
            pulse.add(wave, forKey: "ripple")
        case .flow:
            motion.frame = bounds
            let cometLength = min(64, max(1, length - 18))
            let cometWidth = SeamMetrics.cometWidth(width: style.width, hasDue: style.hasDue)
            let dotWidth = SeamMetrics.dotWidth(width: style.width, hasDue: style.hasDue)
            let position = vertical ? CGPoint(x: center.x, y: 9 + cometLength / 2)
                : CGPoint(x: 9 + cometLength / 2, y: center.y)
            let size = vertical ? CGSize(width: cometWidth, height: cometLength)
                : CGSize(width: cometLength, height: cometWidth)
            comet.frame = CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2,
                                 width: size.width, height: size.height)
            let mask = CAShapeLayer()
            mask.path = Self.taperedPath(size: size, edge: style.edge)
            comet.mask = mask
            dot.frame = CGRect(x: position.x - dotWidth / 2, y: position.y - dotWidth / 2,
                               width: dotWidth, height: dotWidth)
            dot.cornerRadius = dotWidth / 2
            dot.backgroundColor = NSColor(red: 1, green: 0.96, blue: 0.92, alpha: 1).cgColor
            dot.shadowColor = accent.cgColor
            dot.shadowOpacity = 0.9
            dot.shadowRadius = style.hasDue ? 7 : 4
            let cycle = style.hasDue ? 2.8 : 5.2
            let move = CABasicAnimation(keyPath: vertical ? "transform.translation.y" : "transform.translation.x")
            move.fromValue = 0
            move.toValue = max(0, length - cometLength - 18)
            move.timingFunction = CAMediaTimingFunction(name: .linear)
            let flow = CAAnimationGroup()
            flow.duration = cycle
            flow.repeatCount = .infinity
            flow.animations = [move, Self.fade(values: [0, 1, 1, 0], times: [0, 0.16, 0.84, 1])]
            flow.animations?.forEach { $0.duration = flow.duration }
            motion.add(flow, forKey: "flow")
        }
        let countCycle: Double
        switch style.animation {
        case .flow: countCycle = style.hasDue ? 2.8 : 5.2
        case .breathe: countCycle = style.hasDue ? 3.4 : 5.2
        case .ripple: countCycle = style.hasDue ? 2.6 : 4.4
        }
        let cometLength = min(64, max(1, length - 18))
        let position = style.animation == .flow
            ? (vertical ? CGPoint(x: center.x, y: 9 + cometLength / 2)
                        : CGPoint(x: 9 + cometLength / 2, y: center.y))
            : center
        if style.animation == .flow { motion.addSublayer(count) } else { layer?.addSublayer(count) }
        let offset = SeamMetrics.countOffset(width: style.width)
        var countPosition = position
        switch style.edge {
        case .left: countPosition.x += offset
        case .right: countPosition.x -= offset
        case .top: countPosition.y += offset
        case .bottom: countPosition.y -= offset
        }
        count.frame = CGRect(x: countPosition.x - 10, y: countPosition.y - 6, width: 20, height: 14)
        count.string = "\(style.overdueCount)"
        count.font = NSFont.monospacedSystemFont(ofSize: 8.4, weight: .bold)
        count.fontSize = 8.4
        count.alignmentMode = .center
        count.foregroundColor = NSColor.white.cgColor
        count.contentsScale = window?.backingScaleFactor ?? 2
        count.isHidden = style.overdueCount == 0
        let visibility = Self.fade(values: [0, 1, 1, 0, 0], times: [0, 0.04, 0.46, 0.5, 1])
        visibility.duration = countCycle * 4
        visibility.repeatCount = .infinity
        count.add(visibility, forKey: "count")
    }

    private static func fade(values: [Double], times: [NSNumber]) -> CAKeyframeAnimation {
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = values
        fade.keyTimes = times
        return fade
    }

    static func taperedPath(size: CGSize, edge: EdgeSide) -> CGPath {
        let width = edge.isVertical ? size.width : size.height
        let length = edge.isVertical ? size.height : size.width
        func point(_ cross: CGFloat, _ along: CGFloat) -> CGPoint {
            let cross = edge == .right || edge == .bottom ? width - cross : cross
            return edge.isVertical ? CGPoint(x: cross, y: along) : CGPoint(x: along, y: cross)
        }
        let path = CGMutablePath()
        path.move(to: point(0, 0))
        path.addLine(to: point(0, length))
        path.addCurve(to: point(0, 0), control1: point(width * 4 / 3, length * 0.8),
                      control2: point(width * 4 / 3, length * 0.2))
        path.closeSubpath()
        return path
    }
}
