import EdgePeekCore
import SwiftUI

struct NotePreviewView: View {
    let note: StickyNote
    let edge: EdgeSide
    var onHover: (Bool) -> Void
    var onOpen: () -> Void

    private let content: String
    private let tags: [String]

    @State private var appeared = false
    @State private var hovering = false

    static let contentSize: CGFloat = 15.5
    private static let contentSpacing: CGFloat = 4
    private static let chromeHeight: CGFloat = 150
    private static let minimumLines = 6
    private static let estimatedMaximumLines = 16

    /// The preview is allowed to omit the tail, but only when the copy truly
    /// cannot fit: it shows every line it can before truncating.
    private static let contentLineLimit: Int = {
        let lineHeight = AppTypography.lineHeight(size: contentSize, spacing: contentSpacing)
        return max(minimumLines, Int(floor((Layout.previewMaxHeight - chromeHeight) / lineHeight)))
    }()

    /// Height used only when AppKit cannot measure the preview (for example
    /// before the view has a window). Keeps the fallback on the same metrics
    /// as the view instead of a second set of magic numbers.
    static func estimatedHeight(for note: StickyNote) -> CGFloat {
        let lineCount = min(
            note.displayText.components(separatedBy: "\n").count,
            estimatedMaximumLines
        )
        var height = chromeHeight
            + CGFloat(lineCount) * AppTypography.lineHeight(size: contentSize, spacing: contentSpacing)
        if note.dueAt != nil { height += 8 }
        if !NoteText.tags(in: note.content).isEmpty { height += 22 }
        return height
    }

    init(
        note: StickyNote,
        edge: EdgeSide,
        onHover: @escaping (Bool) -> Void = { _ in },
        onOpen: @escaping () -> Void = {}
    ) {
        self.note = note
        self.edge = edge
        self.onHover = onHover
        self.onOpen = onOpen
        self.content = note.displayText
        self.tags = NoteText.tags(in: note.content)
    }

    var body: some View {
        Button(action: onOpen) {
            paper
            .frame(width: Layout.previewWidth)
            .scaleEffect(appeared ? (hovering ? 1.006 : 1) : 0.96)
            .opacity(appeared ? 1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover {
            hovering = $0
            onHover($0)
        }
        .onAppear {
            withAnimation(Theme.spring) {
                appeared = true
            }
        }
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(note.color.dot)
                    .frame(width: 4.5, height: 4.5)
                Text("贴边 / NOTE")
                    .font(Theme.mono(7.4, weight: .semibold))
                    .tracking(1.2)
                Rectangle()
                    .fill(Theme.inkSoft.opacity(0.25))
                    .frame(width: 12, height: 0.6)
                Text(DateText.stamp(note.updatedAt))
                    .font(Theme.mono(7.4, weight: .regular))
                Spacer(minLength: 4)
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(note.color.displayName)
                    .font(Theme.mono(7.2, weight: .regular))
            }
            .foregroundStyle(Theme.inkSoft.opacity(0.9))
            .padding(.top, 2)

            DashedRule(color: note.color.paperEdge.opacity(0.65))
                .padding(.top, 12)
                .padding(.bottom, 10)

            if content.isEmpty {
                Text("点开，写几句。")
                    .font(Theme.hand(14))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.vertical, 2)
            } else {
                MixedText(
                    content,
                    size: Self.contentSize,
                    color: Theme.ink,
                    lineSpacing: Self.contentSpacing,
                    lineLimit: Self.contentLineLimit
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(tags.prefix(4)), id: \.self) { tag in
                        Text(tag)
                            .font(Theme.mono(7.2, weight: .medium))
                            .foregroundStyle(Theme.accentDeep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(Theme.accent.opacity(0.09))
                            )
                    }
                    if tags.count > 4 {
                        Text("+\(tags.count - 4)")
                            .font(Theme.mono(7, weight: .regular))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                .padding(.top, 9)
            }

            HStack(spacing: 6) {
                if let dueAt = note.dueAt {
                    Image(systemName: "clock")
                        .font(.system(size: 7, weight: .medium))
                    Text(note.isOverdue ? "已到期 · \(DateText.dueFull(dueAt))" : DateText.dueFull(dueAt))
                        .font(Theme.mono(7.6, weight: note.isOverdue ? .semibold : .regular))
                        .lineLimit(1)
                } else {
                    Text("点击打开便签")
                        .font(Theme.mono(8, weight: .regular))
                }
                Spacer()
                Text("编辑")
                    .font(Theme.mono(8, weight: .medium))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .foregroundStyle(
                note.isOverdue
                    ? Theme.accentDeep
                    : Theme.inkFaint
            )
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: Layout.previewWidth)
        .background(PaperBackground(color: note.color, cornerRadius: 18))
        .overlay(alignment: .leading) {
            if note.isOverdue {
                Capsule()
                    .fill(Theme.accent.opacity(0.8))
                    .frame(width: 2.5)
                    .padding(.vertical, 14)
                    .padding(.leading, 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
