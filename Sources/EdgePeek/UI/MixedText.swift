import AppKit
import SwiftUI

/// The interface speaks two typographic languages: Chinese in the bundled old
/// Song face, Latin letters and numbers in a monospaced face. SwiftUI cannot
/// cascade fonts by script, so every run is built explicitly.
enum AppTypography {
    static func isChinese(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2FFF,   // radicals + kangxi
                 0x3000...0x303F,   // CJK punctuation
                 0x3040...0x30FF,   // kana
                 0x3100...0x312F,
                 0x31A0...0x31BF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0xFE30...0xFE4F,
                 0xFF00...0xFFEF,   // full-width forms
                 0x1F200...0x1F2FF,
                 0x20000...0x2FA1F:
                return true
            default:
                break
            }
            // Common Chinese punctuation that also lives in Latin ranges.
            return "，。、；：？！“”‘’—…《》「」（）【】·".unicodeScalars.contains(scalar)
        }
    }

    static func runs(in text: String) -> [(text: String, chinese: Bool)] {
        var result: [(String, Bool)] = []
        var buffer = ""
        var bufferIsChinese: Bool?

        for character in text {
            let chinese = isChinese(character)
            if bufferIsChinese == chinese {
                buffer.append(character)
            } else {
                if !buffer.isEmpty, let bufferIsChinese {
                    result.append((buffer, bufferIsChinese))
                }
                buffer = String(character)
                bufferIsChinese = chinese
            }
        }
        if !buffer.isEmpty, let bufferIsChinese {
            result.append((buffer, bufferIsChinese))
        }
        return result
    }

    static func attributed(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight = .regular,
        color: Color = Theme.ink
    ) -> AttributedString {
        var result = AttributedString()
        for run in runs(in: text) {
            var part = AttributedString(run.text)
            part.font = run.chinese
                ? Theme.serif(size)
                : Theme.mono(size, weight: weight)
            part.foregroundColor = color
            result.append(part)
        }
        return result
    }

    static func fontName(chinese: Bool) -> String {
        chinese ? AppFonts.chineseName : "SFMono-Regular"
    }

    static func nsFont(
        chinese: Bool,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSFont {
        if chinese {
            return NSFont(name: AppFonts.chineseName, size: size)
                ?? NSFont.systemFont(ofSize: size, weight: weight)
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Apply the two-script treatment to an AppKit text storage. Hashtags are
    /// tinted like the tags on a paper note, but no Markdown syntax is shown.
    static func applyAttributes(
        to storage: NSTextStorage,
        size: CGFloat,
        textColor: NSColor,
        accentColor: NSColor,
        lineSpacing: CGFloat = 6
    ) {
        let string = storage.string
        guard !string.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = 1
        paragraph.lineBreakMode = .byWordWrapping

        let base: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]

        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))

        var location = 0
        for run in runs(in: string) {
            let length = (run.text as NSString).length
            let range = NSRange(location: location, length: length)
            if length > 0 {
                storage.addAttribute(
                    .font,
                    value: nsFont(chinese: run.chinese, size: size),
                    range: range
                )
            }
            location += length
        }

        let pattern = "#[\\p{L}\\p{N}_\\-]{1,32}"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let fullRange = NSRange(location: 0, length: storage.length)
            for match in regex.matches(in: string, range: fullRange) {
                let token = (string as NSString).substring(with: match.range)
                let body = token.dropFirst()
                let isHex = body.range(
                    of: "^[0-9A-Fa-f]{3,8}$",
                    options: .regularExpression
                ) != nil && body.contains(where: \.isNumber)
                if !isHex {
                    storage.addAttribute(.foregroundColor, value: accentColor, range: match.range)
                }
            }
        }

        storage.endEditing()
    }
}

struct MixedText: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight
    var color: Color
    var lineSpacing: CGFloat
    var lineLimit: Int?
    var alignment: TextAlignment
    var tracking: CGFloat

    init(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight = .regular,
        color: Color = Theme.ink,
        lineSpacing: CGFloat = 0,
        lineLimit: Int? = nil,
        alignment: TextAlignment = .leading,
        tracking: CGFloat = 0
    ) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
        self.lineSpacing = lineSpacing
        self.lineLimit = lineLimit
        self.alignment = alignment
        self.tracking = tracking
    }

    var body: some View {
        Text(
            AppTypography.attributed(
                text,
                size: size,
                weight: weight,
                color: color
            )
        )
        .lineSpacing(lineSpacing)
        .multilineTextAlignment(alignment)
        .lineLimit(lineLimit)
        .tracking(tracking)
        .textSelection(.disabled)
    }
}
