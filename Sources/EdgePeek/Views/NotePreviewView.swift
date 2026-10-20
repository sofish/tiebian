import EdgePeekCore
import SwiftUI

struct NotePreviewView: View {
    let note: StickyNote
    let edge: EdgeSide
    var onHover: (Bool) -> Void = { _ in }
    var onOpen: () -> Void = {}

    @State private var appeared = false
    @State private var hovering = false

    private var bodyLines: [NoteLine] {
        NoteText.bodyLinesForDisplay(from: note.content)
    }

    private var tags: [String] {
        NoteText.tags(in: note.content)
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

            Text(note.title.isEmpty ? "空白便签" : note.title)
                .font(Theme.hand(24))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .lineSpacing(1)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                .padding(.top, 8)
            }

            DashedRule(color: note.color.paperEdge.opacity(0.65))
                .padding(.top, 11)
                .padding(.bottom, 9)

            if bodyLines.contains(where: { $0.kind != .empty }) {
                NoteBodyView(
                    lines: bodyLines,
                    fontSize: 15,
                    maxLines: 11,
                    lineLimit: 3
                )
            } else {
                Text("点开，写几句。")
                    .font(Theme.hand(14))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.vertical, 2)
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
