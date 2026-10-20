import Foundation

public enum SeamSizing {
    public static let minimumLength: Double = 220
    public static let defaultLength: Double = minimumLength * 2
    public static let maximumRatio: Double = 0.8

    public static func range(edge: EdgeSide, availableSize: CGSize) -> ClosedRange<Double> {
        let side = edge.isVertical ? availableSize.height : availableSize.width
        let maximum = max(1, floor(side * maximumRatio))
        return min(minimumLength, maximum)...maximum
    }

    public static func length(_ requested: Double, edge: EdgeSide, availableSize: CGSize) -> Double {
        let range = range(edge: edge, availableSize: availableSize)
        let value = requested.isFinite ? requested : defaultLength
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

public struct SeamSizePreference {
    private let defaults: UserDefaults
    private static let key = "EdgePeek.seamLength.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var length: Double {
        get {
            guard let number = defaults.object(forKey: Self.key) as? NSNumber,
                  number.doubleValue.isFinite else { return SeamSizing.defaultLength }
            return max(SeamSizing.minimumLength, number.doubleValue)
        }
        nonmutating set {
            guard newValue.isFinite else { return }
            defaults.set(max(SeamSizing.minimumLength, newValue), forKey: Self.key)
        }
    }
}
