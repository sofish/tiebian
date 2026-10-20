import Foundation

public enum NoteColor: String, Codable, CaseIterable, Sendable {
    case cream
    case apricot
    case rose
    case sage
    case sky
    case lilac
    case kraft

    public var displayName: String {
        switch self {
        case .cream: return "奶白"
        case .apricot: return "杏橙"
        case .rose: return "豆沙"
        case .sage: return "鼠尾草"
        case .sky: return "雾蓝"
        case .lilac: return "丁香"
        case .kraft: return "牛皮"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = NoteColor(rawValue: raw) ?? .cream
    }
}

public struct StickyNote: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var content: String
    public var color: NoteColor
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var dueAt: Date?

    public init(
        id: UUID = UUID(),
        content: String = "",
        color: NoteColor = .cream,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dueAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.color = color
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueAt = dueAt
    }

    public var title: String {
        NoteText.title(from: content)
    }

    public var displayTitle: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "空白便签" : title
    }

    public var excerpt: String {
        NoteText.excerpt(from: content)
    }

    /// The note as it should read on paper: no Markdown punctuation, but
    /// bullets and checkboxes are kept as friendly glyphs. The editor is a
    /// WYSIWYG surface, so this is also where legacy Markdown is softened the
    /// first time a note is opened.
    public var plainText: String {
        NoteText.plainText(from: content)
    }

    public var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isOverdue: Bool {
        guard let dueAt else { return false }
        return dueAt <= Date()
    }

    public var isEmptyIgnoringTags: Bool {
        NoteText.isEffectivelyEmpty(content)
    }

    public var hasDueDate: Bool {
        dueAt != nil
    }
}

public struct NoteGroup: Identifiable, Equatable, Sendable {
    /// The display form of the tag, including its leading `#`. `nil` is the
    /// group for notes without any hashtag.
    public let tag: String?
    public let key: String
    public let notes: [StickyNote]

    public var id: String { key }

    public init(tag: String?, key: String, notes: [StickyNote]) {
        self.tag = tag
        self.key = key
        self.notes = notes
    }
}

public enum NoteLineKind: Equatable, Sendable {
    case heading(Int)
    case checkbox(Bool)
    case bullet
    case quote
    case code
    case divider
    case empty
    case text
}

public struct NoteLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: NoteLineKind
    public let text: String

    public init(id: Int, kind: NoteLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

/// A deliberately small Markdown reader. It is enough to make a note feel
/// composed without turning a sticky note into a full document editor.
public enum NoteText {
    public static func lines(from content: String) -> [NoteLine] {
        let rawLines = content.components(separatedBy: .newlines)
        var result: [NoteLine] = []
        var inCodeBlock = false

        for (index, raw) in rawLines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock {
                result.append(NoteLine(id: index, kind: .code, text: raw))
                continue
            }

            if trimmed.isEmpty {
                if result.last?.kind != .empty {
                    result.append(NoteLine(id: index, kind: .empty, text: ""))
                }
                continue
            }

            if let heading = headingParts(trimmed) {
                result.append(NoteLine(id: index, kind: .heading(heading.level), text: heading.text))
                continue
            }

            if isDivider(trimmed) {
                result.append(NoteLine(id: index, kind: .divider, text: ""))
                continue
            }

            if let checkbox = checkboxParts(trimmed) {
                result.append(NoteLine(id: index, kind: .checkbox(checkbox.checked), text: checkbox.text))
                continue
            }

            if let bullet = bulletText(trimmed) {
                result.append(NoteLine(id: index, kind: .bullet, text: bullet))
                continue
            }

            if trimmed.hasPrefix(">") {
                let text = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                result.append(NoteLine(id: index, kind: .quote, text: text))
                continue
            }

            result.append(NoteLine(id: index, kind: .text, text: trimmed))
        }

        while result.last?.kind == .empty {
            result.removeLast()
        }
        return result
    }

    public static func title(from content: String) -> String {
        guard let first = lines(from: content).first(where: { line in
            line.kind != .empty && line.kind != .divider
        }) else {
            return ""
        }
        return cleanInline(first.text)
    }

    public static func bodyLines(from content: String) -> [NoteLine] {
        let all = lines(from: content)
        guard let titleIndex = all.firstIndex(where: { line in
            line.kind != .empty && line.kind != .divider
        }) else {
            return []
        }
        var body = Array(all.dropFirst(titleIndex + 1))
        while body.first?.kind == .empty { body.removeFirst() }
        return body
    }

    public static func excerpt(from content: String) -> String {
        guard let first = bodyLinesForDisplay(from: content).first(where: { line in
            line.kind != .empty && line.kind != .divider
        }) else {
            return ""
        }
        return cleanInline(first.text)
    }

    /// Render legacy Markdown as plain paper copy. This is intentionally a
    /// one-way simplification: the editor should never show a naked `#` or
    /// `**` to someone who just wants to write a note.
    public static func plainText(from content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")
        var output: [String] = []
        var inCodeBlock = false

        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock {
                output.append(raw)
                continue
            }
            if trimmed.isEmpty {
                output.append("")
                continue
            }
            if let heading = headingParts(trimmed) {
                output.append(cleanInline(heading.text))
                continue
            }
            if isDivider(trimmed) {
                output.append("")
                continue
            }
            if let checkbox = checkboxParts(trimmed) {
                let mark = checkbox.checked ? "☑ " : "☐ "
                output.append(mark + cleanInline(checkbox.text))
                continue
            }
            if let bullet = bulletText(trimmed) {
                output.append("• " + cleanInline(bullet))
                continue
            }
            if trimmed.hasPrefix(">") {
                output.append(
                    cleanInline(
                        String(trimmed.dropFirst())
                            .trimmingCharacters(in: .whitespaces)
                    )
                )
                continue
            }
            output.append(cleanInline(trimmed))
        }

        while output.first == "" { output.removeFirst() }
        while output.last == "" { output.removeLast() }
        return output.joined(separator: "\n")
    }

    /// The body as it should be shown on a note card or preview. Lines that
    /// only carry hashtags are represented by tag chips instead.
    public static func bodyLinesForDisplay(from content: String) -> [NoteLine] {
        var result = bodyLines(from: content).filter { line in
            switch line.kind {
            case .text, .bullet, .quote:
                return !isOnlyTags(line.text)
            default:
                return true
            }
        }
        while result.last?.kind == .empty { result.removeLast() }
        return result
    }

    public static func isOnlyTags(_ text: String) -> Bool {
        let found = tags(in: text)
        guard !found.isEmpty else { return false }
        var remainder = text
        for tag in found {
            remainder = remainder.replacingOccurrences(of: tag, with: "")
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func cleanInline(_ value: String) -> String {
        var text = value
        let replacements: [(String, String)] = [
            ("!\\[([^\\]]*)\\]\\([^)]*\\)", "$1"),
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
            ("`([^`]*)`", "$1"),
            ("\\*\\*([^*]+)\\*\\*", "$1"),
            ("__([^_]+)__", "$1"),
            ("\\*([^*]+)\\*", "$1"),
            ("_([^_]+)_", "$1"),
            ("~~([^~]+)~~", "$1"),
            // A heading has whitespace after its hashes. A hashtag such as
            // `#旅行` is content and must survive.
            ("^#{1,6}\\s+", ""),
            ("^>\\s*", "")
        ]
        for (pattern, template) in replacements {
            text = text.replacingOccurrences(
                of: pattern,
                with: template,
                options: .regularExpression
            )
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hashtags are lowercase-insensitive group keys. Hex colour values such as
    /// `#C96F45` are deliberately not treated as tags.
    public static func tags(in content: String) -> [String] {
        let pattern = "#([\\p{L}\\p{N}_\\-]{1,32})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: (content as NSString).length)
        let matches = regex.matches(in: content, range: range)
        var seen = Set<String>()
        var tags: [String] = []

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let token = (content as NSString).substring(with: match.range(at: 1))
            guard !isHexColor(token) else { continue }
            let key = token.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            tags.append("#" + token)
        }
        return tags
    }

    public static func tagKeys(in content: String) -> [String] {
        tags(in: content).map { $0.lowercased() }
    }

    /// The first hashtag is the primary grouping key. A note has one group and
    /// one colour, even when it mentions more than one hashtag.
    public static func primaryTag(in content: String) -> String? {
        tags(in: content).first
    }

    public static func primaryTagKey(in content: String) -> String? {
        primaryTag(in: content)?.lowercased()
    }

    /// A new note that only carries its group's hashtag should still be
    /// discarded when the person closes the editor without writing anything.
    public static func isEffectivelyEmpty(_ content: String) -> Bool {
        var text = content
        for tag in tags(in: content) {
            text = text.replacingOccurrences(of: tag, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isHexColor(_ token: String) -> Bool {
        let isHex = token.range(of: "^[0-9A-Fa-f]{3,8}$", options: .regularExpression) != nil
        return isHex && token.contains(where: { $0.isNumber })
    }

    private static func headingParts(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        return (level, String(rest).trimmingCharacters(in: .whitespaces))
    }

    private static func checkboxParts(_ line: String) -> (checked: Bool, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let rest = line.dropFirst(marker.count)
            guard rest.hasPrefix("["), rest.count >= 4 else { continue }
            let characters = Array(rest)
            guard characters[0] == "[", characters[2] == "]" else { continue }
            guard characters[3] == " " else { continue }
            let state = characters[1]
            guard state == " " || state == "x" || state == "X" else { continue }
            let text = String(characters.dropFirst(4))
                .trimmingCharacters(in: .whitespaces)
            return (state != " ", text)
        }
        return nil
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespaces)
        }
        if let range = line.range(of: #"^\d{1,3}\.\s+"#, options: .regularExpression) {
            return String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact == "---" || compact == "***" || compact == "___"
    }
}
