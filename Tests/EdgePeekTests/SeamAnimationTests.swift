import AppKit
import XCTest
import EdgePeekCore
@testable import EdgePeek

@MainActor
final class SeamAnimationTests: XCTestCase {
    private func makeLight(edge: EdgeSide = .left, width: CGFloat = 5.4,
                           mode: SeamAnimation = .flow, due: Bool = false,
                           count: Int = 6) -> SeamLightLayerView {
        _ = NSApplication.shared
        let seamSize = SeamMetrics.panelSize(edge: edge, length: 440, width: width)
        let frame = SeamGlowGeometry(width: width).frame(around: CGRect(origin: .zero, size: seamSize), edge: edge)
        let view = SeamLightLayerView(frame: CGRect(origin: .zero, size: frame.size))
        view.configure(.init(edge: edge, width: width, hasDue: due, noteCount: count,
                             animation: mode), hovered: false)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func child(_ name: String, of layer: CALayer?) throws -> CALayer {
        try XCTUnwrap(layer?.sublayers?.first { $0.name == name })
    }

    func testNativeAnimationsRunWithDurationsAndDoNotRestartOnHover() throws {
        for edge in EdgeSide.allCases {
            for mode in SeamAnimation.allCases {
                let view = makeLight(edge: edge, mode: mode, due: true)
                let target = try child("radiance", of: view.layer)
                let animation = try XCTUnwrap(target.animation(forKey: mode.rawValue) as? CAAnimationGroup)
                XCTAssertGreaterThan(animation.duration, 3)
                XCTAssertEqual(animation.repeatCount, .infinity)
                XCTAssertTrue(try XCTUnwrap(animation.animations).allSatisfy { $0.duration == animation.duration })
                let marker = CABasicAnimation(keyPath: "opacity")
                marker.duration = 60
                target.add(marker, forKey: "do-not-restart")
                view.configure(.init(edge: edge, width: 5.4, hasDue: true, noteCount: 6,
                                     animation: mode), hovered: true)
                view.layoutSubtreeIfNeeded()
                XCTAssertNotNil(target.animation(forKey: "do-not-restart"))
                XCTAssertEqual(target.animation(forKey: mode.rawValue)?.beginTime, animation.beginTime)
            }
        }
    }

    func testSunIsAnEdgeAttachedCapWithTransparentHaloBeyondHitArea() throws {
        for edge in EdgeSide.allCases {
            for width in [SeamSizing.minimumWidth, SeamSizing.defaultWidth, SeamSizing.widthRange.upperBound] {
                let view = makeLight(edge: edge, width: width, mode: .flow)
                let glow = try child("radiance", of: view.layer)
                let core = try child("core", of: glow)
                let halo = try XCTUnwrap(child("atmosphere", of: glow) as? CAGradientLayer)
                let crossPosition = edge.isVertical ? glow.position.x : glow.position.y
                let depth = edge.isVertical ? view.bounds.width : view.bounds.height
                XCTAssertEqual(crossPosition, edge == .left || edge == .top ? 0 : depth)
                let coreCross = edge.isVertical ? core.position.x : core.position.y
                XCTAssertLessThan(coreCross * (edge == .left || edge == .top ? 1 : -1), 0)
                let coreAlong = edge.isVertical ? core.bounds.height : core.bounds.width
                let coreDepth = edge.isVertical ? core.bounds.width : core.bounds.height
                XCTAssertGreaterThan(coreAlong, coreDepth * 3)
                XCTAssertEqual(halo.type, .radial)
                XCTAssertGreaterThan(halo.endPoint.x, halo.startPoint.x)
                XCTAssertGreaterThan(halo.endPoint.y, halo.startPoint.y)
                let colors = try XCTUnwrap(halo.colors as? [CGColor])
                let last = try XCTUnwrap(colors.last)
                XCTAssertEqual(last.alpha, 0)
                let haloDepth = edge.isVertical ? halo.bounds.width : halo.bounds.height
                XCTAssertGreaterThan(haloDepth / 2, width * 4)
                XCTAssertGreaterThanOrEqual(depth, haloDepth / 2)
                XCTAssertNil(view.hitTest(.zero))
            }
        }
    }

    func testFlowCrossesFullSeamAndDueStateRemainsCalmerThanOldFastLoop() throws {
        for edge in EdgeSide.allCases {
            let view = makeLight(edge: edge, due: true)
            let glow = try child("radiance", of: view.layer)
            let flow = try XCTUnwrap(glow.animation(forKey: "flow") as? CAAnimationGroup)
            let move = try XCTUnwrap(flow.animations?.first as? CABasicAnimation)
            XCTAssertEqual(move.keyPath, edge.isVertical ? "transform.translation.y" : "transform.translation.x")
            XCTAssertEqual(move.toValue as? CGFloat, 440)
            let count = try XCTUnwrap(child("count", of: glow) as? CATextLayer)
            XCTAssertFalse(count.isHidden)
            XCTAssertEqual(count.string as? String, "6")
            XCTAssertNil(count.animation(forKey: "count"))
            let normal = SeamLightConfiguration(edge: edge, width: 5.4, hasDue: false, noteCount: 6, animation: .flow)
            XCTAssertLessThan(flow.duration, normal.cycle)
        }
    }

    func testRipplesOverlapHalfACycleApartAndBreatheReturnsWithoutJump() throws {
        let ripple = makeLight(mode: .ripple)
        let glow = try child("radiance", of: ripple.layer)
        let echo = try child("echo", of: ripple.layer)
        let first = try XCTUnwrap(glow.animation(forKey: "ripple"))
        let second = try XCTUnwrap(echo.animation(forKey: "ripple"))
        XCTAssertFalse(echo.isHidden)
        XCTAssertEqual(first.beginTime - second.beginTime, first.duration / 2, accuracy: 0.001)
        let ring = try XCTUnwrap(child("atmosphere", of: glow) as? CAGradientLayer)
        let ringColors = try XCTUnwrap(ring.colors as? [CGColor])
        XCTAssertEqual(ringColors.first?.alpha, 0)
        XCTAssertEqual(ringColors.last?.alpha, 0)
        XCTAssertGreaterThan(ringColors[3].alpha, 0.5)
        XCTAssertEqual(ring.locations?[3].doubleValue, 0.78)
        XCTAssertTrue(try child("core", of: glow).isHidden)
        let group = try XCTUnwrap(first as? CAAnimationGroup)
        let spread = try XCTUnwrap(group.animations?.first as? CABasicAnimation)
        XCTAssertEqual(spread.keyPath, "transform.scale")
        XCTAssertEqual(spread.toValue as? Double, 1)
        let breathe = makeLight(mode: .breathe)
        let breathing = try XCTUnwrap(child("radiance", of: breathe.layer).animation(forKey: "breathe") as? CAAnimationGroup)
        XCTAssertEqual(breathing.animations?.count, 1)
        for animation in try XCTUnwrap(breathing.animations) {
            let keyframe = try XCTUnwrap(animation as? CAKeyframeAnimation)
            XCTAssertEqual(keyframe.keyPath, "opacity")
            XCTAssertEqual(keyframe.values?.first as? Double, keyframe.values?.last as? Double)
        }
        XCTAssertFalse(try child("count", of: breathe.layer).isHidden)
    }

    func testCountSizeIsAdjustableWithoutRebuildingTheGlow() throws {
        let view = makeLight()
        let glow = try child("radiance", of: view.layer)
        let keep = CABasicAnimation(keyPath: "opacity")
        keep.duration = 60
        glow.add(keep, forKey: "keep")
        let small = try XCTUnwrap(child("count", of: glow) as? CATextLayer)
        let smallFrame = small.frame

        view.configure(.init(edge: .left, width: 5.4, hasDue: false, noteCount: 6,
                             animation: .flow, countSize: 15), hovered: false)

        let large = try XCTUnwrap(child("count", of: glow) as? CATextLayer)
        XCTAssertEqual(large.fontSize, 15)
        XCTAssertGreaterThan(large.frame.width, smallFrame.width)
        XCTAssertGreaterThan(large.frame.height, smallFrame.height)
        XCTAssertNotNil(glow.animation(forKey: "keep"))
    }

    func testLightCountShowsEveryNoteAndTurnsRedOnlyWhenOverdue() throws {
        let normal = makeLight(due: false)
        let normalCount = try XCTUnwrap(child("count", of: try child("radiance", of: normal.layer)) as? CATextLayer)
        XCTAssertEqual(normalCount.string as? String, "6")
        XCTAssertFalse(normalCount.isHidden)
        let normalColor = try XCTUnwrap(
            NSColor(cgColor: try XCTUnwrap(normalCount.foregroundColor))?
                .usingColorSpace(.sRGB)
        )

        let overdue = makeLight(due: true)
        let overdueCount = try XCTUnwrap(child("count", of: try child("radiance", of: overdue.layer)) as? CATextLayer)
        XCTAssertEqual(overdueCount.string as? String, "6")
        XCTAssertFalse(overdueCount.isHidden)
        let overdueColor = try XCTUnwrap(
            NSColor(cgColor: try XCTUnwrap(overdueCount.foregroundColor))?
                .usingColorSpace(.sRGB)
        )
        XCTAssertGreaterThan(overdueColor.redComponent, overdueColor.greenComponent)
        XCTAssertGreaterThan(overdueColor.redComponent, overdueColor.blueComponent)
        XCTAssertGreaterThan(normalColor.greenComponent, 0.9)

        let empty = makeLight(count: 0)
        XCTAssertTrue(try XCTUnwrap(child("count", of: try child("radiance", of: empty.layer)) as? CATextLayer).isHidden)
    }

    func testCountOnlyChangeUpdatesTheNumberWithoutRestartingTheGlow() throws {
        let view = makeLight(due: false)
        let glow = try child("radiance", of: view.layer)
        let flow = try XCTUnwrap(glow.animation(forKey: "flow"))
        view.configure(
            .init(edge: .left, width: 5.4, hasDue: false, noteCount: 12, animation: .flow),
            hovered: false
        )
        view.layoutSubtreeIfNeeded()
        let count = try XCTUnwrap(child("count", of: glow) as? CATextLayer)
        XCTAssertEqual(count.string as? String, "12")
        XCTAssertTrue(glow.animation(forKey: "flow") === flow)
    }

    func testExpandedWindowFollowsSeamWithoutExpandingItsMouseTargetAndDetaches() throws {
        _ = NSApplication.shared
        let seam = PanelFactory.make(frame: CGRect(x: 100, y: 200, width: 440, height: 24), keyable: false)
        let host = SeamLightHostView(frame: CGRect(origin: .zero, size: seam.frame.size))
        host.configure(.init(edge: .bottom, width: 5.4, hasDue: false, noteCount: 6, animation: .flow), hovered: false)
        seam.contentView = host
        seam.orderFrontRegardless()
        defer { host.detachLight(); seam.orderOut(nil) }
        let panel = try XCTUnwrap(host.lightPanel)
        XCTAssertTrue(panel.parent === seam)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertEqual(seam.frame.size, CGSize(width: 440, height: 24))
        XCTAssertGreaterThan(panel.frame.height, seam.frame.height)
        XCTAssertLessThan(panel.frame.minX, seam.frame.minX)
        XCTAssertGreaterThan(panel.frame.maxX, seam.frame.maxX)
        XCTAssertEqual(panel.frame.minY, seam.frame.minY)
        let before = panel.frame.origin
        seam.setFrameOrigin(CGPoint(x: seam.frame.minX + 50, y: seam.frame.minY + 30))
        XCTAssertEqual(panel.frame.minX - before.x, 50, accuracy: 0.001)
        XCTAssertEqual(panel.frame.minY - before.y, 30, accuracy: 0.001)
        host.configure(.init(edge: .right, width: 16.2, hasDue: true, noteCount: 6, animation: .ripple), hovered: false)
        seam.setFrame(CGRect(x: 600, y: 100, width: 42, height: 220), display: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.frame.maxX, seam.frame.maxX)
        XCTAssertGreaterThan(panel.frame.height, seam.frame.height)
        XCTAssertGreaterThan(panel.frame.width, seam.frame.width)
        seam.orderOut(nil)
        XCTAssertFalse(panel.isVisible)
        host.detachLight()
        XCTAssertNil(panel.parent)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(host.lightPanel)
    }

    func testGlowWindowHasRoomOnAllEdgesAndWidths() {
        for edge in EdgeSide.allCases {
            for width in [SeamSizing.minimumWidth, SeamSizing.defaultWidth, SeamSizing.widthRange.upperBound] {
                let size = SeamMetrics.panelSize(edge: edge, length: 220, width: width)
                let seam = CGRect(origin: CGPoint(x: -500, y: 120), size: size)
                let geometry = SeamGlowGeometry(width: width)
                let frame = geometry.frame(around: seam, edge: edge)
                XCTAssertTrue(frame.insetBy(dx: -0.001, dy: -0.001).contains(seam))
                let extra = edge.isVertical ? frame.height - seam.height : frame.width - seam.width
                XCTAssertEqual(extra, geometry.overflow * 2)
                XCTAssertGreaterThanOrEqual(geometry.overflow, geometry.haloLength / 2)
                switch edge {
                case .left: XCTAssertEqual(frame.minX, seam.minX, accuracy: 0.001)
                case .right: XCTAssertEqual(frame.maxX, seam.maxX, accuracy: 0.001)
                case .top: XCTAssertEqual(frame.maxY, seam.maxY, accuracy: 0.001)
                case .bottom: XCTAssertEqual(frame.minY, seam.minY, accuracy: 0.001)
                }
            }
        }
    }

    func testRenderedHaloSurvivesBeyondTheMouseStripAndFadesBeforeWindowBoundary() throws {
        let view = makeLight(mode: .breathe)
        let glow = try child("radiance", of: view.layer)
        glow.removeAllAnimations()
        glow.opacity = 1
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let middle = bitmap.pixelsHigh / 2
        let beyondHitArea = try XCTUnwrap(bitmap.colorAt(x: Int(33 * scale), y: middle))
        let boundary = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: middle))
        XCTAssertGreaterThan(beyondHitArea.alphaComponent, 0.01)
        XCTAssertLessThan(boundary.alphaComponent, 0.005)
    }

    func testSwitchingModesClearsWaveStopsAndReparentsTheReminder() throws {
        let view = makeLight(mode: .ripple, due: true)
        for mode in [SeamAnimation.flow, .breathe, .ripple, .flow] {
            view.configure(.init(edge: .left, width: 5.4, hasDue: true, noteCount: 6, animation: mode),
                           hovered: false)
            view.layoutSubtreeIfNeeded()
            let glow = try child("radiance", of: view.layer)
            let ring = try XCTUnwrap(child("atmosphere", of: glow) as? CAGradientLayer)
            let isRipple = mode == .ripple
            XCTAssertEqual(try child("core", of: glow).isHidden, isRipple)
            XCTAssertEqual(try child("echo", of: view.layer).isHidden, !isRipple)
            XCTAssertEqual(ring.locations != nil, isRipple)
            XCTAssertEqual(glow.animationKeys(), [mode.rawValue])
            let count = try child("count", of: mode == .flow ? glow : view.layer)
            XCTAssertFalse(count.isHidden)
        }
    }

    func testTaperTouchesOuterEdgeAndIsThickestInMiddleOnAllSides() {
        for edge in EdgeSide.allCases {
            let size = edge.isVertical ? CGSize(width: 6, height: 440) : CGSize(width: 440, height: 6)
            let path = SeamLightLayerView.taperedPath(size: size, edge: edge)
            let cross: CGFloat = edge == .right || edge == .bottom ? 0.5 : 5.5
            let middle = edge.isVertical ? CGPoint(x: cross, y: 220) : CGPoint(x: 220, y: cross)
            let tip = edge.isVertical ? CGPoint(x: cross, y: 1) : CGPoint(x: 1, y: cross)
            XCTAssertTrue(path.contains(middle))
            XCTAssertFalse(path.contains(tip))
            XCTAssertEqual(path.boundingBoxOfPath.width, size.width, accuracy: 0.001)
            XCTAssertEqual(path.boundingBoxOfPath.height, size.height, accuracy: 0.001)
        }
    }
}
