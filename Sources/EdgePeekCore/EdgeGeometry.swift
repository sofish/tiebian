import Foundation
import CoreGraphics

/// The four edges a peeking note handle can live on.
public enum EdgeSide: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case top
    case bottom

    public var isVertical: Bool {
        self == .left || self == .right
    }

    public var displayName: String {
        switch self {
        case .left: return "左边"
        case .right: return "右边"
        case .top: return "上边"
        case .bottom: return "下边"
        }
    }
}

/// A position on a screen edge. `fraction` is the centre of the handle along
/// the usable part of that edge, expressed from 0 (top/left) to 1 (bottom/right).
public struct EdgeAnchor: Codable, Equatable, Sendable {
    public var edge: EdgeSide
    public var fraction: CGFloat
    public var displayID: UInt32?

    public init(edge: EdgeSide, fraction: CGFloat, displayID: UInt32? = nil) {
        self.edge = edge
        self.fraction = fraction
        self.displayID = displayID
    }
}

public enum EdgeGeometry {
    /// The frame for a handle of `size` sitting on `anchor.edge`.
    /// Coordinates use AppKit's bottom-left origin screen space.
    public static func frame(
        for anchor: EdgeAnchor,
        size: CGSize,
        in usableFrame: CGRect,
        inset: CGFloat = 4
    ) -> CGRect {
        let fraction = min(max(anchor.fraction, 0), 1)
        let width = min(size.width, usableFrame.width)
        let height = min(size.height, usableFrame.height)

        switch anchor.edge {
        case .left:
            let x = usableFrame.minX + inset
            let centreY = usableFrame.minY + fraction * usableFrame.height
            let y = clamp(centreY - height / 2,
                          lower: usableFrame.minY + inset,
                          upper: usableFrame.maxY - height - inset)
            return CGRect(x: x, y: y, width: width, height: height).integral

        case .right:
            let x = usableFrame.maxX - width - inset
            let centreY = usableFrame.minY + fraction * usableFrame.height
            let y = clamp(centreY - height / 2,
                          lower: usableFrame.minY + inset,
                          upper: usableFrame.maxY - height - inset)
            return CGRect(x: x, y: y, width: width, height: height).integral

        case .top:
            let y = usableFrame.maxY - height - inset
            let centreX = usableFrame.minX + fraction * usableFrame.width
            let x = clamp(centreX - width / 2,
                          lower: usableFrame.minX + inset,
                          upper: usableFrame.maxX - width - inset)
            return CGRect(x: x, y: y, width: width, height: height).integral

        case .bottom:
            let y = usableFrame.minY + inset
            let centreX = usableFrame.minX + fraction * usableFrame.width
            let x = clamp(centreX - width / 2,
                          lower: usableFrame.minX + inset,
                          upper: usableFrame.maxX - width - inset)
            return CGRect(x: x, y: y, width: width, height: height).integral
        }
    }

    /// Nearest edge to a point, measured to the four sides of the usable frame.
    public static func nearestEdge(to point: CGPoint, in usableFrame: CGRect) -> EdgeSide {
        let distances: [(EdgeSide, CGFloat)] = [
            (.left, abs(point.x - usableFrame.minX)),
            (.right, abs(usableFrame.maxX - point.x)),
            (.top, abs(usableFrame.maxY - point.y)),
            (.bottom, abs(point.y - usableFrame.minY))
        ]
        return distances.min { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? .left
    }

    /// Converts a free-floating frame into a snapped anchor on its nearest edge.
    public static func anchor(
        for panelFrame: CGRect,
        in usableFrame: CGRect,
        displayID: UInt32? = nil
    ) -> EdgeAnchor {
        let centre = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        let edge = nearestEdge(to: centre, in: usableFrame)

        let fraction: CGFloat
        switch edge {
        case .left, .right:
            fraction = usableFrame.height > 0
                ? (centre.y - usableFrame.minY) / usableFrame.height
                : 0.5
        case .top, .bottom:
            fraction = usableFrame.width > 0
                ? (centre.x - usableFrame.minX) / usableFrame.width
                : 0.5
        }

        return EdgeAnchor(edge: edge,
                          fraction: clamp(fraction, lower: 0, upper: 1),
                          displayID: displayID)
    }

    /// The screen whose frame contains the point, falling back to the nearest
    /// screen by squared distance to its centre.
    public static func screenIndex(
        for point: CGPoint,
        among frames: [CGRect]
    ) -> Int? {
        guard !frames.isEmpty else { return nil }
        if let index = frames.firstIndex(where: { $0.contains(point) }) {
            return index
        }
        let ranked = frames.enumerated().min { lhs, rhs in
            squaredDistance(from: point, to: CGPoint(x: lhs.element.midX, y: lhs.element.midY))
                < squaredDistance(from: point, to: CGPoint(x: rhs.element.midX, y: rhs.element.midY))
        }
        return ranked?.offset
    }

    public static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }

    private static func squaredDistance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
