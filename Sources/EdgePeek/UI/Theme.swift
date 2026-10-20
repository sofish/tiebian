import AppKit
import SwiftUI
import EdgePeekCore

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {
    static let ink = Color(hex: 0x2F2A24)
    static let inkSoft = Color(hex: 0x7A7064)
    static let inkFaint = Color(hex: 0xA89C8D)
    static let accent = Color(hex: 0xC96F45)
    static let accentDeep = Color(hex: 0xA95534)
    static let accentSoft = Color(hex: 0xE8B59A)
    static let paper = Color(hex: 0xF7F1E6)
    static let paperDeep = Color(hex: 0xEDE3D2)
    static let line = Color(hex: 0xD8CBB8)
    static let tape = Color(hex: 0xBEB4A4)
    static let glassTop = Color(hex: 0xF9F3E8)
    static let glassBottom = Color(hex: 0xEDE1CD)
    static let shadow = Color(hex: 0x3A2E22)

    /// Chinese display face. All Chinese copy in the app goes through this
    /// (directly, or via `MixedText`).
    static func serif(_ size: CGFloat) -> Font {
        .custom(AppFonts.chineseName, size: size)
    }

    static func hand(_ size: CGFloat) -> Font {
        serif(size)
    }

    static func marker(_ size: CGFloat) -> Font {
        serif(size)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        serif(size)
    }

    /// Latin letters, digits and code. The monospaced face is deliberately
    /// paired with the old Song Chinese face.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let quickSpring = Animation.spring(response: 0.24, dampingFraction: 0.8)
}

extension NoteColor {
    var paperTop: Color {
        switch self {
        case .cream: return Color(hex: 0xF8F1E2)
        case .apricot: return Color(hex: 0xF7E3D3)
        case .rose: return Color(hex: 0xF5DFE1)
        case .sage: return Color(hex: 0xE9EDDE)
        case .sky: return Color(hex: 0xE2EBEE)
        case .lilac: return Color(hex: 0xEBE4EE)
        case .kraft: return Color(hex: 0xEDE1CB)
        }
    }

    var paperBottom: Color {
        switch self {
        case .cream: return Color(hex: 0xF1E7D4)
        case .apricot: return Color(hex: 0xF1D3BF)
        case .rose: return Color(hex: 0xEFD1D5)
        case .sage: return Color(hex: 0xDEE5D0)
        case .sky: return Color(hex: 0xD7E3E7)
        case .lilac: return Color(hex: 0xE2D8E6)
        case .kraft: return Color(hex: 0xE4D5BB)
        }
    }

    var paperEdge: Color {
        switch self {
        case .cream: return Color(hex: 0xDDCBA9)
        case .apricot: return Color(hex: 0xDDA98D)
        case .rose: return Color(hex: 0xD9ABB4)
        case .sage: return Color(hex: 0xB5C1A3)
        case .sky: return Color(hex: 0xA8BEC6)
        case .lilac: return Color(hex: 0xBFAEC7)
        case .kraft: return Color(hex: 0xCBB48D)
        }
    }

    var dot: Color {
        switch self {
        case .cream: return Color(hex: 0xC99A4B)
        case .apricot: return Color(hex: 0xC96F45)
        case .rose: return Color(hex: 0xB7677A)
        case .sage: return Color(hex: 0x7C9167)
        case .sky: return Color(hex: 0x5F8492)
        case .lilac: return Color(hex: 0x8C6F9C)
        case .kraft: return Color(hex: 0x997A4E)
        }
    }
}

enum DateText {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static func relative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 60 * 60 * 24 * 7 {
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return dayFormatter.string(from: date)
    }

    static func stamp(_ date: Date, includeTime: Bool = true) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date)
            ? "今天"
            : (calendar.isDateInYesterday(date) ? "昨天" : dayFormatter.string(from: date))
        if includeTime {
            return "\(day) \(timeFormatter.string(from: date))"
        }
        return day
    }

    static func dueShort(_ date: Date) -> String {
        if date <= Date() { return "已到期" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInTomorrow(date) {
            return "明天 \(timeFormatter.string(from: date))"
        }
        return "\(dayFormatter.string(from: date)) \(timeFormatter.string(from: date))"
    }

    static func dueFull(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInTomorrow(date) {
            return "明天 \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(timeFormatter.string(from: date))"
        }
        return "\(dayFormatter.string(from: date)) \(timeFormatter.string(from: date))"
    }
}
