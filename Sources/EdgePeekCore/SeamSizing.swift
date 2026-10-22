import Foundation

public enum SeamSizing {
    public static let minimumLength: Double = 220
    public static let defaultLength: Double = minimumLength * 2
    public static let maximumRatio: Double = 0.8
    public static let minimumWidth: Double = 2.7
    public static let defaultWidth = minimumWidth * 2
    public static let widthRange = minimumWidth...(minimumWidth * 6)
    public static let defaultCountSize: Double = 8.4
    public static let countSizeRange: ClosedRange<Double> = 6...18

    public static func width(_ requested: Double) -> Double {
        clamped(requested, fallback: defaultWidth, to: widthRange)
    }

    public static func countSize(_ requested: Double) -> Double {
        clamped(requested, fallback: defaultCountSize, to: countSizeRange)
    }

    private static func clamped(
        _ requested: Double,
        fallback: Double,
        to range: ClosedRange<Double>
    ) -> Double {
        let value = requested.isFinite ? requested : fallback
        return EdgeGeometry.clamp(value, lower: range.lowerBound, upper: range.upperBound)
    }

    public static func range(edge: EdgeSide, availableSize: CGSize) -> ClosedRange<Double> {
        let side = edge.isVertical ? availableSize.height : availableSize.width
        let maximum = max(1, floor(side * maximumRatio))
        return min(minimumLength, maximum)...maximum
    }

    public static func length(_ requested: Double, edge: EdgeSide, availableSize: CGSize) -> Double {
        clamped(
            requested,
            fallback: defaultLength,
            to: range(edge: edge, availableSize: availableSize)
        )
    }
}

public enum SeamAnimation: String, CaseIterable {
    case flow, breathe, ripple

    public var title: String {
        switch self {
        case .flow: return "流光"
        case .breathe: return "呼吸"
        case .ripple: return "涟漪"
        }
    }
}

public struct SeamPreferences {
    private let defaults: UserDefaults
    private static let key = "EdgePeek.seamLength.v1"
    private static let widthKey = "EdgePeek.seamWidth.v1"
    private static let countSizeKey = "EdgePeek.seamCountSize.v1"
    private static let animationKey = "EdgePeek.seamAnimation.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var length: Double {
        get {
            readDouble(Self.key).map { max(SeamSizing.minimumLength, $0) }
                ?? SeamSizing.defaultLength
        }
        nonmutating set {
            guard newValue.isFinite else { return }
            defaults.set(max(SeamSizing.minimumLength, newValue), forKey: Self.key)
        }
    }

    public var width: Double {
        get { readDouble(Self.widthKey).map(SeamSizing.width) ?? SeamSizing.defaultWidth }
        nonmutating set {
            guard newValue.isFinite else { return }
            defaults.set(SeamSizing.width(newValue), forKey: Self.widthKey)
        }
    }

    public var countSize: Double {
        get { readDouble(Self.countSizeKey).map(SeamSizing.countSize) ?? SeamSizing.defaultCountSize }
        nonmutating set {
            guard newValue.isFinite else { return }
            defaults.set(SeamSizing.countSize(newValue), forKey: Self.countSizeKey)
        }
    }

    private func readDouble(_ key: String) -> Double? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    public var animation: SeamAnimation {
        get { defaults.string(forKey: Self.animationKey).flatMap(SeamAnimation.init(rawValue:)) ?? .flow }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.animationKey) }
    }
}
