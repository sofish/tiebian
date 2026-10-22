import Foundation

/// The three reading sizes a person can pick for note copy. The board card and
/// the hover preview scale together so the same note reads consistently in
/// both places.
public enum NoteFontSize: String, CaseIterable, Sendable {
    case compact
    case standard
    case large

    public var title: String {
        switch self {
        case .compact: return "小字"
        case .standard: return "标准"
        case .large: return "大字"
        }
    }

    /// Point size of the copy printed on a board card.
    public var cardPointSize: CGFloat {
        switch self {
        case .compact: return 11.6
        case .standard: return 12.4
        case .large: return 13.6
        }
    }

    /// The preview has always run roughly four points larger than the card;
    /// keep that relationship instead of maintaining a second set of sizes.
    public var previewPointSize: CGFloat { cardPointSize + 4.1 }
}

public struct NoteFontPreferences {
    private let defaults: UserDefaults
    static let defaultsKey = "EdgePeek.noteFontSize.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var size: NoteFontSize {
        get {
            defaults.string(forKey: Self.defaultsKey)
                .flatMap(NoteFontSize.init(rawValue:)) ?? .standard
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.defaultsKey) }
    }
}
