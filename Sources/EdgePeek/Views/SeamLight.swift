import AppKit
import EdgePeekCore
import SwiftUI

struct SeamLightConfiguration: Equatable {
    var edge: EdgeSide
    var width: CGFloat
    var hasDue: Bool
    var noteCount: Int
    var animation: SeamAnimation
    var countSize: CGFloat = SeamSizing.defaultCountSize

    var cycle: CFTimeInterval {
        switch animation {
        case .flow: return hasDue ? 5.6 : 8.4
        case .breathe: return hasDue ? 4.8 : 6.8
        case .ripple: return hasDue ? 4.0 : 6.0
        }
    }
}

/// The light has its own click-through window so its halo can exceed the seam's
/// hit area without covering other apps with an invisible mouse target.
struct SeamLight: NSViewRepresentable {
    let configuration: SeamLightConfiguration
    let hovered: Bool

    func makeNSView(context: Context) -> SeamLightHostView { SeamLightHostView() }

    func updateNSView(_ view: SeamLightHostView, context: Context) {
        view.configure(configuration, hovered: hovered)
    }

    static func dismantleNSView(_ view: SeamLightHostView, coordinator: ()) {
        view.detachLight()
    }
}

final class SeamLightHostView: NSView {
    private(set) var lightPanel: NSPanel?
    private let light = SeamLightLayerView()
    private var configuration: SeamLightConfiguration?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ value: SeamLightConfiguration, hovered: Bool) {
        configuration = value
        light.configure(value, hovered: hovered)
        updateLightFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detachLight()
        guard let window else { return }
        let panel = PanelFactory.make(frame: .zero, keyable: false)
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.level = window.level
        panel.contentView = light
        lightPanel = panel
        updateLightFrame()
        window.addChildWindow(panel, ordered: .above)
    }

    override func layout() {
        super.layout()
        updateLightFrame()
    }

    func detachLight() {
        guard let panel = lightPanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.close()
        lightPanel = nil
    }

    private func updateLightFrame() {
        guard let configuration, let window, let lightPanel,
              bounds.width > 0, bounds.height > 0 else { return }
        let seamFrame = window.convertToScreen(convert(bounds, to: nil))
        let frame = SeamGlowGeometry(width: configuration.width)
            .frame(around: seamFrame, edge: configuration.edge)
        if lightPanel.frame != frame { lightPanel.setFrame(frame, display: true) }
        let lightFrame = CGRect(origin: .zero, size: frame.size)
        if light.frame != lightFrame { light.frame = lightFrame }
    }
}

struct SeamGlowGeometry {
    let width: CGFloat

    var scale: CGFloat { sqrt(width / SeamSizing.defaultWidth) }
    var haloLength: CGFloat { 200 * scale }
    var haloDepth: CGFloat { 96 * scale }
    var overflow: CGFloat { ceil(haloLength / 2 + 8) }
    var depth: CGFloat { ceil(haloDepth / 2 + 8) }

    func frame(around seam: CGRect, edge: EdgeSide) -> CGRect {
        switch edge {
        case .left:
            return CGRect(x: seam.minX, y: seam.minY - overflow,
                          width: max(seam.width, depth), height: seam.height + overflow * 2)
        case .right:
            let depth = max(seam.width, depth)
            return CGRect(x: seam.maxX - depth, y: seam.minY - overflow,
                          width: depth, height: seam.height + overflow * 2)
        case .top:
            let depth = max(seam.height, depth)
            return CGRect(x: seam.minX - overflow, y: seam.maxY - depth,
                          width: seam.width + overflow * 2, height: depth)
        case .bottom:
            return CGRect(x: seam.minX - overflow, y: seam.minY,
                          width: seam.width + overflow * 2, height: max(seam.height, depth))
        }
    }
}

private struct SeamRadiance {
    let layer = CALayer()
    let atmosphere = CAGradientLayer()
    let bloom = CAGradientLayer()
    let core = CAGradientLayer()
    let rim = CAGradientLayer()

    init() {
        atmosphere.name = "atmosphere"
        bloom.name = "bloom"
        core.name = "core"
        rim.name = "rim"
        for band in [atmosphere, bloom, core, rim] { layer.addSublayer(band) }
    }
}

final class SeamLightLayerView: NSView {
    /// Everything that changes the geometry or the glow animation. The note
    /// count changes more often than that, so it gets its own cheap update.
    private struct LayoutSignature: Equatable {
        var edge: EdgeSide
        var width: CGFloat
        var hasDue: Bool
        var animation: SeamAnimation
    }

    private static let overdueCountColor = NSColor(srgbRed: 0.95, green: 0.32, blue: 0.24, alpha: 1)
    private static let countShadowColor = NSColor.black.withAlphaComponent(0.45).cgColor

    private let base = CAGradientLayer()
    private let radiance = SeamRadiance()
    private let echo = SeamRadiance()
    private let count = CATextLayer()
    private var configuration: SeamLightConfiguration?
    private var layoutSignature: LayoutSignature?
    private var hovered = false
    private var renderedSize = CGSize.zero
    private var countCenter = CGPoint.zero
    private var appliedCountSize: CGFloat?
    private var appliedCountFrame: CGRect?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        layer?.masksToBounds = true
        base.name = "horizon"
        radiance.layer.name = "radiance"
        echo.layer.name = "echo"
        count.name = "count"
        for child in [base, radiance.layer, echo.layer, count] { layer?.addSublayer(child) }
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ value: SeamLightConfiguration, hovered: Bool) {
        guard configuration != value || self.hovered != hovered else { return }
        if configuration != value {
            let signature = LayoutSignature(
                edge: value.edge,
                width: value.width,
                hasDue: value.hasDue,
                animation: value.animation
            )
            if layoutSignature != signature {
                layoutSignature = signature
                renderedSize = .zero
                needsLayout = true
            }
            configuration = value
            // A count-only change (adding or deleting a note) must update the
            // number without rebuilding the glow or restarting its animation.
            applyCountStyle(value)
        }
        self.hovered = hovered
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if value.hasDue { base.opacity = 0.48 }
        else { base.opacity = hovered ? 0.38 : 0.22 }
        CATransaction.commit()
    }

    private func applyCountStyle(_ style: SeamLightConfiguration) {
        // Sliders call this on every pointer move, and `frame` is animatable;
        // without an explicit transaction each tick would queue a fresh
        // implicit animation and leave the number trailing the drag.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        count.string = "\(style.noteCount)"
        if appliedCountSize != style.countSize {
            appliedCountSize = style.countSize
            count.font = NSFont.monospacedSystemFont(ofSize: style.countSize, weight: .bold)
            count.fontSize = style.countSize
        }
        count.alignmentMode = .center
        // The count always reports every note; overdue turns it red so the
        // reminder reads without hiding the total.
        count.foregroundColor = style.hasDue
            ? Self.overdueCountColor.cgColor
            : NSColor.white.cgColor
        count.shadowColor = Self.countShadowColor
        count.shadowOpacity = 1
        count.shadowRadius = 1.2
        count.shadowOffset = .zero
        count.contentsScale = window?.backingScaleFactor ?? 2
        count.isHidden = style.noteCount == 0

        let halfExtent = SeamMetrics.countHalfExtent(countSize: style.countSize)
        let frame = CGRect(
            x: countCenter.x - halfExtent,
            y: countCenter.y - SeamMetrics.countHeight(countSize: style.countSize) / 2,
            width: halfExtent * 2,
            height: SeamMetrics.countHeight(countSize: style.countSize)
        )
        if appliedCountFrame != frame {
            appliedCountFrame = frame
            count.frame = frame
        }
    }

    override func layout() {
        super.layout()
        guard let style = configuration, bounds.width > 0, bounds.height > 0,
              renderedSize != bounds.size else { return }
        renderedSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for child in [base, radiance.layer, echo.layer, count] { child.removeAllAnimations() }

        let geometry = SeamGlowGeometry(width: style.width)
        let vertical = style.edge.isVertical
        let length = max(1, (vertical ? bounds.height : bounds.width) - geometry.overflow * 2)
        let center = SeamMetrics.lineCenter(edge: style.edge, size: bounds.size, width: style.width)
        let baseSize = vertical ? CGSize(width: style.width, height: max(1, length - 18))
            : CGSize(width: max(1, length - 18), height: style.width)
        base.frame = CGRect(x: center.x - baseSize.width / 2, y: center.y - baseSize.height / 2,
                            width: baseSize.width, height: baseSize.height)
        base.colors = Self.colors([(.amber, 0), (.amber, 0.55), (.gold, 0.8), (.amber, 0.55), (.amber, 0)])
        base.startPoint = vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        base.endPoint = vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        let mask = CAShapeLayer()
        mask.path = Self.taperedPath(size: baseSize, edge: style.edge)
        base.mask = mask

        // The brightest point sits beyond the horizon. Only a soft, flattened
        // cap is visible on screen, never a detached circular bead.
        var horizon = center
        switch style.edge {
        case .left: horizon.x = 0
        case .right: horizon.x = bounds.width
        case .top: horizon.y = 0
        case .bottom: horizon.y = bounds.height
        }
        for glow in [radiance, echo] {
            glow.layer.bounds = .zero
            glow.layer.position = horizon
            glow.layer.opacity = 0
            configureGlow(glow, style: style, geometry: geometry, length: length)
        }
        echo.layer.isHidden = style.animation != .ripple

        switch style.animation {
        case .flow:
            let start = geometry.overflow
            if vertical { radiance.layer.position.y = start } else { radiance.layer.position.x = start }
            let move = CABasicAnimation(keyPath: vertical ? "transform.translation.y" : "transform.translation.x")
            move.fromValue = 0
            move.toValue = length
            move.timingFunction = CAMediaTimingFunction(name: .linear)
            let visibility = Self.keyframes("opacity", values: [0, 1, 1, 0], times: [0, 0.14, 0.86, 1])
            radiance.layer.add(Self.group([move, visibility], duration: style.cycle), forKey: "flow")
        case .breathe:
            let visibility = Self.keyframes("opacity", values: [0.1, 0.12, 0.9, 1, 0.6, 0.1],
                                            times: [0, 0.12, 0.42, 0.52, 0.72, 1])
            radiance.layer.add(Self.group([visibility], duration: style.cycle), forKey: "breathe")
        case .ripple:
            let spread = CABasicAnimation(keyPath: "transform.scale")
            spread.fromValue = 0.08
            spread.toValue = 1
            spread.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let visibility = Self.keyframes("opacity", values: [0, 0.9, 0.55, 0], times: [0, 0.16, 0.55, 1])
            let wave = Self.group([spread, visibility], duration: style.cycle)
            let now = CACurrentMediaTime()
            wave.beginTime = now
            radiance.layer.add(wave, forKey: "ripple")
            wave.beginTime = now - style.cycle / 2
            echo.layer.add(wave, forKey: "ripple")
        }

        if style.animation == .flow { radiance.layer.addSublayer(count) } else { layer?.addSublayer(count) }
        let offset = SeamMetrics.countOffset(width: style.width) + style.width / 2
        var countPosition = style.animation == .flow ? CGPoint.zero : horizon
        switch style.edge {
        case .left: countPosition.x += offset
        case .right: countPosition.x -= offset
        case .top: countPosition.y += offset
        case .bottom: countPosition.y -= offset
        }
        countCenter = countPosition
        applyCountStyle(style)
    }

    private func configureGlow(_ glow: SeamRadiance, style: SeamLightConfiguration,
                               geometry: SeamGlowGeometry, length: CGFloat) {
        let vertical = style.edge.isVertical
        let strength: CGFloat = style.hasDue ? 1.15 : 1
        for band in [glow.bloom, glow.core, glow.rim] { band.isHidden = style.animation == .ripple }
        if style.animation == .ripple {
            configureGradient(glow.atmosphere, edge: style.edge,
                              along: length + geometry.haloLength * 0.4, cross: geometry.haloDepth,
                              stops: [(.amber, 0), (.amber, 0), (.amber, 0.16),
                                      (.gold, 0.65 * strength), (.amber, 0.18), (.amber, 0)])
            glow.atmosphere.locations = [0, 0.6, 0.7, 0.78, 0.86, 1]
            return
        }
        let breathing = style.animation == .breathe
        let haloLength = breathing ? length + geometry.haloLength * 0.4 : geometry.haloLength
        let bloomLength = breathing ? length * 0.85 : 102 * geometry.scale
        let coreLength = breathing ? length * 0.7 : 42 * geometry.scale
        let coreDepth = (3 + style.width * 0.9) * strength
        let outward: CGFloat = style.edge == .left || style.edge == .top ? -1 : 1
        let coreOffset = outward * coreDepth * 0.2
        let position = vertical ? CGPoint(x: coreOffset, y: 0) : CGPoint(x: 0, y: coreOffset)
        let haloStops: [(SunColor, CGFloat)] = breathing
            ? [(.gold, 0.22 * strength), (.gold, 0.12), (.amber, 0.03), (.amber, 0)]
            : [(.amber, 0.42 * strength), (.amber, 0.22), (.amber, 0.06), (.amber, 0)]
        let bloomStops: [(SunColor, CGFloat)] = breathing
            ? [(.white, 0.6), (.gold, 0.3), (.amber, 0.06), (.amber, 0)]
            : [(.gold, 0.78), (.amber, 0.44), (.amber, 0.1), (.amber, 0)]
        configureGradient(glow.atmosphere, edge: style.edge, along: haloLength, cross: geometry.haloDepth,
                          stops: haloStops)
        configureGradient(glow.bloom, edge: style.edge, along: bloomLength, cross: 30 * geometry.scale,
                          stops: bloomStops)
        configureGradient(glow.core, edge: style.edge, along: coreLength, cross: coreDepth, position: position,
                          stops: [(.white, 1), (.gold, 0.9), (.amber, 0.35), (.amber, 0)])
        let rimLength = breathing ? max(1, length - 18) : 112 * geometry.scale
        configureGradient(glow.rim, edge: style.edge, along: rimLength, cross: 1.5,
                          stops: [(.amber, 0), (.gold, 0.8), (.white, 0.95), (.gold, 0.8), (.amber, 0)], axial: true)
    }

    private func configureGradient(_ gradient: CAGradientLayer, edge: EdgeSide, along: CGFloat, cross: CGFloat,
                                   position: CGPoint = .zero, stops: [(SunColor, CGFloat)], axial: Bool = false) {
        let size = edge.isVertical ? CGSize(width: cross, height: along) : CGSize(width: along, height: cross)
        gradient.frame = CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2,
                                width: size.width, height: size.height)
        gradient.colors = Self.colors(stops)
        gradient.locations = nil
        gradient.type = axial ? .axial : .radial
        if axial {
            gradient.startPoint = edge.isVertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
            gradient.endPoint = edge.isVertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        } else {
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 1)
        }
    }

    private enum SunColor {
        case amber, gold, white
        var color: NSColor {
            switch self {
            case .amber: return NSColor(srgbRed: 0.96, green: 0.43, blue: 0.16, alpha: 1)
            case .gold: return NSColor(srgbRed: 1, green: 0.78, blue: 0.43, alpha: 1)
            case .white: return NSColor(srgbRed: 1, green: 0.97, blue: 0.88, alpha: 1)
            }
        }
    }

    private static func colors(_ stops: [(SunColor, CGFloat)]) -> [CGColor] {
        stops.map { $0.0.color.withAlphaComponent($0.1).cgColor }
    }

    private static func keyframes(_ key: String, values: [Double], times: [NSNumber]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = values
        animation.keyTimes = times
        animation.calculationMode = .linear
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count - 1)
        return animation
    }

    private static func group(_ animations: [CAAnimation], duration: CFTimeInterval) -> CAAnimationGroup {
        animations.forEach { $0.duration = duration }
        let group = CAAnimationGroup()
        group.duration = duration
        group.repeatCount = .infinity
        group.animations = animations
        return group
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
