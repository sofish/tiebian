import Foundation

public enum SeamSizing {
    public static let minimumLength: Double = 220
    public static let defaultLength: Double = minimumLength * 2
    public static let maximumRatio: Double = 0.8
    public static let minimumWidth: Double = 2.7
    public static let defaultWidth = minimumWidth * 2
    public static let widthRange = minimumWidth...(minimumWidth * 6)

    public static func width(_ requested: Double) -> Double {
        let value = requested.isFinite ? requested : defaultWidth
        return min(max(value, widthRange.lowerBound), widthRange.upperBound)
    }

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
    private static let animationKey = "EdgePeek.seamAnimation.v1"

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

    public var width: Double {
        get {
            guard let number = defaults.object(forKey: Self.widthKey) as? NSNumber else {
                return SeamSizing.defaultWidth
            }
            return SeamSizing.width(number.doubleValue)
        }
        nonmutating set {
            guard newValue.isFinite else { return }
            defaults.set(SeamSizing.width(newValue), forKey: Self.widthKey)
        }
    }

    public var animation: SeamAnimation {
        get { defaults.string(forKey: Self.animationKey).flatMap(SeamAnimation.init(rawValue:)) ?? .flow }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.animationKey) }
    }
}
