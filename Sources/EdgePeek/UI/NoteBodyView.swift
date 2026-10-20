import EdgePeekCore
import SwiftUI

struct NoteBodyView: View {
    let lines: [NoteLine]
    var fontSize: CGFloat = 15
    var maxLines: Int = 12
    var lineLimit: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.prefix(maxLines))) { line in
                lineView(line)
            }
            if lines.count > maxLines {
                Text("还有 \(lines.count - maxLines) 行 · 点开看全部")
                    .font(Theme.mono(8.5, weight: .regular))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func lineView(_ line: NoteLine) -> some View {
        switch line.kind {
        case .heading(let level):
            Text(inline(line.text))
                .font(Theme.marker(level <= 2 ? fontSize + 4 : fontSize + 1.5))
                .foregroundStyle(Theme.ink)
                .padding(.top, level <= 2 ? 3 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .checkbox(let checked):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: fontSize - 3.5, weight: .medium))
                    .foregroundStyle(checked ? Theme.inkFaint : Theme.inkSoft)
                Text(inline(line.text))
                    .font(Theme.hand(fontSize))
                    .foregroundStyle(checked ? Theme.inkFaint : Theme.ink)
                    .strikethrough(checked, color: Theme.inkFaint)
                    .lineLimit(lineLimit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle()
                    .fill(Theme.inkSoft.opacity(0.75))
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: -3)
                Text(inline(line.text))
                    .font(Theme.hand(fontSize))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(lineLimit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 2)
                Text(inline(line.text))
                    .font(Theme.hand(fontSize))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(lineLimit)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code:
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: max(10, fontSize - 3), weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.ink.opacity(0.82))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.ink.opacity(0.045))
                )
                .lineLimit(lineLimit)

        case .divider:
            DashedRule(color: Theme.line.opacity(0.65))
                .padding(.vertical, 3)

        case .empty:
            Spacer()
                .frame(height: 3)

        case .text:
            Text(inline(line.text))
                .font(Theme.hand(fontSize))
                .foregroundStyle(Theme.ink)
                .lineSpacing(4)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }
}
