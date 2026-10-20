import AppKit
import XCTest
import EdgePeekCore
@testable import EdgePeek

@MainActor
final class SeamAnimationTests: XCTestCase {
    func testNativeAnimationsRunWithDurationsAndDoNotRestartOnHover() throws {
        _ = NSApplication.shared
        let view = SeamLightLayerView(frame: CGRect(x: 0, y: 0, width: 32, height: 440))
        for mode in SeamAnimation.allCases {
            let config = SeamLightConfiguration(edge: .left, width: 5.4, hasDue: true,
                                               overdueCount: 2, animation: mode)
            view.configure(config, hovered: false)
            view.layoutSubtreeIfNeeded()
            let layers = try XCTUnwrap(view.layer?.sublayers)
            let key: String
            let target: CALayer
            switch mode {
            case .flow: target = layers[2]; key = "flow"
            case .breathe: target = layers[0]; key = "breathe"
            case .ripple: target = layers[1]; key = "ripple"
            }
            let animation = try XCTUnwrap(target.animation(forKey: key))
            XCTAssertGreaterThan(animation.duration, 1)
            XCTAssertEqual(animation.repeatCount, .infinity)
            if let group = animation as? CAAnimationGroup {
                XCTAssertTrue(try XCTUnwrap(group.animations).allSatisfy { $0.duration == group.duration })
            }
            let marker = CABasicAnimation(keyPath: "opacity")
            marker.duration = 60
            target.add(marker, forKey: "do-not-restart")
            view.configure(config, hovered: true)
            view.layoutSubtreeIfNeeded()
            XCTAssertNotNil(target.animation(forKey: "do-not-restart"))
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
